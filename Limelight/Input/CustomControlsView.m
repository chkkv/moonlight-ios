//
//  CustomControlsView.m
//  Moonlight
//

#import "CustomControlsView.h"
#import "ControllerSupport.h"
#import "Controller.h"

#include <math.h>
#include "Limelight.h"

// Full scale for the analog sticks. Matches what OnScreenControls sends.
static const short kStickFullScale = 0x7FFE;

NSNotificationName const CustomControlsViewShowKeyboardNotification = @"CustomControlsViewShowKeyboard";

static const CGFloat kControlLabelFontSize = 15.0;

// The font used for a control's label. The runtime draws labels with a
// CATextLayer rather than a UILabel, and CATextLayer has no vertical centring, so
// this font's line height is what the label layer gets sized to.
static UIFont *CustomControlLabelFont(void) {
    return [UIFont systemFontOfSize:kControlLabelFontSize weight:UIFontWeightSemibold];
}

// The artwork for a control, or nil when it has none. Both call sites share this
// so the border rule below cannot drift between them.
static UIImage *CustomControlImage(CustomControl *control) {
    return control.icon.length ? [UIImage imageNamed:control.icon] : nil;
}

#pragma mark - CustomControlItem

@interface CustomControlItem : NSObject

@property (nonatomic, strong) CustomControl *control;
@property (nonatomic, strong) CALayer *layer;
@property (nonatomic, strong, nullable) CALayer *knobLayer;
@property (nonatomic, strong, nullable) CATextLayer *labelLayer;

// Owned touch, nil when the control is idle. One touch owns at most one control.
@property (nonatomic, weak, nullable) UITouch *touch;

// Sticky controls latch instead of tracking a finger: a tap flips this.
@property (nonatomic) BOOL latched;

// Suppressed because a hide-others control is currently latched: this control
// must not be hit-testable and must not hold input.
@property (nonatomic) BOOL soloHidden;

// Layers hidden. Deliberately separate from soloHidden because the latched
// hide-others control hides itself yet has to keep capturing taps where it is,
// otherwise there would be no way to bring everything back.
@property (nonatomic) BOOL soloInvisible;

// Normalised stick deflection, already in gamepad orientation (+y is up).
@property (nonatomic) CGPoint stickVector;

// The same deflection before the dead zone is applied, used to draw the knob.
// The knob belongs to the finger, not to the output: driving it from the
// dead-zoned vector would pin it to the centre and then make it jump the moment
// the dead zone was crossed, which is very visible now that the dead zone also
// serves as the direction threshold.
@property (nonatomic) CGPoint stickDisplay;

// Rendered frame in this view's coordinate space, refreshed on layout.
@property (nonatomic) CGRect renderedFrame;

@end

@implementation CustomControlItem

// Whether the control is asserting its input right now.
- (BOOL)isAsserted {
    if (self.control.sticky && self.control.type != CustomControlTypeStick) {
        return self.latched;
    }
    return self.touch != nil;
}

@end

#pragma mark - CustomControlsView

// Private surface, declared up front so the implementation order is irrelevant.
@interface CustomControlsView ()
- (void)buildItems;
- (void)layoutControlLayers;
- (void)updateKnobForItem:(CustomControlItem *)item;
- (NSUInteger)itemIndexAtPoint:(CGPoint)point;
- (CustomControlItem *)itemForTouch:(UITouch *)touch;
- (void)endTouches:(NSSet<UITouch *> *)touches;
- (void)commitState;
- (NSUInteger)activeDirectionsForItem:(CustomControlItem *)item;
- (int)directionButtonFlagsForItem:(CustomControlItem *)item;
- (void)commitKeyboardState;
- (void)updateMouseMovementTimer;
- (void)mouseTick:(CADisplayLink *)link;
- (BOOL)mouseControlIsActive:(CustomControlItem *)item;
- (CGPoint)mouseVectorForItem:(CustomControlItem *)item;
- (void)applySoloVisibility;
- (void)pressKeyCode:(uint16_t)keyCode modifiers:(char)modifiers;
- (void)releaseKeyCode:(uint16_t)keyCode modifiers:(char)modifiers;
- (void)reflectLatchedStateForItem:(CustomControlItem *)item;
- (void)updateStickVectorForItem:(CustomControlItem *)item atPoint:(CGPoint)point;
@end

