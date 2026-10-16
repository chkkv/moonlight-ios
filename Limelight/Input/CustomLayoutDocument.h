//
//  CustomLayoutDocument.h
//  Moonlight
//
//  Model and codec for the user-defined on-screen control overlay.
//
//  This is deliberately independent from OnScreenControls: the presets keep
//  their hardcoded layouts and this overlay is a separate, user-authored layer
//  that is mounted on top of the stream view.
//
//  Coordinate system (v1):
//
//    anchor   One of five screen reference points (four corners + centre). The
//             anchor is placed on the *safe area* rect, so controls placed at
//             an anchor never end up under the notch or the home indicator.
//    offset   Signed decimals from the anchor, always along the screen axes
//             (+x right, +y down). x is a fraction of the full view width and
//             y is a fraction of the full view height, so offsets are
//             resolution independent. Typical values are in [-0.5, 0.5];
//             anything outside is clamped back to the safe area edge.
//    size.pt  Size in points. Points are already a density independent unit, so
//             no DPI table is involved: a 56 pt button is 56 pt everywhere.
//    aspect   Width / height ratio. 1.0 is a square.
//
//  The rendered geometry lives here rather than in the view so that the editor
//  preview and the live overlay cannot drift apart.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Current schema version, bumped whenever the stored format changes.
//
// v1 -> v2 added keyboard keys (binding kind "key") and the per-control "sticky"
// flag. v2 -> v3 added the special stick (binding kind "specialStick"), whose
// four directions each carry an arbitrary digital input. v3 -> v4 added the mouse
// binding (with its rate and fixed direction) and the hide-others binding. v4 -> v5
// added the show-keyboard binding. All the additions are additive and every field
// has a default, so older documents still load; the reader accepts any version from
// CUSTOM_LAYOUT_MIN_VERSION up to this one and writers always emit the newest.
#define CUSTOM_LAYOUT_VERSION 5
#define CUSTOM_LAYOUT_MIN_VERSION 1

// "MLOSC1:" + base64(UTF-8 JSON). The prefix lets us reject foreign data early.
#define CUSTOM_LAYOUT_TOKEN_PREFIX @"MLOSC1:"

// A layout may not contain more controls than this. Bounds the worst case for
// hit testing, which is linear in the control count.
#define CUSTOM_LAYOUT_MAX_CONTROLS 32

typedef NS_ENUM(NSInteger, CustomControlType) {
    CustomControlTypeButton,
    CustomControlTypeStick,
};

typedef NS_ENUM(NSInteger, CustomAnchor) {
    CustomAnchorTopLeft,
    CustomAnchorTopRight,
    CustomAnchorBottomLeft,
    CustomAnchorBottomRight,
    CustomAnchorCenter,
};

// What the control sends to the host.
typedef NS_ENUM(NSInteger, CustomBindingKind) {
    CustomBindingKindButton,       // digital, a Limelight *_FLAG bit
    CustomBindingKindStick,        // analog left/right stick
    CustomBindingKindTrigger,      // analog left/right trigger
    CustomBindingKindKey,          // keyboard, a Win32 VK_* code
    CustomBindingKindSpecialStick, // stick-shaped, but its four directions each
                                   // emit an arbitrary digital input
    CustomBindingKindMouse,        // moves the cursor: continuously from the drag
                                   // when stick-shaped, or in one fixed direction
                                   // while held when button-shaped
    CustomBindingKindHideOthers,   // sends nothing; while toggled on it hides every
                                   // other control so an obstructed area is usable
    CustomBindingKindShowKeyboard, // sends nothing; asking for the software keyboard
                                   // is its whole effect
};

// One digital input, which can be a gamepad button or a keyboard key. The
// special stick maps each of its directions to one of these. The namespaces are
// separate because "A" is both a gamepad button and a keyboard letter.
typedef NS_ENUM(NSInteger, CustomDigitalSourceKind) {
    CustomDigitalSourceNone,   // deliberately unassigned
    CustomDigitalSourceButton, // gamepad, same namespace as buttonFlag
    CustomDigitalSourceKey,    // keyboard, same namespace as keyCode
};

