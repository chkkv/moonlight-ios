//
//  CustomLayoutDocument.m
//  Moonlight
//

#import "CustomLayoutDocument.h"
#include "Limelight.h"
#include <math.h>

// Forward declarations for the members used before their definitions below.
@interface CustomControl ()
- (NSDictionary *)dictionaryRepresentation;
@end

@interface CustomLayoutDocument ()
- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)layoutFromJSONData:(NSData *)data error:(NSError **)error;
+ (CustomControl *)controlFromDictionary:(NSDictionary *)dict error:(NSError **)error;
+ (CustomDigitalBinding *)digitalBindingFromDictionary:(NSDictionary *)dict error:(NSError **)error;
@end

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

typedef struct {
    const char *name;
    uint32_t flag;
} CustomButtonFlagEntry;

// The bindable digital inputs. Triggers and sticks are analog and are handled
// separately by CustomBindingKind.
static const CustomButtonFlagEntry kButtonFlags[] = {
    { "A",       A_FLAG },
    { "B",       B_FLAG },
    { "X",       X_FLAG },
    { "Y",       Y_FLAG },
    { "Up",      UP_FLAG },
    { "Down",    DOWN_FLAG },
    { "Left",    LEFT_FLAG },
    { "Right",   RIGHT_FLAG },
    { "LB",      LB_FLAG },
    { "RB",      RB_FLAG },
    { "Start",   PLAY_FLAG },
    { "Back",    BACK_FLAG },
    { "L3",      LS_CLK_FLAG },
    { "R3",      RS_CLK_FLAG },
    { "Special", SPECIAL_FLAG },
};
static const size_t kButtonFlagCount = sizeof(kButtonFlags) / sizeof(*kButtonFlags);

// ---------------------------------------------------------------------------
// Keyboard keys
// ---------------------------------------------------------------------------

// Win32 VK_* codes, matching what KeyboardSupport already sends for a physical
// keyboard. Letters, digits and function keys are derived arithmetically in
// -keyNameForCode: / -keyCodeForName: rather than listed here.
typedef struct {
    const char *category;
    const char *name;
    uint16_t code;
    char modifierBit;
} CustomKeyEntry;

static const CustomKeyEntry kKeyTable[] = {
    // The modifier codes and bits are exactly the ones KeyboardSupport uses.
    { "Modifiers",   "Ctrl",      0x11, MODIFIER_CTRL  },
    { "Modifiers",   "Shift",     0x10, MODIFIER_SHIFT },
    { "Modifiers",   "Alt",       0x12, MODIFIER_ALT   },
    { "Modifiers",   "Meta",      0x5B, MODIFIER_META  },

    { "Common",      "Space",     0x20, 0 },
    { "Common",      "Enter",     0x0D, 0 },
    { "Common",      "Tab",       0x09, 0 },
    { "Common",      "Escape",    0x1B, 0 },
    { "Common",      "Backspace", 0x08, 0 },
    { "Common",      "Left",      0x25, 0 },
    { "Common",      "Up",        0x26, 0 },
    { "Common",      "Right",     0x27, 0 },
    { "Common",      "Down",      0x28, 0 },

    { "Punctuation", "-",         0xBD, 0 },
    { "Punctuation", "=",         0xBB, 0 },
    { "Punctuation", "[",         0xDB, 0 },
    { "Punctuation", "]",         0xDD, 0 },
    { "Punctuation", "\\",        0xDC, 0 },
    { "Punctuation", ";",         0xBA, 0 },
    { "Punctuation", "'",         0xDE, 0 },
    { "Punctuation", ",",         0xBC, 0 },
    { "Punctuation", ".",         0xBE, 0 },
    { "Punctuation", "/",         0xBF, 0 },
};
static const size_t kKeyTableCount = sizeof(kKeyTable) / sizeof(*kKeyTable);

static const char *kKeyCategoryNames[] = {
    "Modifiers", "Letters", "Digits", "Common", "Function Keys", "Punctuation",
};
static const size_t kKeyCategoryCount = sizeof(kKeyCategoryNames) / sizeof(*kKeyCategoryNames);

static const char *kKeyCategoryLetters = "Letters";
static const char *kKeyCategoryDigits = "Digits";
static const char *kKeyCategoryFunction = "Function Keys";

// Index order must match CustomAnchor.
static const char *kAnchorNames[] = {
    "topLeft", "topRight", "bottomLeft", "bottomRight", "center",
};
static const size_t kAnchorCount = sizeof(kAnchorNames) / sizeof(*kAnchorNames);

// Range guards. Out of range values are clamped on decode and rejected by
// -validate:, so user edits cannot produce a control the renderer cannot honour.
static const double kOffsetLimit = 2.0;
static const double kMinSizePt = 16.0;
static const double kMaxSizePt = 400.0;
static const double kMinAspect = 0.2;
static const double kMaxAspect = 5.0;
static const NSUInteger kMaxNameLength = 40;

// Stick dead zone, as a fraction of the stick radius. The editor's slider offers
// exactly this range in 0.01 steps.
static const double kMinDeadZone = 0.0;
static const double kMaxDeadZone = 0.5;
static const double kDefaultDeadZone = 0.1;

// Cursor speed for a mouse control, in points per second at full deflection.
// The range deliberately matches what the editor's rate slider offers.
static const double kMinMouseRate = 60.0;
static const double kMaxMouseRate = 2000.0;
static const double kDefaultMouseRate = 600.0;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

static NSError *CustomLayoutError(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    return [NSError errorWithDomain:@"CustomLayoutDocument"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static double ClampDouble(double value, double lo, double hi) {
    if (value < lo) {
        return lo;
    }
    if (value > hi) {
        return hi;
    }
    return value;
}

static double DoubleFromJSON(id value, double fallback) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value doubleValue];
    }
    return fallback;
}