@implementation CustomControlsView {
    CustomLayoutDocument *_layout;
    ControllerSupport *_controllerSupport;
    Controller *_oscController;
    NSMutableArray<CustomControlItem *> *_items;

    // Digital flags last handed to ControllerSupport, used to compute the diff.
    int _appliedButtonFlags;

    // YES once anything has actually been sent. Construction and the initial
    // setLayout: both run before the stream connection exists, and emitting an
    // all-zero controller event there would report a controller that never
    // sends anything.
    BOOL _hasCommitted;

    // Keyboard state. Unlike controller input this does not go through
    // ControllerSupport at all; LiSendKeyboardEvent is called directly.
    //
    // _appliedKeyCodes is the set of VK codes the host currently believes are
    // held, which is what makes the diff work for sticky keys too.
    NSMutableSet<NSNumber *> *_appliedKeyCodes;
    // Modifier bits of the keys in _appliedKeyCodes, sent with every key event.
    char _appliedKeyModifiers;

    // Runs only while a mouse control is asserted, so an idle overlay costs
    // nothing. Continuous motion needs ticks; there is no "drag" to piggyback on.
    CADisplayLink *_mouseLink;
}

- (instancetype)initWithLayout:(CustomLayoutDocument *)layout
             controllerSupport:(ControllerSupport *)controllerSupport {
    self = [super initWithFrame:CGRectZero];
    if (self == nil) {
        return nil;
    }

    _controllerSupport = controllerSupport;
    _oscController = [controllerSupport getOscController];
    _items = [[NSMutableArray alloc] init];
    _appliedButtonFlags = 0;
    _appliedKeyCodes = [[NSMutableSet alloc] init];
    _appliedKeyModifiers = 0;

    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.multipleTouchEnabled = YES;
    self.userInteractionEnabled = YES;

    [self setLayout:layout];

    return self;
}

- (void)setLayout:(CustomLayoutDocument *)layout {
    _layout = layout;

    // Release anything held by the outgoing layout before its layers vanish.
    [self releaseAllInputs];

    for (CustomControlItem *item in _items) {
        [item.layer removeFromSuperlayer];
        [item.knobLayer removeFromSuperlayer];
    }
    [_items removeAllObjects];

    [self buildItems];
    [self setNeedsLayout];
}

// ---------------------------------------------------------------------------
// Layers
// ---------------------------------------------------------------------------

- (void)buildItems {
    for (CustomControl *control in _layout.controls) {
        CustomControlItem *item = [[CustomControlItem alloc] init];
        item.control = control;
        item.layer = [CALayer layer];
        item.layer.masksToBounds = NO;

        UIImage *image = CustomControlImage(control);
        if (image != nil) {
            item.layer.contents = (__bridge id)image.CGImage;
            item.layer.contentsGravity = kCAGravityResizeAspect;
        } else {
            item.layer.backgroundColor = [[UIColor colorWithWhite:1.0 alpha:0.18] CGColor];
            item.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.45] CGColor];
            item.layer.borderWidth = 1.0;
            item.layer.cornerRadius = 10.0;
        }

        [_items addObject:item];
        [self.layer addSublayer:item.layer];
        [self reflectLatchedStateForItem:item];

        if (control.type == CustomControlTypeStick) {
            CALayer *knob = [CALayer layer];
            UIImage *knobImage = [UIImage imageNamed:@"StickInner"];
            if (knobImage != nil) {
                knob.contents = (__bridge id)knobImage.CGImage;
                knob.contentsGravity = kCAGravityResizeAspect;
            } else {
                knob.backgroundColor = [[UIColor colorWithWhite:1.0 alpha:0.35] CGColor];
            }
            item.knobLayer = knob;
            // A standalone CALayer animates its property changes implicitly for
            // about a quarter of a second, unlike a UIView's backing layer.
            // While the thumb is moving a new position arrives every 8-16ms, so
            // each of those animations is replaced long before it finishes and
            // the knob only travels a fraction of the way: it crawls along
            // behind the finger instead of sitting under it. Touch-down looked
            // right because a single assignment is allowed to complete. Nothing
            // here should ever be animated.
            knob.actions = @{ @"position": [NSNull null], @"bounds": [NSNull null] };
            // Sibling of the ring rather than a child, so it can be positioned
            // directly in view coordinates.
            [self.layer addSublayer:knob];
        }

        // A text label is only needed when there is no artwork to draw.
        if (image == nil && control.label.length) {
            CATextLayer *text = [CATextLayer layer];

            // An attributed string carries the font as an ordinary object, so
            // there is no CF ownership to get wrong, and it pins the very font
            // whose line height the layout uses to centre the text.
            NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
            paragraph.alignment = NSTextAlignmentCenter;
            paragraph.lineBreakMode = NSLineBreakByTruncatingTail;

            text.string = [[NSAttributedString alloc] initWithString:control.label
                                                          attributes:@{ NSFontAttributeName: CustomControlLabelFont(),
                                                                        NSForegroundColorAttributeName: [UIColor whiteColor],
                                                                        NSParagraphStyleAttributeName: paragraph }];
            text.alignmentMode = kCAAlignmentCenter;
            // A label wider than its control is truncated rather than spilling
            // over the neighbouring controls.
            text.truncationMode = kCATruncationEnd;
            text.contentsScale = [UIScreen mainScreen].scale;
            item.labelLayer = text;
            [self.layer addSublayer:text];
        }
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self layoutControlLayers];
}