@interface CustomDigitalBinding : NSObject

@property (nonatomic) CustomDigitalSourceKind kind;
@property (nonatomic) uint32_t buttonFlag;
@property (nonatomic) uint16_t keyCode;

+ (instancetype)unassigned;
+ (instancetype)bindingWithButtonFlag:(uint32_t)flag;
+ (instancetype)bindingWithKeyCode:(uint16_t)keyCode;

- (BOOL)isAssigned;

// Human readable, for the editor menus and for a control's derived title.
- (NSString *)displayName;

@end

// Order matters: the editor's direction menu and the JSON both use it.
typedef NS_ENUM(NSInteger, CustomStickDirection) {
    CustomStickDirectionUp,
    CustomStickDirectionDown,
    CustomStickDirectionLeft,
    CustomStickDirectionRight,
};

@interface CustomControl : NSObject

@property (nonatomic, copy) NSString *controlId;
@property (nonatomic) CustomControlType type;
@property (nonatomic) CustomAnchor anchor;

// Signed fractions of the full view width/height, measured from the anchor.
@property (nonatomic) double offsetX;
@property (nonatomic) double offsetY;

// Size in points, plus the width/height ratio (1.0 == square).
@property (nonatomic) double sizePt;
@property (nonatomic) double aspect;

@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *icon;

@property (nonatomic) CustomBindingKind bindingKind;

// bindingKind == CustomBindingKindButton
@property (nonatomic) uint32_t buttonFlag;

// bindingKind == CustomBindingKindStick / CustomBindingKindTrigger
@property (nonatomic) BOOL bindLeft;

// bindingKind == CustomBindingKindKey. A Win32 VK_* code, matching what
// KeyboardSupport already sends for a physical keyboard.
@property (nonatomic) uint16_t keyCode;

// Sticky (latching) behaviour: a tap toggles the control on or off instead of
// it being held while the finger is down. This is what makes a modifier usable
// on a touch screen, because it would otherwise be impossible to hold Ctrl and
// press C with one hand. Ignored for sticks, whose value is their position.
@property (nonatomic) BOOL sticky;

// bindingKind == CustomBindingKindSpecialStick. Each direction emits the bound
// digital input while the knob is pushed that way; several can be active at once
// for diagonals. Never nil: an unused direction holds an unassigned binding.
@property (nonatomic, strong) CustomDigitalBinding *upBinding;
@property (nonatomic, strong) CustomDigitalBinding *downBinding;
@property (nonatomic, strong) CustomDigitalBinding *leftBinding;
@property (nonatomic, strong) CustomDigitalBinding *rightBinding;

- (CustomDigitalBinding *)bindingForDirection:(CustomStickDirection)direction;
- (void)setBinding:(CustomDigitalBinding *)binding forDirection:(CustomStickDirection)direction;

// bindingKind == CustomBindingKindMouse.
//
// mouseRate is the cursor speed in points per second: at full deflection when
// stick-shaped, or while held when button-shaped.
//
// mouseDirection is only used by a button-shaped control, which has no drag to
// take a direction from. A stick-shaped one moves along the drag instead.
@property (nonatomic) double mouseRate;
@property (nonatomic) CustomStickDirection mouseDirection;

// YES when the control is drawn and manipulated like a stick, which covers both
// the analog stick and the special one.
- (BOOL)isStickShaped;

// Stick only. Reserved for a future release (stick click as a tap gesture):
// parsed and stored so the format does not have to change, but ignored by the
// v1 renderer. To get L3/R3 today, add a separate button control bound to
// "L3" / "R3".
@property (nonatomic) BOOL clickable;