static BOOL BoolFromJSON(id value, BOOL fallback) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value boolValue];
    }
    return fallback;
}

static NSString *StringFromJSON(id value) {
    return [value isKindOfClass:[NSString class]] ? (NSString *)value : nil;
}

static NSDictionary *DictionaryFromJSON(id value) {
    return [value isKindOfClass:[NSDictionary class]] ? (NSDictionary *)value : nil;
}

// ---------------------------------------------------------------------------
// CustomDigitalBinding
// ---------------------------------------------------------------------------

@implementation CustomDigitalBinding

+ (instancetype)unassigned {
    CustomDigitalBinding *binding = [[CustomDigitalBinding alloc] init];
    binding.kind = CustomDigitalSourceNone;
    return binding;
}

+ (instancetype)bindingWithButtonFlag:(uint32_t)flag {
    CustomDigitalBinding *binding = [[CustomDigitalBinding alloc] init];
    binding.kind = CustomDigitalSourceButton;
    binding.buttonFlag = flag;
    return binding;
}

+ (instancetype)bindingWithKeyCode:(uint16_t)keyCode {
    CustomDigitalBinding *binding = [[CustomDigitalBinding alloc] init];
    binding.kind = CustomDigitalSourceKey;
    binding.keyCode = keyCode;
    return binding;
}

- (BOOL)isAssigned {
    switch (self.kind) {
        case CustomDigitalSourceButton:
            return self.buttonFlag != 0;
        case CustomDigitalSourceKey:
            return self.keyCode != 0;
        case CustomDigitalSourceNone:
            return NO;
    }
    return NO;
}

- (NSString *)displayName {
    switch (self.kind) {
        case CustomDigitalSourceButton: {
            NSString *name = [CustomLayoutDocument buttonNameForFlag:self.buttonFlag];
            return name.length ? name : @"?";
        }
        case CustomDigitalSourceKey: {
            NSString *name = [CustomLayoutDocument keyNameForCode:self.keyCode];
            return name.length ? name : @"?";
        }
        case CustomDigitalSourceNone:
            return @"Not set";
    }
    return @"Not set";
}

@end

// ---------------------------------------------------------------------------
// CustomControl
// ---------------------------------------------------------------------------

@implementation CustomControl

- (instancetype)init {
    self = [super init];
    if (self) {
        _controlId = @"";
        _type = CustomControlTypeButton;
        _anchor = CustomAnchorTopLeft;
        _sizePt = 56.0;
        _aspect = 1.0;
        _bindingKind = CustomBindingKindButton;
        _buttonFlag = 0;
        _bindLeft = YES;
        _clickable = NO;
        _deadZone = kDefaultDeadZone;
        // Never nil, so the codec and the renderer can treat an unused direction
        // as "unassigned" instead of having to nil-check everywhere.
        _upBinding = [CustomDigitalBinding unassigned];
        _downBinding = [CustomDigitalBinding unassigned];
        _leftBinding = [CustomDigitalBinding unassigned];
        _rightBinding = [CustomDigitalBinding unassigned];
        // 600 pt/s is roughly a comfortable desktop cursor speed at full push.
        _mouseRate = 600.0;
        _mouseDirection = CustomStickDirectionUp;
    }
    return self;
}

- (BOOL)isStickShaped {
    return self.type == CustomControlTypeStick;
}

- (CustomDigitalBinding *)bindingForDirection:(CustomStickDirection)direction {
    switch (direction) {
        case CustomStickDirectionUp:    return self.upBinding;
        case CustomStickDirectionDown:  return self.downBinding;
        case CustomStickDirectionLeft:  return self.leftBinding;
        case CustomStickDirectionRight: return self.rightBinding;
    }
    return self.upBinding;
}

- (void)setBinding:(CustomDigitalBinding *)binding forDirection:(CustomStickDirection)direction {
    CustomDigitalBinding *value = binding ?: [CustomDigitalBinding unassigned];

    switch (direction) {
        case CustomStickDirectionUp:    self.upBinding = value; break;
        case CustomStickDirectionDown:  self.downBinding = value; break;
        case CustomStickDirectionLeft:  self.leftBinding = value; break;
        case CustomStickDirectionRight: self.rightBinding = value; break;
    }
}

- (CGSize)renderedSize {
    double aspect = (self.aspect > 0.0) ? self.aspect : 1.0;
    double width = MAX(self.sizePt, 1.0);
    return CGSizeMake(width, width / aspect);
}

- (CGPoint)anchorOriginInBounds:(CGSize)bounds safeInsets:(UIEdgeInsets)safeInsets {
    // The anchor sits on the safe area, so a control placed at an anchor never
    // lands under the notch or the home indicator.
    CGRect safe = CGRectMake(safeInsets.left,
                             safeInsets.top,
                             MAX(bounds.width - safeInsets.left - safeInsets.right, 0.0),
                             MAX(bounds.height - safeInsets.top - safeInsets.bottom, 0.0));

    switch (self.anchor) {
        case CustomAnchorTopRight:
            return CGPointMake(CGRectGetMaxX(safe), CGRectGetMinY(safe));
        case CustomAnchorBottomLeft:
            return CGPointMake(CGRectGetMinX(safe), CGRectGetMaxY(safe));
        case CustomAnchorBottomRight:
            return CGPointMake(CGRectGetMaxX(safe), CGRectGetMaxY(safe));
        case CustomAnchorCenter:
            return CGPointMake(CGRectGetMidX(safe), CGRectGetMidY(safe));
        case CustomAnchorTopLeft:
        default:
            return CGPointMake(CGRectGetMinX(safe), CGRectGetMinY(safe));
    }
}