- (void)safeAreaInsetsDidChange {
    [super safeAreaInsetsDidChange];
    [self layoutControlLayers];
}

- (void)layoutControlLayers {
    UIEdgeInsets safeInsets = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) {
        safeInsets = self.safeAreaInsets;
    }

    CGSize bounds = self.bounds.size;

    for (CustomControlItem *item in _items) {
        CustomControl *control = item.control;

        // Shared with the editor preview so the two cannot drift apart.
        CGSize size = [control renderedSize];
        CGPoint center = [control renderedCenterInBounds:bounds safeInsets:safeInsets];
        CGRect frame = CGRectMake(center.x - size.width / 2.0,
                                  center.y - size.height / 2.0,
                                  size.width,
                                  size.height);
        item.renderedFrame = frame;

        item.layer.bounds = CGRectMake(0, 0, size.width, size.height);
        item.layer.position = center;

        if (item.knobLayer != nil) {
            CGSize knobSize = CGSizeMake(size.width * 0.42, size.height * 0.42);
            item.knobLayer.bounds = CGRectMake(0, 0, knobSize.width, knobSize.height);
            item.knobLayer.cornerRadius = knobSize.width / 2.0;
            item.knobLayer.position = center;
        }

        if (item.labelLayer != nil) {
            // CATextLayer draws its line against the top of its bounds and has no
            // vertical centring, so give it exactly one line and centre that.
            // Without this a single-line label sits on the top edge of the
            // control instead of in the middle.
            CGFloat lineHeight = ceil(CustomControlLabelFont().lineHeight);
            item.labelLayer.bounds = CGRectMake(0, 0, size.width, lineHeight);
            item.labelLayer.position = center;
        }

        if (item.layer != nil) {
            item.layer.hidden = item.soloInvisible;
        }
        if (item.knobLayer != nil) {
            item.knobLayer.hidden = item.soloInvisible;
        }
        if (item.labelLayer != nil) {
            item.labelLayer.hidden = item.soloInvisible;
        }

        [self updateKnobForItem:item];
    }
}

- (void)updateKnobForItem:(CustomControlItem *)item {
    if (item.knobLayer == nil) {
        return;
    }

    CGRect frame = item.renderedFrame;
    CGFloat radius = CGRectGetWidth(frame) / 2.0;
    CGPoint center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));

    // The knob tracks the finger one to one and simply stops once it meets the
    // rim. Scaling the offset instead - which is what this used to do, reusing
    // the travel limit as a motion ratio - made the knob move at only a fraction
    // of the finger's movement at every distance, so it never felt attached.
    // stickDisplay is in gamepad orientation, so flip y back for display.
    CGPoint display = item.stickDisplay;
    CGFloat length = sqrt(display.x * display.x + display.y * display.y);
    if (length <= 0.0) {
        item.knobLayer.position = center;
        return;
    }

    // Keep the knob inside the control: its own radius comes out of the travel.
    CGFloat knobRadius = CGRectGetWidth(item.knobLayer.bounds) / 2.0;
    CGFloat travel = MAX(radius - knobRadius, 0.0);
    CGFloat distance = MIN(MIN(length, 1.0) * radius, travel);

    item.knobLayer.position =
        CGPointMake(center.x + display.x / length * distance,
                    center.y - display.y / length * distance);
}

