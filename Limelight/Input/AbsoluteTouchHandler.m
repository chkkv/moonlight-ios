//
//  AbsoluteTouchHandler.m
//  Moonlight
//
//  Created by Cameron Gutman on 11/1/20.
//  Copyright © 2020 Moonlight Game Streaming Project. All rights reserved.
//

#import "AbsoluteTouchHandler.h"

#include <Limelight.h>

#import <objc/runtime.h>

// UIEvent hands out recycled UITouch objects, so a pointer id parked on one is
// only valid for the lifetime of that touch and is cleared on up/cancel.
static const void* kPointerIdKey = &kPointerIdKey;

// How long the fingers must be stationary to start a right click
#define LONG_PRESS_ACTIVATION_DELAY 0.650f

// How far the finger can move before it cancels a right click
#define LONG_PRESS_ACTIVATION_DELTA 0.01f

// How long the double tap deadzone stays in effect between touch up and touch down
#define DOUBLE_TAP_DEAD_ZONE_DELAY 0.250f

// How far the finger can move before it can override the double tap deadzone
#define DOUBLE_TAP_DEAD_ZONE_DELTA 0.025f

@implementation AbsoluteTouchHandler {
    StreamView* view;
    BOOL multitouchMode;
    uint32_t nextPointerId;
    
    NSTimer* longPressTimer;
    UITouch* lastTouchDown;
    CGPoint lastTouchDownLocation;
    UITouch* lastTouchUp;
    CGPoint lastTouchUpLocation;
}

- (id)initWithView:(StreamView*)view multitouch:(BOOL)multitouch {
    self = [self init];
    self->view = view;
    self->multitouchMode = multitouch;
    return self;
}

// ---------------------------------------------------------------------------
// Multitouch forwarding
//
// The host sees a real touchscreen: each finger keeps its own pointerId for the
// duration of the touch, and down/move/up are reported per finger. This replaces
// the absolute-mouse emulation below entirely rather than running alongside it,
// so a single finger is a touch here and never also a mouse click.
// ---------------------------------------------------------------------------

- (uint32_t)pointerIdForTouch:(UITouch*)touch {
    NSNumber* existing = objc_getAssociatedObject(touch, kPointerIdKey);
    if (existing != nil) {
        return (uint32_t)existing.unsignedIntValue;
    }
    
    uint32_t assigned = nextPointerId++;
    objc_setAssociatedObject(touch, kPointerIdKey, @(assigned), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return assigned;
}

- (void)forgetTouch:(UITouch*)touch {
    objc_setAssociatedObject(touch, kPointerIdKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)sendTouch:(UITouch*)touch type:(uint8_t)type {
    CGSize videoSize = [view getVideoAreaSize];
    if (videoSize.width <= 0.0 || videoSize.height <= 0.0) {
        return;
    }
    
    CGPoint location = [view adjustCoordinatesForVideoArea:[touch locationInView:view]];
    
    // Force is only meaningful on hardware that reports it. Falling back to 1.0
    // keeps hosts that read zero pressure as "not touching" working on the rest.
    float pressure = 1.0f;
    if (touch.maximumPossibleForce > 0.0) {
        pressure = (float)(touch.force / touch.maximumPossibleForce);
    }
    
    LiSendTouchEvent(type, [self pointerIdForTouch:touch],
                     (float)(location.x / videoSize.width),
                     (float)(location.y / videoSize.height),
                     pressure, 0.0f, 0.0f, LI_ROT_UNKNOWN);
}

- (void)onLongPressStart:(NSTimer*)timer {
    // Raise the left click and start a right click
    LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_RIGHT);
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if (multitouchMode) {
        for (UITouch* touch in touches) {
            [self sendTouch:touch type:LI_TOUCH_EVENT_DOWN];
        }
        return;
    }
    
    // Ignore touch down events with more than one finger
    if ([[event allTouches] count] > 1) {
        return;
    }
    
    UITouch* touch = [touches anyObject];
    CGPoint touchLocation = [touch locationInView:view];
    
    // Don't reposition for finger down events within the deadzone. This makes double-clicking easier.
    if (touch.timestamp - lastTouchUp.timestamp > DOUBLE_TAP_DEAD_ZONE_DELAY ||
        sqrt(pow((touchLocation.x / view.bounds.size.width) - (lastTouchUpLocation.x / view.bounds.size.width), 2) +
             pow((touchLocation.y / view.bounds.size.height) - (lastTouchUpLocation.y / view.bounds.size.height), 2)) > DOUBLE_TAP_DEAD_ZONE_DELTA) {
        [view updateCursorLocation:touchLocation isMouse:NO];
    }
    
    // Press the left button down
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
    
    // Start the long press timer
    longPressTimer = [NSTimer scheduledTimerWithTimeInterval:LONG_PRESS_ACTIVATION_DELAY
                                                      target:self
                                                    selector:@selector(onLongPressStart:)
                                                    userInfo:nil
                                                     repeats:NO];
    
    lastTouchDown = touch;
    lastTouchDownLocation = touchLocation;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if (multitouchMode) {
        for (UITouch* touch in touches) {
            [self sendTouch:touch type:LI_TOUCH_EVENT_MOVE];
        }
        return;
    }
    
    // Ignore touch move events with more than one finger
    if ([[event allTouches] count] > 1) {
        return;
    }
    
    UITouch* touch = [touches anyObject];
    CGPoint touchLocation = [touch locationInView:view];
    
    if (sqrt(pow((touchLocation.x / view.bounds.size.width) - (lastTouchDownLocation.x / view.bounds.size.width), 2) +
             pow((touchLocation.y / view.bounds.size.height) - (lastTouchDownLocation.y / view.bounds.size.height), 2)) > LONG_PRESS_ACTIVATION_DELTA) {
        // Moved too far since touch down. Cancel the long press timer.
        [longPressTimer invalidate];
        longPressTimer = nil;
    }
    
    [view updateCursorLocation:[[touches anyObject] locationInView:view] isMouse:NO];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if (multitouchMode) {
        for (UITouch* touch in touches) {
            [self sendTouch:touch type:LI_TOUCH_EVENT_UP];
            [self forgetTouch:touch];
        }
        return;
    }
    
    // Only fire this logic if all touches have ended
    if ([[event allTouches] count] == [touches count]) {
        // Cancel the long press timer
        [longPressTimer invalidate];
        longPressTimer = nil;

        // Left button up on finger up
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);

        // Raise right button too in case we triggered a long press gesture
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_RIGHT);
        
        // Remember this last touch for touch-down deadzoning
        lastTouchUp = [touches anyObject];
        lastTouchUpLocation = [lastTouchUp locationInView:view];
    }
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    if (multitouchMode) {
        for (UITouch* touch in touches) {
            // Only the pointerId is meaningful for a cancel.
            LiSendTouchEvent(LI_TOUCH_EVENT_CANCEL, [self pointerIdForTouch:touch],
                             0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0);
            [self forgetTouch:touch];
        }
        return;
    }
    
    // Treat this as a normal touchesEnded event
    [self touchesEnded:touches withEvent:event];
}

@end