- (CGPoint)renderedCenterInBounds:(CGSize)bounds safeInsets:(UIEdgeInsets)safeInsets {
    CGRect safe = CGRectMake(safeInsets.left,
                             safeInsets.top,
                             MAX(bounds.width - safeInsets.left - safeInsets.right, 0.0),
                             MAX(bounds.height - safeInsets.top - safeInsets.bottom, 0.0));

    CGPoint origin = [self anchorOriginInBounds:bounds safeInsets:safeInsets];

    CGSize size = [self renderedSize];

    // Offsets are always along the screen axes, so a bottom-right anchored
    // control uses negative values to move inwards.
    CGFloat cx = origin.x + (CGFloat)(self.offsetX * bounds.width);
    CGFloat cy = origin.y + (CGFloat)(self.offsetY * bounds.height);

    // Overflow is pulled back to the safe area edge. A control larger than the
    // safe area is centred instead, otherwise the clamp interval would invert
    // and push it off screen.
    if (size.width >= safe.size.width) {
        cx = CGRectGetMidX(safe);
    } else {
        cx = MIN(MAX(cx, CGRectGetMinX(safe) + size.width / 2), CGRectGetMaxX(safe) - size.width / 2);
    }
    if (size.height >= safe.size.height) {
        cy = CGRectGetMidY(safe);
    } else {
        cy = MIN(MAX(cy, CGRectGetMinY(safe) + size.height / 2), CGRectGetMaxY(safe) - size.height / 2);
    }

    return CGPointMake(cx, cy);
}

- (BOOL)bindsSameInputAs:(CustomControl *)other {
    if (other == nil || self.bindingKind != other.bindingKind) {
        return NO;
    }

    switch (self.bindingKind) {
        case CustomBindingKindButton:
            return self.buttonFlag != 0 && self.buttonFlag == other.buttonFlag;
        case CustomBindingKindStick:
        case CustomBindingKindTrigger:
            // Analog axes are written by direct assignment, so two controls on
            // the same axis would overwrite each other every event.
            return self.bindLeft == other.bindLeft;
        case CustomBindingKindKey:
            // Digital, like a button: the renderer diffs the aggregate desired
            // set, so two controls on the same key cooperate.
            return NO;
        case CustomBindingKindSpecialStick:
            // Its four directions emit digital inputs, which are diffed the same
            // way, so overlaps between two special sticks are tolerated too.
            return NO;
        case CustomBindingKindMouse:
            // Two mouse controls simply sum their deltas, which is harmless.
            return NO;
        case CustomBindingKindHideOthers:
        case CustomBindingKindShowKeyboard:
            // Send nothing at all.
            return NO;
    }
    return NO;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    dict[@"id"] = self.controlId.length ? self.controlId : @"";
    dict[@"type"] = (self.type == CustomControlTypeStick) ? @"stick" : @"button";
    dict[@"anchor"] = [CustomLayoutDocument nameForAnchor:self.anchor];
    dict[@"offset"] = @{ @"x": @(self.offsetX), @"y": @(self.offsetY) };
    dict[@"size"] = @{ @"pt": @(self.sizePt), @"aspect": @(self.aspect) };

    NSMutableDictionary *binding = [NSMutableDictionary dictionary];
    switch (self.bindingKind) {
        case CustomBindingKindButton:
            binding[@"kind"] = @"button";
            binding[@"button"] = [CustomLayoutDocument buttonNameForFlag:self.buttonFlag] ?: @"";
            break;
        case CustomBindingKindStick:
            binding[@"kind"] = @"stick";
            binding[@"stick"] = self.bindLeft ? @"left" : @"right";
            break;
        case CustomBindingKindTrigger:
            binding[@"kind"] = @"trigger";
            binding[@"trigger"] = self.bindLeft ? @"left" : @"right";
            break;
        case CustomBindingKindKey:
            binding[@"kind"] = @"key";
            binding[@"key"] = [CustomLayoutDocument keyNameForCode:self.keyCode] ?: @"";
            break;
        case CustomBindingKindSpecialStick: {
            binding[@"kind"] = @"specialStick";
            // Unassigned directions are omitted entirely, so "absent" and
            // "unassigned" are the same thing and the document stays small.
            NSMutableDictionary *directions = [NSMutableDictionary dictionary];
            for (NSInteger i = 0; i <= (NSInteger)CustomStickDirectionRight; i++) {
                CustomStickDirection direction = (CustomStickDirection)i;
                CustomDigitalBinding *digital = [self bindingForDirection:direction];

                NSMutableDictionary *entry = [NSMutableDictionary dictionary];
                if (digital.kind == CustomDigitalSourceButton) {
                    entry[@"source"] = @"button";
                    entry[@"button"] = [CustomLayoutDocument buttonNameForFlag:digital.buttonFlag] ?: @"";
                } else if (digital.kind == CustomDigitalSourceKey) {
                    entry[@"source"] = @"key";
                    entry[@"key"] = [CustomLayoutDocument keyNameForCode:digital.keyCode] ?: @"";
                }

                if (entry.count > 0) {
                    directions[[CustomLayoutDocument nameForDirection:direction]] = entry;
                }
            }
            binding[@"directions"] = directions;
            break;
        }
        case CustomBindingKindMouse:
            binding[@"kind"] = @"mouse";
            // Only a button-shaped control needs a stored direction; a
            // stick-shaped one takes it from the drag.
            if (![self isStickShaped]) {
                binding[@"direction"] = [CustomLayoutDocument nameForDirection:self.mouseDirection];
            }
            break;
        case CustomBindingKindHideOthers:
            binding[@"kind"] = @"hideOthers";
            break;
        case CustomBindingKindShowKeyboard:
            binding[@"kind"] = @"showKeyboard";
            break;
    }
    dict[@"binding"] = binding;

    if (self.label.length) {
        dict[@"label"] = self.label;
    }
    if (self.icon.length) {
        dict[@"icon"] = self.icon;
    }

    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    if (self.type == CustomControlTypeStick) {
        options[@"clickable"] = @(self.clickable);
        options[@"deadZone"] = @(self.deadZone);
    }
    if (self.sticky) {
        options[@"sticky"] = @(YES);
    }
    if (self.bindingKind == CustomBindingKindMouse) {
        options[@"rate"] = @(self.mouseRate);
    }
    if (options.count > 0) {
        dict[@"options"] = options;
    }

    return dict;
}