// ---------------------------------------------------------------------------
// Passthrough hit testing
// ---------------------------------------------------------------------------

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || !self.userInteractionEnabled || self.alpha < 0.01) {
        return nil;
    }

    // Decline everything that is not a control so the touch reaches the stream
    // view (touch handling) or the enclosing scroll view (pinch/pan).
    if ([self itemIndexAtPoint:point] == (NSUInteger)NSNotFound) {
        return nil;
    }

    return self;
}

- (NSUInteger)itemIndexAtPoint:(CGPoint)point {
    for (NSUInteger i = 0; i < _items.count; i++) {
        // A control hidden by a hide-others toggle must not swallow touches.
        if (_items[i].soloHidden) {
            continue;
        }
        if (CGRectContainsPoint(_items[i].renderedFrame, point)) {
            return i;
        }
    }
    return (NSUInteger)NSNotFound;
}

- (CustomControlItem *)itemForTouch:(UITouch *)touch {
    for (CustomControlItem *item in _items) {
        if (item.touch == touch) {
            return item;
        }
    }
    return nil;
}

// ---------------------------------------------------------------------------
// Touch handling
// ---------------------------------------------------------------------------

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        CGPoint point = [touch locationInView:self];
        NSUInteger index = [self itemIndexAtPoint:point];
        if (index == (NSUInteger)NSNotFound) {
            continue;
        }

        CustomControlItem *item = _items[index];

        // Show-keyboard sends nothing either: the keyboard is the whole effect, and
        // it belongs to StreamView's private text field, so this asks for it rather
        // than reaching for it.
        if (item.control.bindingKind == CustomBindingKindShowKeyboard) {
            [[NSNotificationCenter defaultCenter] postNotificationName:CustomControlsViewShowKeyboardNotification
                                                                object:self];
            continue;
        }

        // Hide-others is a pure toggle: it sends nothing, it just gets the other
        // controls out of the way. Its own tap is what brings them back.
        if (item.control.bindingKind == CustomBindingKindHideOthers) {
            item.latched = !item.latched;
            [self applySoloVisibility];
            [self reflectLatchedStateForItem:item];
            continue;
        }

        // A sticky control latches on touch-down, so the tap feels immediate and
        // the second tap releases it. It deliberately does not keep the touch:
        // the finger has no further role until the next tap.
        if (item.control.sticky && item.control.type != CustomControlTypeStick) {
            item.latched = !item.latched;
            [self reflectLatchedStateForItem:item];
            continue;
        }

        if (item.touch != nil) {
            // Already driven by another finger.
            continue;
        }

        item.touch = touch;
        item.stickVector = CGPointZero;
        item.stickDisplay = CGPointZero;
        if (item.control.type == CustomControlTypeStick) {
            [self updateStickVectorForItem:item atPoint:point];
        }
    }

    [self commitState];
}

// Gives a latched (or released) sticky control a visible pressed state, since
// there is no finger holding it that would otherwise show what is active.
- (void)reflectLatchedStateForItem:(CustomControlItem *)item {
    // Hide-others is always a latch; sticky controls latch when so configured.
    BOOL usesLatch = item.control.bindingKind == CustomBindingKindHideOthers ||
                     (item.control.sticky && ![item.control isStickShaped]);
    if (!usesLatch) {
        return;
    }

    BOOL latched = item.latched;
    item.layer.transform = latched ? CATransform3DMakeScale(0.92, 0.92, 1.0) : CATransform3DIdentity;

    if (latched) {
        item.layer.borderColor = [[UIColor systemYellowColor] CGColor];
        item.layer.borderWidth = 3.0;
        return;
    }

    // Restore whatever buildItems set for this kind of control.
    UIImage *image = CustomControlImage(item.control);
    if (image != nil) {
        item.layer.borderWidth = 0.0;
    } else {
        item.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.45] CGColor];
        item.layer.borderWidth = 1.0;
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    BOOL changed = NO;

    for (UITouch *touch in touches) {
        CustomControlItem *item = [self itemForTouch:touch];
        if (item == nil || item.control.type != CustomControlTypeStick) {
            // Buttons deliberately do not slide between controls in v1.
            continue;
        }

        [self updateStickVectorForItem:item atPoint:[touch locationInView:self]];
        changed = YES;
    }

    if (changed) {
        [self commitState];
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self endTouches:touches];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    // A cancelled touch must release its input, otherwise the control sticks on.
    [self endTouches:touches];
}

