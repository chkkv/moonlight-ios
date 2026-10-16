//
//  CustomControlsView.h
//  Moonlight
//
//  Transparent, top-most overlay that renders a user-authored control layout
//  and forwards input to the virtual gamepad.
//
//  PASSTHROUGH CONTRACT
//  --------------------
//  A plain full-screen UIView swallows every touch inside its bounds, because
//  -hitTest:withEvent: returns self for any point that does not land on a
//  subview. This view therefore overrides -hitTest:withEvent: to return nil
//  unless the point lands on one of its controls, so untouched areas keep
//  reaching the relative/absolute touch handlers and the zoom/pan scroll view
//  underneath. Removing that override breaks all stream touch input.
//
//  INPUT MODEL
//  -----------
//  Digital flags are committed by diffing the aggregate desired state against
//  what was last sent. That makes two controls bound to the same button behave
//  correctly (the flag stays set while either is held) and makes a cancelled
//  touch release everything without any per-control bookkeeping. Analog values
//  are written directly, which is why CustomLayoutDocument rejects two controls
//  driving the same analog axis.
//
//  Keyboard keys are a separate channel: they go straight to
//  LiSendKeyboardEvent rather than through ControllerSupport, and the same diff
//  is applied to the set of held VK codes. Modifier keys are held as real key
//  downs so their bits travel with every later key event.
//
//  STICKY CONTROLS
//  ---------------
//  A control marked sticky latches on touch-down instead of being held, and a
//  second tap releases it. That is what makes a modifier usable on a touch
//  screen, where holding Ctrl and pressing C with one hand is impossible.
//
//  SPECIAL STICKS
//  --------------
//  A special stick looks and drags like an analog stick but emits digital inputs:
//  whichever of its four directions are pushed past the control's dead zone
//  assert the input bound to them, which can be a gamepad button or a keyboard
//  key. That dead zone is the only distance that applies, since a special stick
//  has no analog output for a separate one to shape, so it doubles as the
//  sensitivity control. Diagonals assert two directions at once, and the results
//  feed the same flag and key diffs as everything else.
//

#import <UIKit/UIKit.h>

// Posted when a control bound to CustomBindingKindShowKeyboard is tapped, so the
// overlay can ask for the software keyboard without holding a reference to the
// view that owns it. StreamView is the only observer.
extern NSNotificationName const CustomControlsViewShowKeyboardNotification;

#import "CustomLayoutDocument.h"

@class ControllerSupport;

@interface CustomControlsView : UIView

- (instancetype)initWithLayout:(CustomLayoutDocument *)layout
             controllerSupport:(ControllerSupport *)controllerSupport;

// Replaces the layout and rebuilds the control layers.
- (void)setLayout:(CustomLayoutDocument *)layout;

// Clears all touch state and releases everything currently held. Safe to call
// repeatedly and from the main thread only.
- (void)releaseAllInputs;

@end