@end

// ---------------------------------------------------------------------------
// CustomLayoutDocument
// ---------------------------------------------------------------------------

@implementation CustomLayoutDocument

- (instancetype)init {
    self = [super init];
    if (self) {
        _name = @"";
        _controls = @[];
    }
    return self;
}

- (BOOL)isEmpty {
    return self.controls.count == 0;
}

+ (instancetype)emptyLayoutWithName:(NSString *)name {
    CustomLayoutDocument *layout = [[CustomLayoutDocument alloc] init];
    layout.name = name.length ? name : @"Untitled";
    layout.controls = @[];
    return layout;
}

+ (instancetype)starterLayoutWithName:(NSString *)name {
    CustomLayoutDocument *layout = [self emptyLayoutWithName:name];

    CustomControl *stick = [[CustomControl alloc] init];
    stick.controlId = @"stick-left";
    stick.type = CustomControlTypeStick;
    stick.anchor = CustomAnchorBottomLeft;
    stick.offsetX = 0.12;
    stick.offsetY = -0.14;
    stick.sizePt = 120.0;
    stick.aspect = 1.0;
    stick.bindingKind = CustomBindingKindStick;
    stick.bindLeft = YES;
    // Stick click is reserved for a later release; bind a separate L3 button.
    stick.clickable = NO;
    stick.icon = @"StickOuter";

    CustomControl *a = [[CustomControl alloc] init];
    a.controlId = @"button-a";
    a.type = CustomControlTypeButton;
    a.anchor = CustomAnchorBottomRight;
    a.offsetX = -0.06;
    a.offsetY = -0.08;
    a.sizePt = 56.0;
    a.aspect = 1.0;
    a.bindingKind = CustomBindingKindButton;
    a.buttonFlag = A_FLAG;
    a.label = @"A";
    a.icon = @"AButton";

    CustomControl *b = [[CustomControl alloc] init];
    b.controlId = @"button-b";
    b.type = CustomControlTypeButton;
    b.anchor = CustomAnchorBottomRight;
    b.offsetX = -0.16;
    b.offsetY = -0.15;
    b.sizePt = 56.0;
    b.aspect = 1.0;
    b.bindingKind = CustomBindingKindButton;
    b.buttonFlag = B_FLAG;
    b.label = @"B";
    b.icon = @"BButton";

    layout.controls = @[ stick, a, b ];
    return layout;
}

// ---------------------------------------------------------------------------
// Name tables
// ---------------------------------------------------------------------------

+ (NSArray<NSString *> *)buttonNames {
    NSMutableArray *names = [NSMutableArray arrayWithCapacity:kButtonFlagCount];
    for (size_t i = 0; i < kButtonFlagCount; i++) {
        [names addObject:[NSString stringWithUTF8String:kButtonFlags[i].name]];
    }
    return names;
}

+ (uint32_t)flagForButtonName:(NSString *)name {
    if (![name isKindOfClass:[NSString class]]) {
        return 0;
    }
    for (size_t i = 0; i < kButtonFlagCount; i++) {
        NSString *candidate = [NSString stringWithUTF8String:kButtonFlags[i].name];
        if ([candidate isEqualToString:name]) {
            return kButtonFlags[i].flag;
        }
    }
    return 0;
}

+ (NSString *)buttonNameForFlag:(uint32_t)flag {
    for (size_t i = 0; i < kButtonFlagCount; i++) {
        if (kButtonFlags[i].flag == flag) {
            return [NSString stringWithUTF8String:kButtonFlags[i].name];
        }
    }
    return nil;
}

+ (NSArray<NSString *> *)keyCategories {
    NSMutableArray *categories = [NSMutableArray arrayWithCapacity:kKeyCategoryCount];
    for (size_t i = 0; i < kKeyCategoryCount; i++) {
        [categories addObject:[NSString stringWithUTF8String:kKeyCategoryNames[i]]];
    }
    return categories;
}

+ (NSArray<NSString *> *)keyNamesInCategory:(NSString *)category {
    NSMutableArray *names = [NSMutableArray array];

    for (size_t i = 0; i < kKeyTableCount; i++) {
        if ([category isEqualToString:[NSString stringWithUTF8String:kKeyTable[i].category]]) {
            [names addObject:[NSString stringWithUTF8String:kKeyTable[i].name]];
        }
    }

    if ([category isEqualToString:[NSString stringWithUTF8String:kKeyCategoryLetters]]) {
        for (unichar c = 'A'; c <= 'Z'; c++) {
            [names addObject:[NSString stringWithFormat:@"%C", c]];
        }
    } else if ([category isEqualToString:[NSString stringWithUTF8String:kKeyCategoryDigits]]) {
        for (unichar c = '0'; c <= '9'; c++) {
            [names addObject:[NSString stringWithFormat:@"%C", c]];
        }
    } else if ([category isEqualToString:[NSString stringWithUTF8String:kKeyCategoryFunction]]) {
        for (int i = 1; i <= 12; i++) {
            [names addObject:[NSString stringWithFormat:@"F%d", i]];
        }
    }

    return names;
}