- (void)endTouches:(NSSet<UITouch *> *)touches {
    for (UITouch *touch in touches) {
        CustomControlItem *item = [self itemForTouch:touch];
        if (item == nil) {
            continue;
        }

        item.touch = nil;
        item.stickVector = CGPointZero;
        item.stickDisplay = CGPointZero;
        [self updateKnobForItem:item];
    }

    [self commitState];
}

- (void)releaseAllInputs {
    for (CustomControlItem *item in _items) {
        item.touch = nil;
        item.stickVector = CGPointZero;
        item.stickDisplay = CGPointZero;
        // Clear latches too, otherwise a sticky Ctrl would still be held on the
        // host after the stream ends.
        item.latched = NO;
        item.soloHidden = NO;
        item.soloInvisible = NO;
        [self updateKnobForItem:item];
        [self reflectLatchedStateForItem:item];
    }

    [self layoutControlLayers];
    [self commitState];
}

- (void)updateStickVectorForItem:(CustomControlItem *)item atPoint:(CGPoint)point {
    CGRect frame = item.renderedFrame;
    CGPoint center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    CGFloat radius = MAX(CGRectGetWidth(frame) / 2.0, 1.0);

    CGFloat dx = (point.x - center.x) / radius;
    CGFloat dy = (point.y - center.y) / radius;

    CGFloat length = sqrt(dx * dx + dy * dy);
    if (length > 1.0) {
        dx /= length;
        dy /= length;
        length = 1.0;
    }

    // Screen +y points down, gamepad +y points up. The knob is driven by this
    // raw, clamped deflection so it stays under the finger at every distance.
    item.stickDisplay = CGPointMake(dx, -dy);

    if (length < item.control.deadZone) {
        dx = 0.0;
        dy = 0.0;
    }

    item.stickVector = CGPointMake(dx, -dy);
    [self updateKnobForItem:item];
}

// ---------------------------------------------------------------------------
// State commit
// ---------------------------------------------------------------------------