// Stick only, as a fraction of the stick radius.
//
// On an analog stick and on a mouse nub this is the radial dead zone: deflection
// below it is reported as no deflection at all. A special stick has no analog
// output, so there it is the distance a direction must pass before its input
// asserts, which makes it the single sensitivity control for a WASD-style nub.
@property (nonatomic) double deadZone;

// Size in points after applying `aspect`.
- (CGSize)renderedSize;

// The anchor point itself, in points, for a view of `bounds` with the given
// safe area insets. Exposed so the editor can turn a dragged position back into
// offsets without duplicating the anchor maths.
- (CGPoint)anchorOriginInBounds:(CGSize)bounds safeInsets:(UIEdgeInsets)safeInsets;

// Centre of the control inside a view of `bounds` with the given safe area
// insets, already clamped so the control stays fully inside the safe area.
// Controls larger than the safe area are centred on it instead of being
// clamped, which would otherwise invert the clamp interval.
- (CGPoint)renderedCenterInBounds:(CGSize)bounds safeInsets:(UIEdgeInsets)safeInsets;

// YES if this control claims the same input as `other`. Two controls claiming
// the same digital flag is tolerated (the overlay reference-counts by diffing
// the desired state), but two controls claiming the same analog axis is not.
- (BOOL)bindsSameInputAs:(CustomControl *)other;

@end

@interface CustomLayoutDocument : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSArray<CustomControl *> *controls;

// A layout with no controls. Used as the starting point when the user adds a
// new layout in the editor.
+ (instancetype)emptyLayoutWithName:(NSString *)name;

// A small, usable starter layout (left stick + A/B) so a freshly created
// layout is not a dead overlay that renders nothing.
+ (instancetype)starterLayoutWithName:(NSString *)name;

- (BOOL)isEmpty;

// Serialisation. `shareToken` is "MLOSC1:" + base64 of the UTF-8 JSON, which is
// the format stored in CoreData and the format users copy between devices.
- (NSString *)shareToken;
+ (instancetype)layoutFromShareToken:(NSString *)token error:(NSError **)error;

// Raw JSON, for debugging and for the editor's import/export preview.
- (NSData *)jsonData;

// Structural validation. Rejects a layout the renderer cannot honour, and
// rejects duplicate analog bindings (see -bindsSameInputAs:). Duplicate
// digital bindings are allowed on purpose.
- (BOOL)validate:(NSError **)error;

// Digital button name <-> Limelight flag. Names are the JSON spelling.
+ (NSArray<NSString *> *)buttonNames;
+ (uint32_t)flagForButtonName:(NSString *)name;
+ (NSString *)buttonNameForFlag:(uint32_t)flag;

// Keyboard key name <-> Win32 VK_* code, for the JSON and the editor menus.
// The categories exist so the editor can offer the keys in manageable groups
// instead of one long list.
+ (NSArray<NSString *> *)keyCategories;
+ (NSArray<NSString *> *)keyNamesInCategory:(NSString *)category;
+ (uint16_t)keyCodeForName:(NSString *)name;
+ (NSString *)keyNameForCode:(uint16_t)code;

// Special stick direction names, in CustomStickDirection order, used by both the
// JSON and the editor's direction menus.
+ (NSArray<NSString *> *)directionNames;
+ (NSString *)nameForDirection:(CustomStickDirection)direction;
+ (BOOL)directionForName:(NSString *)name out:(CustomStickDirection *)outDirection;

// Non-zero when the code is a modifier, in which case it is the Limelight
// MODIFIER_* bit that has to travel with every other key event.
+ (char)modifierBitForCode:(uint16_t)code;
+ (BOOL)isModifierKeyCode:(uint16_t)code;

// Anchor name <-> enum, for the JSON and the editor menu.
+ (NSArray<NSString *> *)anchorNames;
+ (NSString *)nameForAnchor:(CustomAnchor)anchor;
+ (BOOL)anchorForName:(NSString *)name out:(CustomAnchor *)outAnchor;

@end