+ (uint16_t)keyCodeForName:(NSString *)name {
    if (![name isKindOfClass:[NSString class]] || name.length == 0) {
        return 0;
    }

    for (size_t i = 0; i < kKeyTableCount; i++) {
        if ([name isEqualToString:[NSString stringWithUTF8String:kKeyTable[i].name]]) {
            return kKeyTable[i].code;
        }
    }

    if (name.length == 1) {
        unichar c = [name characterAtIndex:0];
        if (c >= 'A' && c <= 'Z') {
            return (uint16_t)(0x41 + (c - 'A'));
        }
        if (c >= 'a' && c <= 'z') {
            return (uint16_t)(0x41 + (c - 'a'));
        }
        if (c >= '0' && c <= '9') {
            return (uint16_t)(0x30 + (c - '0'));
        }
    }

    // "F1".."F12"
    if (name.length >= 2 && ([name characterAtIndex:0] == 'F' || [name characterAtIndex:0] == 'f')) {
        NSInteger index = [[name substringFromIndex:1] integerValue];
        if (index >= 1 && index <= 12) {
            return (uint16_t)(0x70 + index - 1);
        }
    }

    return 0;
}

+ (NSString *)keyNameForCode:(uint16_t)code {
    for (size_t i = 0; i < kKeyTableCount; i++) {
        if (kKeyTable[i].code == code) {
            return [NSString stringWithUTF8String:kKeyTable[i].name];
        }
    }

    if (code >= 0x41 && code <= 0x5A) {
        return [NSString stringWithFormat:@"%C", (unichar)('A' + (code - 0x41))];
    }
    if (code >= 0x30 && code <= 0x39) {
        return [NSString stringWithFormat:@"%C", (unichar)('0' + (code - 0x30))];
    }
    if (code >= 0x70 && code <= 0x7B) {
        return [NSString stringWithFormat:@"F%d", (int)(code - 0x70 + 1)];
    }

    return nil;
}

+ (char)modifierBitForCode:(uint16_t)code {
    for (size_t i = 0; i < kKeyTableCount; i++) {
        if (kKeyTable[i].code == code) {
            return kKeyTable[i].modifierBit;
        }
    }
    return 0;
}

+ (BOOL)isModifierKeyCode:(uint16_t)code {
    return [self modifierBitForCode:code] != 0;
}

+ (NSArray<NSString *> *)directionNames {
    return @[ @"Up", @"Down", @"Left", @"Right" ];
}

+ (NSString *)nameForDirection:(CustomStickDirection)direction {
    NSArray<NSString *> *names = [self directionNames];
    if (direction < 0 || (NSUInteger)direction >= names.count) {
        return names.firstObject;
    }
    return names[(NSUInteger)direction];
}

+ (BOOL)directionForName:(NSString *)name out:(CustomStickDirection *)outDirection {
    if (![name isKindOfClass:[NSString class]]) {
        return NO;
    }

    NSArray<NSString *> *names = [self directionNames];
    for (NSUInteger i = 0; i < names.count; i++) {
        if ([names[i] isEqualToString:name]) {
            if (outDirection != NULL) {
                *outDirection = (CustomStickDirection)i;
            }
            return YES;
        }
    }
    return NO;
}

+ (NSArray<NSString *> *)anchorNames {
    NSMutableArray *names = [NSMutableArray arrayWithCapacity:kAnchorCount];
    for (size_t i = 0; i < kAnchorCount; i++) {
        [names addObject:[NSString stringWithUTF8String:kAnchorNames[i]]];
    }
    return names;
}

+ (NSString *)nameForAnchor:(CustomAnchor)anchor {
    if (anchor < 0 || (size_t)anchor >= kAnchorCount) {
        return [NSString stringWithUTF8String:kAnchorNames[0]];
    }
    return [NSString stringWithUTF8String:kAnchorNames[anchor]];
}

+ (BOOL)anchorForName:(NSString *)name out:(CustomAnchor *)outAnchor {
    if (![name isKindOfClass:[NSString class]]) {
        return NO;
    }
    for (size_t i = 0; i < kAnchorCount; i++) {
        if ([[NSString stringWithUTF8String:kAnchorNames[i]] isEqualToString:name]) {
            if (outAnchor != NULL) {
                *outAnchor = (CustomAnchor)i;
            }
            return YES;
        }
    }
    return NO;
}

// ---------------------------------------------------------------------------
// Serialisation
// ---------------------------------------------------------------------------

- (NSDictionary *)dictionaryRepresentation {
    NSMutableArray *controls = [NSMutableArray arrayWithCapacity:self.controls.count];
    for (CustomControl *control in self.controls) {
        [controls addObject:[control dictionaryRepresentation]];
    }

    return @{
        @"v": @(CUSTOM_LAYOUT_VERSION),
        @"name": self.name.length ? self.name : @"",
        @"controls": controls,
    };
}

- (NSData *)jsonData {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:[self dictionaryRepresentation]
                                                   options:0
                                                     error:&error];
    if (data == nil) {
        Log(LOG_E, @"CustomLayoutDocument: JSON serialisation failed: %@", error);
    }
    return data;
}

- (NSString *)shareToken {
    NSData *data = [self jsonData];
    if (data == nil) {
        return nil;
    }
    return [CUSTOM_LAYOUT_TOKEN_PREFIX stringByAppendingString:[data base64EncodedStringWithOptions:0]];
}