- (void)commitState {
    int desiredFlags = 0;
    short leftX = 0, leftY = 0, rightX = 0, rightY = 0;
    unsigned char leftTrigger = 0, rightTrigger = 0;

    for (CustomControlItem *item in _items) {
        CustomControl *control = item.control;

        // Keyboard keys are a separate channel and are handled below.
        if (control.bindingKind == CustomBindingKindKey) {
            continue;
        }

        if (control.bindingKind == CustomBindingKindButton) {
            // A sticky button or trigger stays asserted without a finger, which
            // is what makes a toggle-style control possible.
            if ([item isAsserted]) {
                desiredFlags |= (int)control.buttonFlag;
            }
            continue;
        }

        // A special stick emits digital inputs picked by the knob position, so it
        // feeds the same flag diff rather than the analog path below.
        if (control.bindingKind == CustomBindingKindSpecialStick) {
            desiredFlags |= [self directionButtonFlagsForItem:item];
            continue;
        }

        // Mouse, hide-others and show-keyboard send nothing on the controller channel.
        if (control.bindingKind == CustomBindingKindMouse ||
            control.bindingKind == CustomBindingKindHideOthers ||
            control.bindingKind == CustomBindingKindShowKeyboard) {
            continue;
        }

        if (item.touch == nil) {
            continue;
        }

        if (control.bindingKind == CustomBindingKindStick) {
            short x = (short)lround(item.stickVector.x * kStickFullScale);
            short y = (short)lround(item.stickVector.y * kStickFullScale);
            if (control.bindLeft) {
                leftX = x;
                leftY = y;
            } else {
                rightX = x;
                rightY = y;
            }
        } else if (control.bindingKind == CustomBindingKindTrigger) {
            // v1 treats a trigger control as fully pressed while it is asserted.
            if (control.bindLeft) {
                leftTrigger = 0xFF;
            } else {
                rightTrigger = 0xFF;
            }
        }
    }

    // Keyboard runs on its own channel and guards its own empty state, so commit
    // it before the neutral check below. Otherwise the very first keyboard-only
    // interaction would be swallowed by that construction guard, which only
    // knows about controller state.
    [self commitKeyboardState];
    // The mouse link has its own start/stop logic and does not depend on any of
    // the controller state below, so it runs before the neutral guard too.
    [self updateMouseMovementTimer];

    // Nothing has been sent yet and the desired state is completely neutral:
    // this is the construction path, where the stream connection does not exist
    // yet, so stay quiet rather than announcing an idle virtual gamepad.
    if (!_hasCommitted &&
        desiredFlags == 0 &&
        leftX == 0 && leftY == 0 && rightX == 0 && rightY == 0 &&
        leftTrigger == 0 && rightTrigger == 0) {
        return;
    }
    _hasCommitted = YES;

    // Diff rather than set/clear per control: two controls bound to the same
    // button then cooperate instead of clearing each other's bit, and a
    // cancelled touch releases everything for free.
    int toSet = desiredFlags & ~_appliedButtonFlags;
    int toClear = _appliedButtonFlags & ~desiredFlags;
    if (toSet != 0) {
        [_controllerSupport setButtonFlag:_oscController flags:toSet];
    }
    if (toClear != 0) {
        [_controllerSupport clearButtonFlag:_oscController flags:toClear];
    }
    _appliedButtonFlags = desiredFlags;

    // Analog values are plain assignments inside ControllerSupport. With the
    // presets suppressed this controller is the only writer, so writing the
    // full state every commit is correct.
    [_controllerSupport updateLeftStick:_oscController x:leftX y:leftY];
    [_controllerSupport updateRightStick:_oscController x:rightX y:rightY];
    [_controllerSupport updateLeftTrigger:_oscController left:leftTrigger];
    [_controllerSupport updateRightTrigger:_oscController right:rightTrigger];

    [_controllerSupport updateFinished:_oscController];
}

// ---------------------------------------------------------------------------
// Keyboard
// ---------------------------------------------------------------------------

// Directions of a special stick that are currently pushed, as a bitmask indexed
// by CustomStickDirection. Only meaningful while the stick is being held.
- (NSUInteger)activeDirectionsForItem:(CustomControlItem *)item {
    if (item.control.bindingKind != CustomBindingKindSpecialStick || item.touch == nil) {
        return 0;
    }

    // A special stick has no analog consumer - commitState sends it straight to
    // the direction flags - so its dead zone is the only distance that means
    // anything, and it is the one the user can edit. Testing the directions
    // against a second, hardcoded threshold made that slider do nothing below
    // it: the vector started moving at the dead zone, but the keys only fired at
    // 0.4, so nothing came out until the stick had been dragged a long way.
    //
    // The comparison is strict so that a dead zone of zero cannot fire both
    // positive directions from a vector of exactly (0, 0) at rest.
    CGFloat threshold = item.control.deadZone;

    // stickVector is already dead-zoned and normalised, with +y pointing up.
    CGPoint vector = item.stickVector;
    NSUInteger mask = 0;

    if (vector.y > threshold) {
        mask |= (NSUInteger)1 << CustomStickDirectionUp;
    }
    if (vector.y < -threshold) {
        mask |= (NSUInteger)1 << CustomStickDirectionDown;
    }
    if (vector.x < -threshold) {
        mask |= (NSUInteger)1 << CustomStickDirectionLeft;
    }
    if (vector.x > threshold) {
        mask |= (NSUInteger)1 << CustomStickDirectionRight;
    }

    return mask;
}

- (int)directionButtonFlagsForItem:(CustomControlItem *)item {
    NSUInteger mask = [self activeDirectionsForItem:item];
    if (mask == 0) {
        return 0;
    }

    int flags = 0;
    for (NSInteger d = 0; d <= (NSInteger)CustomStickDirectionRight; d++) {
        if (!(mask & ((NSUInteger)1 << d))) {
            continue;
        }

        CustomDigitalBinding *digital = [item.control bindingForDirection:(CustomStickDirection)d];
        if (digital.kind == CustomDigitalSourceButton) {
            flags |= (int)digital.buttonFlag;
        }
    }

    return flags;
}

// ---------------------------------------------------------------------------
// Mouse
// ---------------------------------------------------------------------------

- (BOOL)mouseControlIsActive:(CustomControlItem *)item {
    if (item.soloHidden) {
        return NO;
    }
    return [item isAsserted];
}

- (CGPoint)mouseVectorForItem:(CustomControlItem *)item {
    CustomControl *control = item.control;

    if ([control isStickShaped]) {
        // stickVector is gamepad oriented (+y up). The mouse API wants screen
        // coordinates, where +y points down.
        return CGPointMake(item.stickVector.x, -item.stickVector.y);
    }

    // Button-shaped: one fixed direction while held, because there is no drag to
    // take a direction from.
    switch (control.mouseDirection) {
        case CustomStickDirectionUp:    return CGPointMake(0.0, -1.0);
        case CustomStickDirectionDown:  return CGPointMake(0.0, 1.0);
        case CustomStickDirectionLeft:  return CGPointMake(-1.0, 0.0);
        case CustomStickDirectionRight: return CGPointMake(1.0, 0.0);
    }
    return CGPointZero;
}

// The link only exists while something is actually moving the cursor, so an idle
// overlay costs nothing. Continuous motion needs ticks: unlike a drag there is no
// touch event to piggyback on.
- (void)updateMouseMovementTimer {
    BOOL needed = NO;
    for (CustomControlItem *item in _items) {
        if (item.control.bindingKind == CustomBindingKindMouse && [self mouseControlIsActive:item]) {
            needed = YES;
            break;
        }
    }

    if (needed && _mouseLink == nil) {
        _mouseLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(mouseTick:)];
        [_mouseLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    } else if (!needed && _mouseLink != nil) {
        [_mouseLink invalidate];
        _mouseLink = nil;
    }
}

- (void)mouseTick:(CADisplayLink *)link {
    // The rate is per second, so the delta depends on how long the last frame
    // took. Guard the first frame and any long stall.
    double dt = link.targetTimestamp - link.timestamp;
    if (dt <= 0.0 || dt > 0.25) {
        dt = 1.0 / 60.0;
    }

    double deltaX = 0.0;
    double deltaY = 0.0;

    for (CustomControlItem *item in _items) {
        CustomControl *control = item.control;
        if (control.bindingKind != CustomBindingKindMouse || ![self mouseControlIsActive:item]) {
            continue;
        }

        CGPoint vector = [self mouseVectorForItem:item];
        deltaX += vector.x * control.mouseRate * dt;
        deltaY += vector.y * control.mouseRate * dt;
    }

    if (deltaX == 0.0 && deltaY == 0.0) {
        return;
    }

    short sendX = (short)MAX(-32767.0, MIN(32767.0, deltaX));
    short sendY = (short)MAX(-32767.0, MIN(32767.0, deltaY));
    if (sendX != 0 || sendY != 0) {
        LiSendMouseMoveEvent(sendX, sendY);
    }
}

// ---------------------------------------------------------------------------
// Hide others
// ---------------------------------------------------------------------------

// While a hide-others control is toggled on, everything except that control is
// hidden and stops holding input, so an obstructed part of the screen becomes
// usable without deleting anything.
- (void)applySoloVisibility {
    CustomControlItem *revealed = nil;
    for (CustomControlItem *item in _items) {
        if (item.control.bindingKind == CustomBindingKindHideOthers && item.latched) {
            revealed = item;
            break;
        }
    }

    for (CustomControlItem *item in _items) {
        if (revealed == nil) {
            item.soloHidden = NO;
            item.soloInvisible = NO;
            continue;
        }

        // Everything disappears, including the control that was tapped: the
        // point of the feature is a completely unobstructed screen.
        item.soloInvisible = YES;

        if (item == revealed) {
            // ...but it keeps its hit area, so a tap in the same place brings
            // the controls back. Making it untouchable too would strand the
            // layout for the rest of the stream.
            item.soloHidden = NO;
            continue;
        }

        // A control nobody can see must not keep input asserted, must not
        // swallow touches, and must not keep showing a latched look that no
        // longer matches its state.
        item.soloHidden = YES;
        item.touch = nil;
        item.latched = NO;
        item.stickVector = CGPointZero;
        item.stickDisplay = CGPointZero;
        [self reflectLatchedStateForItem:item];
    }

    [self layoutControlLayers];
}