+ (instancetype)layoutFromShareToken:(NSString *)token error:(NSError **)error {
    if (![token isKindOfClass:[NSString class]]) {
        if (error) *error = CustomLayoutError(@"Layout token is not a string.");
        return nil;
    }

    NSString *trimmed = [token stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![trimmed hasPrefix:CUSTOM_LAYOUT_TOKEN_PREFIX]) {
        if (error) *error = CustomLayoutError(@"Layout token is missing the %@ prefix.", CUSTOM_LAYOUT_TOKEN_PREFIX);
        return nil;
    }

    NSString *encoded = [trimmed substringFromIndex:CUSTOM_LAYOUT_TOKEN_PREFIX.length];
    NSData *data = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
    if (data == nil) {
        if (error) *error = CustomLayoutError(@"Layout token is not valid base64.");
        return nil;
    }

    return [self layoutFromJSONData:data error:error];
}

// Decode is lenient about ranges (they are clamped) and strict about structure
// (unknown bindings, duplicate analog axes, bad versions are rejected) so a
// hand-edited or foreign token cannot produce an unrenderable overlay.
+ (instancetype)layoutFromJSONData:(NSData *)data error:(NSError **)error {
    NSError *jsonError = nil;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    NSDictionary *rootDict = DictionaryFromJSON(root);
    if (rootDict == nil) {
        if (error) *error = CustomLayoutError(@"Layout is not a JSON object: %@", jsonError.localizedDescription);
        return nil;
    }

    NSNumber *version = rootDict[@"v"];
    if (![version isKindOfClass:[NSNumber class]] ||
        [version integerValue] < CUSTOM_LAYOUT_MIN_VERSION ||
        [version integerValue] > CUSTOM_LAYOUT_VERSION) {
        if (error) *error = CustomLayoutError(@"Unsupported layout version %@ (expected %d to %d).",
                                              version, CUSTOM_LAYOUT_MIN_VERSION, CUSTOM_LAYOUT_VERSION);
        return nil;
    }

    CustomLayoutDocument *layout = [[CustomLayoutDocument alloc] init];
    NSString *name = StringFromJSON(rootDict[@"name"]);
    layout.name = (name.length ? name : @"Untitled");

    NSArray *rawControls = rootDict[@"controls"];
    if (rawControls != nil && ![rawControls isKindOfClass:[NSArray class]]) {
        if (error) *error = CustomLayoutError(@"'controls' must be an array.");
        return nil;
    }
    if (rawControls.count > CUSTOM_LAYOUT_MAX_CONTROLS) {
        if (error) *error = CustomLayoutError(@"Layout has %lu controls, the limit is %d.",
                                              (unsigned long)rawControls.count, CUSTOM_LAYOUT_MAX_CONTROLS);
        return nil;
    }

    NSMutableArray *controls = [NSMutableArray arrayWithCapacity:rawControls.count];
    for (id rawControl in rawControls) {
        NSDictionary *controlDict = DictionaryFromJSON(rawControl);
        if (controlDict == nil) {
            if (error) *error = CustomLayoutError(@"Each control must be a JSON object.");
            return nil;
        }

        CustomControl *control = [self controlFromDictionary:controlDict error:error];
        if (control == nil) {
            return nil;
        }
        [controls addObject:control];
    }
    layout.controls = controls;

    if (![layout validate:error]) {
        return nil;
    }
    return layout;
}