- (void)commitKeyboardState {
    // The desired set is computed across all controls, so two controls bound to
    // the same key cooperate rather than clearing each other, exactly like the
    // digital button flags.
    NSMutableSet<NSNumber *> *desiredCodes = [[NSMutableSet alloc] init];
    char desiredModifiers = 0;

    for (CustomControlItem *item in _items) {
        CustomControl *control = item.control;

        // A special stick contributes whichever of its directions are pushed and
        // happen to be bound to a key.
        if (control.bindingKind == CustomBindingKindSpecialStick) {
            NSUInteger mask = [self activeDirectionsForItem:item];
            for (NSInteger d = 0; d <= (NSInteger)CustomStickDirectionRight; d++) {
                if (!(mask & ((NSUInteger)1 << d))) {
                    continue;
                }
                CustomDigitalBinding *digital = [control bindingForDirection:(CustomStickDirection)d];
                if (digital.kind != CustomDigitalSourceKey || digital.keyCode == 0) {
                    continue;
                }
                [desiredCodes addObject:@(digital.keyCode)];
                desiredModifiers |= [CustomLayoutDocument modifierBitForCode:digital.keyCode];
            }
            continue;
        }

        if (control.bindingKind != CustomBindingKindKey || control.keyCode == 0) {
            continue;
        }
        if (![item isAsserted]) {
            continue;
        }

        [desiredCodes addObject:@(control.keyCode)];
        desiredModifiers |= [CustomLayoutDocument modifierBitForCode:control.keyCode];
    }

    if (desiredCodes.count == 0 && _appliedKeyCodes.count == 0) {
        return;
    }

    // Releases first, carrying the modifier state that was in effect while the
    // key was held. A modifier's own release event therefore still advertises
    // its bit, which is what the existing physical-keyboard path does too.
    for (NSNumber *code in _appliedKeyCodes) {
        if (![desiredCodes containsObject:code]) {
            [self releaseKeyCode:(uint16_t)code.unsignedShortValue modifiers:_appliedKeyModifiers];
        }
    }

    // Then presses, carrying the modifier state that will be in effect, so a
    // latched Ctrl is already part of the event for the C that follows it.
    for (NSNumber *code in desiredCodes) {
        if (![_appliedKeyCodes containsObject:code]) {
            [self pressKeyCode:(uint16_t)code.unsignedShortValue modifiers:desiredModifiers];
        }
    }

    _appliedKeyCodes = desiredCodes;
    _appliedKeyModifiers = desiredModifiers;
}

- (void)pressKeyCode:(uint16_t)keyCode modifiers:(char)modifiers {
    // Modifiers are sent as their own key event, then the key itself advertises
    // the modifier bits. This matches StreamView's physical keyboard path.
    char modifierBit = [CustomLayoutDocument modifierBitForCode:keyCode];
    if (modifierBit != 0) {
        LiSendKeyboardEvent((short)keyCode, KEY_ACTION_DOWN, modifiers);
        return;
    }

    // NON_NORMALIZED tells the host these are Win32 VK codes rather than US
    // English scancodes.
    LiSendKeyboardEvent2((short)keyCode, KEY_ACTION_DOWN, modifiers, SS_KBE_FLAG_NON_NORMALIZED);
}

- (void)releaseKeyCode:(uint16_t)keyCode modifiers:(char)modifiers {
    char modifierBit = [CustomLayoutDocument modifierBitForCode:keyCode];
    if (modifierBit != 0) {
        LiSendKeyboardEvent((short)keyCode, KEY_ACTION_UP, modifiers);
        return;
    }

    LiSendKeyboardEvent2((short)keyCode, KEY_ACTION_UP, modifiers, SS_KBE_FLAG_NON_NORMALIZED);
}

@end