+ (CustomControl *)controlFromDictionary:(NSDictionary *)dict error:(NSError **)error {
    CustomControl *control = [[CustomControl alloc] init];

    NSString *identifier = StringFromJSON(dict[@"id"]);
    control.controlId = identifier.length ? identifier : [[NSUUID UUID] UUIDString];

    NSString *type = StringFromJSON(dict[@"type"]);
    if ([type isEqualToString:@"stick"]) {
        control.type = CustomControlTypeStick;
    } else if ([type isEqualToString:@"button"] || type == nil) {
        control.type = CustomControlTypeButton;
    } else {
        if (error) *error = CustomLayoutError(@"Unknown control type '%@'.", type);
        return nil;
    }

    // Anchors default to topLeft so a layout written by an older tool still loads.
    NSString *anchorName = StringFromJSON(dict[@"anchor"]);
    CustomAnchor anchor = CustomAnchorTopLeft;
    if (anchorName != nil && ![self anchorForName:anchorName out:&anchor]) {
        if (error) *error = CustomLayoutError(@"Unknown anchor '%@'.", anchorName);
        return nil;
    }
    control.anchor = anchor;

    NSDictionary *offset = DictionaryFromJSON(dict[@"offset"]);
    control.offsetX = ClampDouble(DoubleFromJSON(offset[@"x"], 0.0), -kOffsetLimit, kOffsetLimit);
    control.offsetY = ClampDouble(DoubleFromJSON(offset[@"y"], 0.0), -kOffsetLimit, kOffsetLimit);

    NSDictionary *size = DictionaryFromJSON(dict[@"size"]);
    control.sizePt = ClampDouble(DoubleFromJSON(size[@"pt"], 56.0), kMinSizePt, kMaxSizePt);
    control.aspect = ClampDouble(DoubleFromJSON(size[@"aspect"], 1.0), kMinAspect, kMaxAspect);

    control.label = StringFromJSON(dict[@"label"]);
    control.icon = StringFromJSON(dict[@"icon"]);

    NSDictionary *binding = DictionaryFromJSON(dict[@"binding"]);
    NSString *kind = StringFromJSON(binding[@"kind"]);
    if (kind == nil) {
        if (error) *error = CustomLayoutError(@"Control '%@' has no binding.", control.controlId);
        return nil;
    }

    if ([kind isEqualToString:@"button"]) {
        control.bindingKind = CustomBindingKindButton;
        NSString *buttonName = StringFromJSON(binding[@"button"]);
        uint32_t flag = [self flagForButtonName:buttonName];
        if (flag == 0) {
            if (error) *error = CustomLayoutError(@"Unknown button binding '%@'.", buttonName);
            return nil;
        }
        control.buttonFlag = flag;
    } else if ([kind isEqualToString:@"stick"] || [kind isEqualToString:@"trigger"]) {
        BOOL isStick = [kind isEqualToString:@"stick"];
        control.bindingKind = isStick ? CustomBindingKindStick : CustomBindingKindTrigger;

        NSString *side = StringFromJSON(binding[isStick ? @"stick" : @"trigger"]);
        if ([side isEqualToString:@"left"]) {
            control.bindLeft = YES;
        } else if ([side isEqualToString:@"right"]) {
            control.bindLeft = NO;
        } else {
            if (error) *error = CustomLayoutError(@"Unknown %@ side '%@'.", kind, side);
            return nil;
        }
    } else if ([kind isEqualToString:@"key"]) {
        control.bindingKind = CustomBindingKindKey;
        NSString *keyName = StringFromJSON(binding[@"key"]);
        uint16_t code = [self keyCodeForName:keyName];
        if (code == 0) {
            if (error) *error = CustomLayoutError(@"Unknown keyboard key '%@'.", keyName);
            return nil;
        }
        control.keyCode = code;
        // A modifier that is only held while a finger is down is nearly useless
        // on a touch screen, so default modifiers to sticky. options.sticky
        // below overrides this when it is present.
        control.sticky = [self isModifierKeyCode:code];
    } else if ([kind isEqualToString:@"specialStick"]) {
        control.bindingKind = CustomBindingKindSpecialStick;
        // A special stick is stick-shaped by definition, so do not make a
        // hand-written document spell that out.
        control.type = CustomControlTypeStick;

        NSDictionary *directions = DictionaryFromJSON(binding[@"directions"]);
        for (NSInteger i = 0; i <= (NSInteger)CustomStickDirectionRight; i++) {
            CustomStickDirection direction = (CustomStickDirection)i;
            NSDictionary *entry = DictionaryFromJSON(directions[[self nameForDirection:direction]]);
            if (entry == nil) {
                // Absent means deliberately unassigned.
                continue;
            }

            CustomDigitalBinding *digital = [self digitalBindingFromDictionary:entry error:error];
            if (digital == nil) {
                return nil;
            }
            [control setBinding:digital forDirection:direction];
        }
    } else if ([kind isEqualToString:@"mouse"]) {
        control.bindingKind = CustomBindingKindMouse;
        // A stick-shaped mouse control takes its direction from the drag, so it
        // only stores one when it is button-shaped.
        if (![control isStickShaped]) {
            NSString *name = StringFromJSON(binding[@"direction"]);
            CustomStickDirection direction = CustomStickDirectionUp;
            if (name != nil && ![self directionForName:name out:&direction]) {
                if (error) *error = CustomLayoutError(@"Unknown mouse direction '%@'.", name);
                return nil;
            }
            control.mouseDirection = direction;
        }
    } else if ([kind isEqualToString:@"hideOthers"]) {
        control.bindingKind = CustomBindingKindHideOthers;
        // It is a button by definition: there is nothing to drag.
        control.type = CustomControlTypeButton;
    } else if ([kind isEqualToString:@"showKeyboard"]) {
        control.bindingKind = CustomBindingKindShowKeyboard;
        control.type = CustomControlTypeButton;
    } else {
        if (error) *error = CustomLayoutError(@"Unknown binding kind '%@'.", kind);
        return nil;
    }

    // A stick-shaped control must drive an analog stick or a special stick; the
    // mouse binding is the only one that accepts either shape.
    BOOL stickShaped = (control.type == CustomControlTypeStick);
    BOOL drivesStick = (control.bindingKind == CustomBindingKindStick ||
                        control.bindingKind == CustomBindingKindSpecialStick);
    BOOL mustBeButton = (control.bindingKind == CustomBindingKindButton ||
                         control.bindingKind == CustomBindingKindTrigger ||
                         control.bindingKind == CustomBindingKindKey ||
                         control.bindingKind == CustomBindingKindHideOthers ||
                         control.bindingKind == CustomBindingKindShowKeyboard);
    if ((drivesStick && !stickShaped) || (mustBeButton && stickShaped)) {
        if (error) *error = CustomLayoutError(@"Control '%@': type '%@' does not match its binding.",
                                              control.controlId, type);
        return nil;
    }

    NSDictionary *options = DictionaryFromJSON(dict[@"options"]);
    control.clickable = BoolFromJSON(options[@"clickable"], NO);
    control.deadZone = ClampDouble(DoubleFromJSON(options[@"deadZone"], kDefaultDeadZone),
                                   kMinDeadZone, kMaxDeadZone);
    control.sticky = BoolFromJSON(options[@"sticky"], control.sticky);
    control.mouseRate = ClampDouble(DoubleFromJSON(options[@"rate"], kDefaultMouseRate),
                                    kMinMouseRate, kMaxMouseRate);

    // Sticky is about a control being held without a finger; a stick's value is
    // its position, so the flag means nothing there.
    if (control.type == CustomControlTypeStick) {
        control.sticky = NO;
    }

    return control;
}

+ (CustomDigitalBinding *)digitalBindingFromDictionary:(NSDictionary *)dict error:(NSError **)error {
    NSString *source = StringFromJSON(dict[@"source"]);
    if (source == nil) {
        return [CustomDigitalBinding unassigned];
    }

    if ([source isEqualToString:@"button"]) {
        NSString *name = StringFromJSON(dict[@"button"]);
        uint32_t flag = [self flagForButtonName:name];
        if (flag == 0) {
            if (error) *error = CustomLayoutError(@"Unknown direction button '%@'.", name);
            return nil;
        }
        return [CustomDigitalBinding bindingWithButtonFlag:flag];
    }

    if ([source isEqualToString:@"key"]) {
        NSString *name = StringFromJSON(dict[@"key"]);
        uint16_t code = [self keyCodeForName:name];
        if (code == 0) {
            if (error) *error = CustomLayoutError(@"Unknown direction key '%@'.", name);
            return nil;
        }
        return [CustomDigitalBinding bindingWithKeyCode:code];
    }

    if (error) *error = CustomLayoutError(@"Unknown direction source '%@'.", source);
    return nil;
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

- (BOOL)validate:(NSError **)error {
    if (self.name.length == 0) {
        if (error) *error = CustomLayoutError(@"Layout name must not be empty.");
        return NO;
    }
    if (self.name.length > kMaxNameLength) {
        if (error) *error = CustomLayoutError(@"Layout name is longer than %lu characters.",
                                              (unsigned long)kMaxNameLength);
        return NO;
    }
    if (self.controls.count > CUSTOM_LAYOUT_MAX_CONTROLS) {
        if (error) *error = CustomLayoutError(@"Layout has %lu controls, the limit is %d.",
                                              (unsigned long)self.controls.count, CUSTOM_LAYOUT_MAX_CONTROLS);
        return NO;
    }

    NSMutableSet<NSString *> *seenIds = [NSMutableSet setWithCapacity:self.controls.count];

    for (NSUInteger i = 0; i < self.controls.count; i++) {
        CustomControl *control = self.controls[i];

        if (control.controlId.length == 0) {
            if (error) *error = CustomLayoutError(@"Control at index %lu has no id.", (unsigned long)i);
            return NO;
        }
        if ([seenIds containsObject:control.controlId]) {
            if (error) *error = CustomLayoutError(@"Duplicate control id '%@'.", control.controlId);
            return NO;
        }
        [seenIds addObject:control.controlId];

        if (control.sizePt < kMinSizePt || control.sizePt > kMaxSizePt) {
            if (error) *error = CustomLayoutError(@"Control '%@': size must be between %.0f and %.0f pt.",
                                                  control.controlId, kMinSizePt, kMaxSizePt);
            return NO;
        }
        if (control.aspect < kMinAspect || control.aspect > kMaxAspect) {
            if (error) *error = CustomLayoutError(@"Control '%@': aspect must be between %.1f and %.1f.",
                                                  control.controlId, kMinAspect, kMaxAspect);
            return NO;
        }
        if (fabs(control.offsetX) > kOffsetLimit || fabs(control.offsetY) > kOffsetLimit) {
            if (error) *error = CustomLayoutError(@"Control '%@': offset must stay within +/-%.1f.",
                                                  control.controlId, kOffsetLimit);
            return NO;
        }
        if (control.bindingKind == CustomBindingKindButton && control.buttonFlag == 0) {
            if (error) *error = CustomLayoutError(@"Control '%@' has no button bound.", control.controlId);
            return NO;
        }
        if (control.bindingKind == CustomBindingKindKey && control.keyCode == 0) {
            if (error) *error = CustomLayoutError(@"Control '%@' has no keyboard key bound.", control.controlId);
            return NO;
        }
        if (control.bindingKind == CustomBindingKindMouse &&
            (control.mouseRate < kMinMouseRate || control.mouseRate > kMaxMouseRate)) {
            if (error) *error = CustomLayoutError(@"Control '%@': mouse rate must be between %.0f and %.0f pt/s.",
                                                  control.controlId, kMinMouseRate, kMaxMouseRate);
            return NO;
        }
        if (control.deadZone < kMinDeadZone || control.deadZone > kMaxDeadZone) {
            if (error) *error = CustomLayoutError(@"Control '%@': dead zone must be between %.2f and %.2f.",
                                                  control.controlId, kMinDeadZone, kMaxDeadZone);
            return NO;
        }
        // Sticky is about a control being held without a finger. Hide-others is
        // inherently a toggle and a stick's value is its position, so the flag is
        // meaningless for both.
        if (control.sticky && ([control isStickShaped] ||
                               control.bindingKind == CustomBindingKindHideOthers ||
                               control.bindingKind == CustomBindingKindShowKeyboard)) {
            if (error) *error = CustomLayoutError(@"Control '%@': sticky is not meaningful for this binding.",
                                                  control.controlId);
            return NO;
        }
        if (control.bindingKind == CustomBindingKindSpecialStick) {
            // A special stick with no direction bound would draw a stick that
            // does nothing at all, which is almost certainly a mistake.
            BOOL anyAssigned = NO;
            for (NSInteger d = 0; d <= (NSInteger)CustomStickDirectionRight; d++) {
                if ([[control bindingForDirection:(CustomStickDirection)d] isAssigned]) {
                    anyAssigned = YES;
                    break;
                }
            }
            if (!anyAssigned) {
                if (error) *error = CustomLayoutError(@"Control '%@' is a special stick with no direction bound.",
                                                      control.controlId);
                return NO;
            }
        }

        // Duplicate digital bindings are fine: the overlay diffs the aggregate
        // desired state, so the flag stays set while any holder is pressed.
        // Duplicate analog bindings are not: sticks and triggers are written by
        // direct assignment and would clobber each other.
        for (NSUInteger j = 0; j < i; j++) {
            CustomControl *other = self.controls[j];
            if (control.bindingKind != CustomBindingKindButton &&
                [control bindsSameInputAs:other]) {
                if (error) *error = CustomLayoutError(@"Controls '%@' and '%@' drive the same analog axis.",
                                                      other.controlId, control.controlId);
                return NO;
            }
        }
    }

    return YES;
}

@end
