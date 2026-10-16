//
//  CustomControlsEditorViewController.m
//  Moonlight
//

#import "CustomControlsEditorViewController.h"

#import "DataManager.h"

static const CGFloat kToolbarWidth = 236.0;
static const CGFloat kHandleWidth = 18.0;
static const CGFloat kHandleHeight = 76.0;
static const CGFloat kToolbarButtonHeight = 48.0;

// Size slider range. The upper bound stays inside what CustomLayoutDocument
// accepts, and the mouse rate range has to match the model's exactly.
static const CGFloat kEditorMinSizePt = 24.0;
static const CGFloat kEditorMaxSizePt = 240.0;
static const double kEditorMinMouseRate = 60.0;
static const double kEditorMaxMouseRate = 2000.0;

// Stick dead zone: the same range the model validates against, stepped onto the
// 0.01 grid so the value is easy to read back.
static const double kEditorMinDeadZone = 0.0;
static const double kEditorMaxDeadZone = 0.5;
static const double kEditorDeadZoneStep = 0.01;

// Floating slider panel.
static const CGFloat kSliderPanelHeight = 108.0;
static const CGFloat kSliderPanelMaxWidth = 420.0;

#pragma mark - EditorControlView

// A draggable, selectable representation of one CustomControl on the canvas.
@interface EditorControlView : UIView

@property (nonatomic, strong) CustomControl *control;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic) BOOL selected;

- (instancetype)initWithControl:(CustomControl *)control;
- (NSString *)bindingDescription;
- (void)refreshFromControl;

@end

@implementation EditorControlView

- (instancetype)initWithControl:(CustomControl *)control {
    self = [super initWithFrame:CGRectZero];
    if (self == nil) {
        return nil;
    }

    _control = control;

    self.layer.borderWidth = 2.0;
    self.layer.borderColor = [[UIColor whiteColor] CGColor];
    self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.20];
    self.userInteractionEnabled = YES;

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.textColor = [UIColor whiteColor];
    _titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
    _titleLabel.adjustsFontSizeToFitWidth = YES;
    _titleLabel.minimumScaleFactor = 0.5;
    _titleLabel.userInteractionEnabled = NO;
    [self addSubview:_titleLabel];

    [self refreshFromControl];

    return self;
}

- (NSString *)bindingDescription {
    switch (self.control.bindingKind) {
        case CustomBindingKindButton: {
            NSString *name = [CustomLayoutDocument buttonNameForFlag:self.control.buttonFlag];
            return name.length ? name : @"?";
        }
        case CustomBindingKindStick:
            return self.control.bindLeft ? @"L-Stick" : @"R-Stick";
        case CustomBindingKindTrigger:
            return self.control.bindLeft ? @"LT" : @"RT";
        case CustomBindingKindKey: {
            NSString *name = [CustomLayoutDocument keyNameForCode:self.control.keyCode];
            return name.length ? name : @"?";
        }
        case CustomBindingKindSpecialStick:
            return @"D-Pad";
        case CustomBindingKindMouse:
            return @"Mouse";
        case CustomBindingKindHideOthers:
            return @"Hide";
        case CustomBindingKindShowKeyboard:
            return @"Keyboard";
    }
    return @"?";
}

- (void)refreshFromControl {
    NSString *title = self.control.label.length ? self.control.label : [self bindingDescription];

    // A latched control behaves differently from a held one, so mark it. This is
    // display only; control.label keeps the plain name for the document.
    if (self.control.sticky && self.control.type != CustomControlTypeStick) {
        title = [title stringByAppendingString:@" \u21bb"];
    }

    self.titleText = title;
    [self setSelected:self.selected];
    [self setNeedsLayout];
}

- (void)setTitleText:(NSString *)titleText {
    _titleText = [titleText copy];
    self.titleLabel.text = titleText;
}

- (void)setSelected:(BOOL)selected {
    _selected = selected;

    if (selected) {
        self.layer.borderColor = [[UIColor systemYellowColor] CGColor];
        self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.32];
    } else {
        self.layer.borderColor = [[UIColor whiteColor] CGColor];
        self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.20];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat radius = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds)) / 2.0;
    self.layer.cornerRadius = (self.control.type == CustomControlTypeStick) ? radius : 10.0;
    self.titleLabel.frame = self.bounds;
}

@end

#pragma mark - CustomControlsEditorViewController

// Private surface, declared up front so the implementation order is irrelevant.
@interface CustomControlsEditorViewController ()
- (void)buildToolbar;
- (UIButton *)toolbarButtonWithTitle:(NSString *)title action:(SEL)action;
- (void)updateHandleGlyph;
- (void)installGestures;
- (void)rebuildControlViews;
- (EditorControlView *)selectedControlView;
- (EditorControlView *)controlViewAtPoint:(CGPoint)point;
- (void)layoutControlViews;
- (void)layoutSafeAreaGuide;
- (void)layoutToolbar;
- (void)layoutToolbarContents;
- (void)layoutHandle;
- (void)buildSliderPanel;
- (void)layoutSliderPanel;
- (void)presentSliderPanelWithTitle:(NSString *)title
                                min:(double)minValue
                                max:(double)maxValue
                               step:(double)step
                              value:(double)value
                             format:(NSString *)format
                           onChange:(void (^)(double value))onChange;
- (void)dismissSliderPanel;
- (void)sliderPanelChanged;
- (void)showDeadZoneMenuForView:(EditorControlView *)view;
- (void)writeBackPositionForControlView:(EditorControlView *)view;
- (void)handleControlPan:(UIPanGestureRecognizer *)recognizer;
- (void)handleControlTap:(UITapGestureRecognizer *)recognizer;
- (void)handleCanvasTap:(UITapGestureRecognizer *)recognizer;
- (void)handleEdgePan:(UIScreenEdgePanGestureRecognizer *)recognizer;
- (void)handleHandleTap:(UITapGestureRecognizer *)recognizer;
- (void)setToolbarX:(CGFloat)x;
- (void)setToolbarOpen:(BOOL)open animated:(BOOL)animated;
- (NSArray<NSDictionary *> *)palette;
- (NSString *)displayTitleForControl:(CustomControl *)control;
- (void)addControlTapped;
- (void)addControlFromPaletteEntry:(NSDictionary *)entry;
- (void)showAddKeyCategoryMenu;
- (void)showAddKeyMenuForCategory:(NSString *)category;
- (void)addKeyControlNamed:(NSString *)name;
- (void)showControlMenuForView:(EditorControlView *)view;
- (void)showBindingMenuForView:(EditorControlView *)view;
- (void)showBindingGamepadMenuForView:(EditorControlView *)view;
- (void)showBindingKeyCategoryMenuForView:(EditorControlView *)view;
- (void)showBindingKeyMenuForView:(EditorControlView *)view category:(NSString *)category;
- (void)applyKeyNamed:(NSString *)name toControlView:(EditorControlView *)view;
- (void)showSizeMenuForView:(EditorControlView *)view;
- (void)showRateMenuForView:(EditorControlView *)view;
- (void)showMouseDirectionMenuForView:(EditorControlView *)view;
- (void)showAnchorMenuForView:(EditorControlView *)view;
- (void)applyAnchor:(CustomAnchor)anchor toControlView:(EditorControlView *)view;
- (NSString *)displayNameForAnchor:(CustomAnchor)anchor;
- (void)applySpecialStickToControlView:(EditorControlView *)view;
- (void)applyMouseToControlView:(EditorControlView *)view stickShaped:(BOOL)stickShaped;
- (void)applyHideOthersToControlView:(EditorControlView *)view;
- (void)applyShowKeyboardToControlView:(EditorControlView *)view;
- (void)addMouseControlStickShaped:(BOOL)stickShaped;
- (void)addHideOthersControl;
- (void)addShowKeyboardControl;
- (void)applyPaletteEntry:(NSDictionary *)entry toControlView:(EditorControlView *)view;
- (void)deleteControlView:(EditorControlView *)view;
- (NSArray<NSDictionary *> *)gamepadButtonPalette;
- (void)showDirectionsMenuForView:(EditorControlView *)view;
- (void)showDirectionPickerForView:(EditorControlView *)view direction:(CustomStickDirection)direction;
- (void)presentDigitalBindingPickerForTitle:(NSString *)title
                                   fromView:(UIView *)sourceView
                                   onChoose:(void (^)(CustomDigitalBinding *binding))onChoose;
- (void)presentGamepadButtonPickerForTitle:(NSString *)title
                                  fromView:(UIView *)sourceView
                                  onChoose:(void (^)(CustomDigitalBinding *binding))onChoose;
- (void)presentKeyPickerForTitle:(NSString *)title
                        fromView:(UIView *)sourceView
                        onChoose:(void (^)(CustomDigitalBinding *binding))onChoose;
- (void)presentKeyPickerForTitle:(NSString *)title
                        category:(NSString *)category
                        fromView:(UIView *)sourceView
                        onChoose:(void (^)(CustomDigitalBinding *binding))onChoose;
- (void)saveTapped;
- (void)exitTapped;
- (void)presentSheet:(UIAlertController *)sheet fromView:(UIView *)view;
- (void)showMessage:(NSString *)message;
@end

@implementation CustomControlsEditorViewController {
    TemporaryCustomLayout *_layout;
    CustomLayoutDocument *_document;

    // Fills the window. Controls are laid out inside it with the same call the
    // live overlay uses, so the editor shows exactly what streaming shows.
    UIView *_canvasView;
    CAShapeLayer *_safeAreaBorder;

    NSMutableArray<EditorControlView *> *_controlViews;
    NSString *_selectedControlId;
    BOOL _dirty;

    UIView *_toolbarView;
    UIView *_toolbarHandle;
    UILabel *_toolbarHandleGlyph;
    UILabel *_toolbarTitleLabel;
    UILabel *_toolbarHintLabel;
    BOOL _toolbarOpen;

    // Floating slider, used for anything that is a continuous value: size and
    // the mouse rate. The value is shown above the track so it stays readable
    // while the thumb is under the finger.
    UIView *_sliderPanel;
    UILabel *_sliderPanelTitle;
    UILabel *_sliderPanelValue;
    UISlider *_sliderPanelSlider;
    NSString *_sliderPanelFormat;
    void (^_sliderPanelHandler)(double value);
    // 0 means continuous. Anything else snaps the value to that increment, which
    // UISlider cannot do on its own.
    double _sliderPanelStep;
}

- (instancetype)initWithLayout:(TemporaryCustomLayout *)layout {
    self = [super initWithNibName:nil bundle:nil];
    if (self == nil) {
        return nil;
    }

    _layout = layout;

    // Edit an independent copy so that closing without saving really discards.
    // The round trip through the share token is the cheapest deep copy here.
    NSError *error = nil;
    CustomLayoutDocument *copy = [CustomLayoutDocument layoutFromShareToken:[layout.document shareToken]
                                                                     error:&error];
    if (copy != nil) {
        _document = copy;
    } else {
        Log(LOG_W, @"Could not copy custom layout '%@', editing in place: %@",
            layout.name, error.localizedDescription);
        _document = layout.document;
    }

    _controlViews = [[NSMutableArray alloc] init];

    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1.0];

    _canvasView = [[UIView alloc] initWithFrame:CGRectZero];
    _canvasView.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1.0];
    _canvasView.clipsToBounds = NO;
    [self.view addSubview:_canvasView];

    // Safe area guide: every anchor is measured from the safe area, not from the
    // physical screen corner, so the user has to be able to see it.
    _safeAreaBorder = [CAShapeLayer layer];
    _safeAreaBorder.fillColor = nil;
    _safeAreaBorder.strokeColor = [[UIColor colorWithRed:0.35 green:0.85 blue:1.0 alpha:0.9] CGColor];
    _safeAreaBorder.lineWidth = 1.0;
    _safeAreaBorder.lineDashPattern = @[ @4, @3 ];
    [_canvasView.layer addSublayer:_safeAreaBorder];

    [self buildToolbar];
    [self buildSliderPanel];
    // Gestures first: rebuildControlViews looks the edge recogniser up so the
    // control drag can yield to it near the screen edge.
    [self installGestures];
    [self rebuildControlViews];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // The canvas must be the screen, with no bar insetting it, so that the
    // geometry matches the live overlay exactly.
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    _canvasView.frame = self.view.bounds;

    [self layoutSafeAreaGuide];
    [self layoutControlViews];
    [self layoutToolbar];
    [self layoutSliderPanel];
}

- (void)layoutSafeAreaGuide {
    UIEdgeInsets insets = _canvasView.safeAreaInsets;
    CGSize size = _canvasView.bounds.size;

    CGRect safe = CGRectMake(insets.left,
                             insets.top,
                             MAX(size.width - insets.left - insets.right, 0.0),
                             MAX(size.height - insets.top - insets.bottom, 0.0));

    _safeAreaBorder.frame = _canvasView.bounds;
    _safeAreaBorder.path = [UIBezierPath bezierPathWithRect:safe].CGPath;
}

- (void)layoutControlViews {
    if (_canvasView.bounds.size.width <= 0.0) {
        return;
    }

    // Identical maths to CustomControlsView, deliberately: the frames here are
    // the frames the overlay will use during a stream.
    CGSize size = _canvasView.bounds.size;
    UIEdgeInsets insets = _canvasView.safeAreaInsets;

    for (EditorControlView *view in _controlViews) {
        CGSize controlSize = [view.control renderedSize];
        CGPoint center = [view.control renderedCenterInBounds:size safeInsets:insets];

        view.bounds = CGRectMake(0, 0, controlSize.width, controlSize.height);
        view.center = center;
        [view setSelected:[view.control.controlId isEqualToString:_selectedControlId]];
    }
}

- (void)layoutToolbar {
    CGFloat height = _canvasView.bounds.size.height;
    CGFloat x = _toolbarView.frame.origin.x;
    _toolbarView.frame = CGRectMake(x, 0, kToolbarWidth, height);
    [self layoutToolbarContents];
    [self layoutHandle];
}

- (void)layoutToolbarContents {
    // Use the canvas safe area, not the toolbar's own: while the drawer is
    // closed the toolbar sits off-screen and its own insets collapse to zero,
    // which would make the contents jump on every open.
    UIEdgeInsets insets = _canvasView.safeAreaInsets;
    // Keep the content clear of the sensor housing, which in landscape sits on
    // one of the short edges and is reported as a large left inset.
    CGFloat left = MAX(insets.left, 16.0);
    CGFloat contentWidth = MAX(kToolbarWidth - left - 16.0, 80.0);
    CGFloat y = insets.top + 20.0;

    _toolbarTitleLabel.frame = CGRectMake(left, y, contentWidth, 24.0);
    y = CGRectGetMaxY(_toolbarTitleLabel.frame) + 18.0;

    for (UIView *subview in _toolbarView.subviews) {
        if (![subview isKindOfClass:[UIButton class]]) {
            continue;
        }
        subview.frame = CGRectMake(left, y, contentWidth, kToolbarButtonHeight);
        y = CGRectGetMaxY(subview.frame) + 8.0;
    }

    // The hint follows the buttons instead of being pinned to the bottom, so the
    // two cannot overlap on a short landscape screen.
    CGFloat hintTop = y + 10.0;
    CGFloat hintBottom = CGRectGetMaxY(_toolbarView.frame) - insets.bottom - 12.0;
    _toolbarHintLabel.frame = CGRectMake(left,
                                         hintTop,
                                         contentWidth,
                                         MAX(hintBottom - hintTop, 40.0));
}

- (void)layoutHandle {
    UIEdgeInsets insets = _canvasView.safeAreaInsets;
    CGFloat height = _canvasView.bounds.size.height;
    CGFloat handleHeight = MIN(kHandleHeight, MAX(height - insets.top - insets.bottom - 60.0, 40.0));

    // The handle rides the drawer's right edge so it never lands on top of the
    // toolbar buttons, and it parks just inside the safe area while closed so
    // the sensor housing does not cover it.
    CGFloat x = MAX(CGRectGetMaxX(_toolbarView.frame), insets.left);
    _toolbarHandle.frame = CGRectMake(x, (height - handleHeight) / 2.0, kHandleWidth, handleHeight);
    [_canvasView bringSubviewToFront:_toolbarHandle];
}

// ---------------------------------------------------------------------------
// Toolbar
// ---------------------------------------------------------------------------

- (void)buildToolbar {
    _toolbarView = [[UIView alloc] init];
    _toolbarView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.97];
    _toolbarView.frame = CGRectMake(-kToolbarWidth, 0, kToolbarWidth, 100);
    [_canvasView addSubview:_toolbarView];

    _toolbarTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _toolbarTitleLabel.text = _document.name.length ? _document.name : @"Layout";
    _toolbarTitleLabel.textColor = [UIColor whiteColor];
    _toolbarTitleLabel.font = [UIFont systemFontOfSize:19.0 weight:UIFontWeightBold];
    _toolbarTitleLabel.numberOfLines = 1;
    _toolbarTitleLabel.adjustsFontSizeToFitWidth = YES;
    _toolbarTitleLabel.minimumScaleFactor = 0.6;
    [_toolbarView addSubview:_toolbarTitleLabel];

    [_toolbarView addSubview:[self toolbarButtonWithTitle:@"Add Control" action:@selector(addControlTapped)]];
    [_toolbarView addSubview:[self toolbarButtonWithTitle:@"Save" action:@selector(saveTapped)]];
    [_toolbarView addSubview:[self toolbarButtonWithTitle:@"Exit" action:@selector(exitTapped)]];

    _toolbarHintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _toolbarHintLabel.text = @"Drag a control to move it.\n\nTap a control to change its binding or size, or to delete it.\n\nSwipe from the left edge to show or hide this toolbar.";
    _toolbarHintLabel.textColor = [UIColor lightGrayColor];
    _toolbarHintLabel.font = [UIFont systemFontOfSize:12.0];
    _toolbarHintLabel.numberOfLines = 0;
    [_toolbarView addSubview:_toolbarHintLabel];

    // Handle: a slim tab on the left edge, always visible so the drawer is
    // discoverable without knowing the edge-swipe gesture.
    _toolbarHandle = [[UIView alloc] init];
    _toolbarHandle.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
    _toolbarHandle.layer.cornerRadius = kHandleWidth / 2.0;
    _toolbarHandle.userInteractionEnabled = YES;
    [_canvasView addSubview:_toolbarHandle];

    _toolbarHandleGlyph = [[UILabel alloc] initWithFrame:CGRectZero];
    _toolbarHandleGlyph.textAlignment = NSTextAlignmentCenter;
    _toolbarHandleGlyph.textColor = [UIColor whiteColor];
    _toolbarHandleGlyph.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
    _toolbarHandleGlyph.userInteractionEnabled = NO;
    [_toolbarHandle addSubview:_toolbarHandleGlyph];

    [self updateHandleGlyph];

    UITapGestureRecognizer *handleTap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                               action:@selector(handleHandleTap:)];
    [_toolbarHandle addGestureRecognizer:handleTap];
}

- (UIButton *)toolbarButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    button.layer.cornerRadius = 10.0;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)updateHandleGlyph {
    _toolbarHandleGlyph.text = _toolbarOpen ? @"\u2039" : @"\u203a";
}

- (void)setToolbarX:(CGFloat)x {
    CGRect frame = _toolbarView.frame;
    frame.origin.x = x;
    _toolbarView.frame = frame;
    // The handle rides the drawer edge, so it has to follow during a drag too.
    [self layoutHandle];
}

- (void)setToolbarOpen:(BOOL)open animated:(BOOL)animated {
    _toolbarOpen = open;
    [self updateHandleGlyph];

    CGFloat target = open ? 0.0 : -kToolbarWidth;
    if (!animated) {
        [self setToolbarX:target];
        return;
    }

    [UIView animateWithDuration:0.25
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        [self setToolbarX:target];
    } completion:nil];
}

// ---------------------------------------------------------------------------
// Floating slider panel
// ---------------------------------------------------------------------------

- (void)buildSliderPanel {
    _sliderPanel = [[UIView alloc] init];
    _sliderPanel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.96];
    _sliderPanel.layer.cornerRadius = 14.0;
    _sliderPanel.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.18] CGColor];
    _sliderPanel.layer.borderWidth = 1.0;
    _sliderPanel.hidden = YES;
    [_canvasView addSubview:_sliderPanel];

    _sliderPanelTitle = [[UILabel alloc] initWithFrame:CGRectZero];
    _sliderPanelTitle.textColor = [UIColor lightGrayColor];
    _sliderPanelTitle.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
    [_sliderPanel addSubview:_sliderPanelTitle];

    // The value sits above the track, so the finger never covers it.
    _sliderPanelValue = [[UILabel alloc] initWithFrame:CGRectZero];
    _sliderPanelValue.textColor = [UIColor whiteColor];
    _sliderPanelValue.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];
    [_sliderPanel addSubview:_sliderPanelValue];

    _sliderPanelSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    [_sliderPanelSlider addTarget:self
                           action:@selector(sliderPanelChanged)
                 forControlEvents:UIControlEventValueChanged];
    [_sliderPanel addSubview:_sliderPanelSlider];
}

- (void)layoutSliderPanel {
    if (_sliderPanel == nil || _sliderPanel.hidden) {
        return;
    }

    UIEdgeInsets insets = _canvasView.safeAreaInsets;
    CGSize size = _canvasView.bounds.size;

    CGFloat width = MIN(kSliderPanelMaxWidth, size.width - insets.left - insets.right - 32.0);
    width = MAX(width, 200.0);

    _sliderPanel.frame = CGRectMake((size.width - width) / 2.0,
                                    size.height - insets.bottom - kSliderPanelHeight - 24.0,
                                    width,
                                    kSliderPanelHeight);

    CGFloat side = 16.0;
    CGFloat contentWidth = width - side * 2.0;
    _sliderPanelTitle.frame = CGRectMake(side, 10.0, contentWidth, 16.0);
    _sliderPanelValue.frame = CGRectMake(side, 28.0, contentWidth, 24.0);
    _sliderPanelSlider.frame = CGRectMake(side, 60.0, contentWidth, 32.0);
}

- (void)presentSliderPanelWithTitle:(NSString *)title
                                min:(double)minValue
                                max:(double)maxValue
                               step:(double)step
                              value:(double)value
                             format:(NSString *)format
                           onChange:(void (^)(double value))onChange {
    _sliderPanelFormat = [format copy];
    _sliderPanelHandler = [onChange copy];
    _sliderPanelStep = step;

    // A step whose value is not on the grid would otherwise snap on the first
    // touch, which looks like the panel jumped.
    if (step > 0.0) {
        value = round(value / step) * step;
    }

    _sliderPanelTitle.text = title;
    _sliderPanelSlider.minimumValue = (float)minValue;
    _sliderPanelSlider.maximumValue = (float)maxValue;
    _sliderPanelSlider.value = (float)value;
    _sliderPanelValue.text = [NSString stringWithFormat:format, value];

    _sliderPanel.hidden = NO;
    // Above the controls, but below the drawer and its handle so those stay
    // reachable while a value is being adjusted.
    [_canvasView bringSubviewToFront:_sliderPanel];
    [_canvasView bringSubviewToFront:_toolbarView];
    [_canvasView bringSubviewToFront:_toolbarHandle];

    [self layoutSliderPanel];
}

- (void)sliderPanelChanged {
    double value = _sliderPanelSlider.value;

    if (_sliderPanelStep > 0.0) {
        value = round(value / _sliderPanelStep) * _sliderPanelStep;
        // Setting value programmatically does not re-send the action, so this
        // cannot recurse; it just makes the thumb sit on the step.
        _sliderPanelSlider.value = (float)value;
    }

    _sliderPanelValue.text = [NSString stringWithFormat:_sliderPanelFormat, value];

    if (_sliderPanelHandler != nil) {
        _sliderPanelHandler(value);
    }
}

- (void)dismissSliderPanel {
    _sliderPanel.hidden = YES;
    _sliderPanelHandler = nil;
}

// ---------------------------------------------------------------------------
// Gestures
// ---------------------------------------------------------------------------

- (void)installGestures {
    // Left-edge swipe opens the drawer, tracking the finger while it moves.
    UIScreenEdgePanGestureRecognizer *edgePan =
        [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(handleEdgePan:)];
    edgePan.edges = UIRectEdgeLeft;
    [self.view addGestureRecognizer:edgePan];

    // Tapping empty canvas closes the drawer and clears the selection.
    UITapGestureRecognizer *canvasTap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                               action:@selector(handleCanvasTap:)];
    [_canvasView addGestureRecognizer:canvasTap];
}

- (void)handleEdgePan:(UIScreenEdgePanGestureRecognizer *)recognizer {
    CGFloat translation = [recognizer translationInView:self.view].x;
    CGFloat baseX = _toolbarOpen ? 0.0 : -kToolbarWidth;

    switch (recognizer.state) {
        case UIGestureRecognizerStateChanged: {
            CGFloat x = MAX(-kToolbarWidth, MIN(0.0, baseX + translation));
            [self setToolbarX:x];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
            [self setToolbarOpen:(_toolbarView.frame.origin.x > -kToolbarWidth / 2.0) animated:YES];
            break;
        default:
            break;
    }
}

- (void)handleHandleTap:(UITapGestureRecognizer *)recognizer {
    [self setToolbarOpen:!_toolbarOpen animated:YES];
}

- (void)handleCanvasTap:(UITapGestureRecognizer *)recognizer {
    CGPoint point = [recognizer locationInView:_canvasView];

    // A tap that landed on a control is handled by that control.
    if ([self controlViewAtPoint:point] != nil) {
        return;
    }

    // The toolbar and the handle are subviews of the canvas, so their taps reach
    // this recogniser too. Leave them to their own handlers.
    if (CGRectContainsPoint(_toolbarView.frame, point)) {
        return;
    }
    if (CGRectContainsPoint(_toolbarHandle.frame, point)) {
        return;
    }
    if (!_sliderPanel.hidden && CGRectContainsPoint(_sliderPanel.frame, point)) {
        return;
    }

    [self dismissSliderPanel];
    _selectedControlId = nil;
    [self layoutControlViews];
    [self setToolbarOpen:NO animated:YES];
}

- (void)handleControlTap:(UITapGestureRecognizer *)recognizer {
    EditorControlView *view = (EditorControlView *)recognizer.view;
    if (![view isKindOfClass:[EditorControlView class]]) {
        return;
    }

    _selectedControlId = view.control.controlId;
    [self layoutControlViews];
    [self showControlMenuForView:view];
}

- (void)handleControlPan:(UIPanGestureRecognizer *)recognizer {
    EditorControlView *view = (EditorControlView *)recognizer.view;
    if (![view isKindOfClass:[EditorControlView class]]) {
        return;
    }

    if (recognizer.state == UIGestureRecognizerStateBegan) {
        _selectedControlId = view.control.controlId;
        [self layoutControlViews];
        return;
    }

    if (recognizer.state != UIGestureRecognizerStateChanged) {
        return;
    }

    CGPoint translation = [recognizer translationInView:_canvasView];
    [recognizer setTranslation:CGPointZero inView:_canvasView];

    // The canvas is the screen, so a canvas-space translation is already a
    // device-space translation and needs no scaling.
    view.center = CGPointMake(view.center.x + translation.x, view.center.y + translation.y);
    [self writeBackPositionForControlView:view];
    _dirty = YES;
}

// Converts the dragged position back into offsets. The offsets are re-derived
// from the clamped centre so the stored value always describes what is actually
// drawn, keeping the editor honest about the safe-area clamp.
- (void)writeBackPositionForControlView:(EditorControlView *)view {
    CGSize size = _canvasView.bounds.size;
    if (size.width <= 0.0 || size.height <= 0.0) {
        return;
    }

    UIEdgeInsets insets = _canvasView.safeAreaInsets;
    CGPoint origin = [view.control anchorOriginInBounds:size safeInsets:insets];

    view.control.offsetX = (view.center.x - origin.x) / size.width;
    view.control.offsetY = (view.center.y - origin.y) / size.height;

    CGPoint clamped = [view.control renderedCenterInBounds:size safeInsets:insets];
    view.control.offsetX = (clamped.x - origin.x) / size.width;
    view.control.offsetY = (clamped.y - origin.y) / size.height;

    view.center = clamped;
}

// ---------------------------------------------------------------------------
// Control views
// ---------------------------------------------------------------------------

- (void)rebuildControlViews {
    for (EditorControlView *view in _controlViews) {
        [view removeFromSuperview];
    }
    [_controlViews removeAllObjects];

    UIScreenEdgePanGestureRecognizer *edgePan = nil;
    for (UIGestureRecognizer *recognizer in self.view.gestureRecognizers) {
        if ([recognizer isKindOfClass:[UIScreenEdgePanGestureRecognizer class]]) {
            edgePan = (UIScreenEdgePanGestureRecognizer *)recognizer;
            break;
        }
    }

    for (CustomControl *control in _document.controls) {
        EditorControlView *view = [[EditorControlView alloc] initWithControl:control];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                             action:@selector(handleControlPan:)];
        // A drag that starts on the screen edge belongs to the drawer gesture.
        if (edgePan != nil) {
            [pan requireGestureRecognizerToFail:edgePan];
        }

        [view addGestureRecognizer:pan];
        [view addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(handleControlTap:)]];

        [_canvasView insertSubview:view belowSubview:_toolbarView];
        [_controlViews addObject:view];
    }

    // The handle must stay above the controls.
    [_canvasView bringSubviewToFront:_toolbarHandle];

    [self layoutControlViews];
}

- (EditorControlView *)selectedControlView {
    if (_selectedControlId == nil) {
        return nil;
    }

    for (EditorControlView *view in _controlViews) {
        if ([view.control.controlId isEqualToString:_selectedControlId]) {
            return view;
        }
    }
    return nil;
}

- (EditorControlView *)controlViewAtPoint:(CGPoint)point {
    for (EditorControlView *view in _controlViews) {
        if (CGRectContainsPoint(view.frame, point)) {
            return view;
        }
    }
    return nil;
}

// ---------------------------------------------------------------------------
// Palette and menus
// ---------------------------------------------------------------------------

- (NSArray<NSDictionary *> *)palette {
    return @[
        @{ @"title": @"A", @"icon": @"AButton", @"button": @"A" },
        @{ @"title": @"B", @"icon": @"BButton", @"button": @"B" },
        @{ @"title": @"X", @"icon": @"XButton", @"button": @"X" },
        @{ @"title": @"Y", @"icon": @"YButton", @"button": @"Y" },
        @{ @"title": @"LB", @"icon": @"L1", @"button": @"LB" },
        @{ @"title": @"RB", @"icon": @"R1", @"button": @"RB" },
        @{ @"title": @"LT", @"icon": @"L2", @"trigger": @"left" },
        @{ @"title": @"RT", @"icon": @"R2", @"trigger": @"right" },
        @{ @"title": @"D-Pad Up", @"icon": @"UpButton", @"button": @"Up" },
        @{ @"title": @"D-Pad Down", @"icon": @"DownButton", @"button": @"Down" },
        @{ @"title": @"D-Pad Left", @"icon": @"LeftButton", @"button": @"Left" },
        @{ @"title": @"D-Pad Right", @"icon": @"RightButton", @"button": @"Right" },
        @{ @"title": @"Start", @"icon": @"StartButton", @"button": @"Start" },
        @{ @"title": @"Back", @"icon": @"SelectButton", @"button": @"Back" },
        @{ @"title": @"L3", @"icon": @"L3", @"button": @"L3" },
        @{ @"title": @"R3", @"icon": @"R3", @"button": @"R3" },
        @{ @"title": @"Left Stick", @"icon": @"StickOuter", @"stick": @"left" },
        @{ @"title": @"Right Stick", @"icon": @"StickOuter", @"stick": @"right" },
    ];
}


- (NSString *)displayTitleForControl:(CustomControl *)control {
    return control.label.length ? control.label : @"Control";
}

- (void)addControlTapped {
    if (_document.controls.count >= CUSTOM_LAYOUT_MAX_CONTROLS) {
        [self showMessage:[NSString stringWithFormat:@"This layout already has the maximum of %d controls.",
                           CUSTOM_LAYOUT_MAX_CONTROLS]];
        return;
    }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Add Control"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    // Gamepad and keyboard are peers: each opens its own list rather than the
    // two being mixed into one long sheet.
    [sheet addAction:[UIAlertAction actionWithTitle:@"Gamepad"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [self showAddGamepadMenu];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Keyboard Key\u2026"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [self showAddKeyCategoryMenu];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Special Stick"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [self addSpecialStick];
    }]];
    // Two mouse shapes: a nub takes its direction from the drag, a button has to
    // be told one because there is nothing to drag.
    [sheet addAction:[UIAlertAction actionWithTitle:@"Mouse Nub"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [self addMouseControlStickShaped:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Mouse Button"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [self addMouseControlStickShaped:NO];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Hide Others"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [self addHideOthersControl];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Show Keyboard"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [self addShowKeyboardControl];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [self presentSheet:sheet fromView:_toolbarHandle];
}

- (void)showAddGamepadMenu {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Gamepad"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *entry in [self palette]) {
        [sheet addAction:[UIAlertAction actionWithTitle:entry[@"title"]
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            [self addControlFromPaletteEntry:entry];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [self presentSheet:sheet fromView:_toolbarHandle];
}

// A stick-shaped control whose four directions each emit a digital input. It
// starts mapped to the D-pad so it is immediately useful and passes validation;
// the Directions menu rebinds any of them, which is how you get WASD.
- (void)addSpecialStick {
    CustomControl *control = [[CustomControl alloc] init];
    control.controlId = [[NSUUID UUID] UUIDString];
    control.aspect = 1.0;
    control.anchor = CustomAnchorCenter;
    control.type = CustomControlTypeStick;
    control.bindingKind = CustomBindingKindSpecialStick;
    control.sizePt = 120.0;
    // No icon: the label is what tells it apart from the analog sticks.
    control.label = nil;

    NSArray<NSString *> *defaults = @[ @"Up", @"Down", @"Left", @"Right" ];
    for (NSInteger d = 0; d <= (NSInteger)CustomStickDirectionRight; d++) {
        uint32_t flag = [CustomLayoutDocument flagForButtonName:defaults[(NSUInteger)d]];
        [control setBinding:[CustomDigitalBinding bindingWithButtonFlag:flag]
               forDirection:(CustomStickDirection)d];
    }

    NSUInteger count = _document.controls.count;
    control.offsetX = ((double)(count % 5) - 2.0) * 0.06;
    control.offsetY = ((double)(count % 3) - 1.0) * 0.08;

    NSMutableArray *controls = [_document.controls mutableCopy];
    [controls addObject:control];
    _document.controls = controls;

    _selectedControlId = control.controlId;
    _dirty = YES;

    [self rebuildControlViews];
}

- (void)addMouseControlStickShaped:(BOOL)stickShaped {
    CustomControl *control = [[CustomControl alloc] init];
    control.controlId = [[NSUUID UUID] UUIDString];
    control.aspect = 1.0;
    control.anchor = CustomAnchorCenter;
    control.bindingKind = CustomBindingKindMouse;
    control.mouseRate = 600.0;
    control.mouseDirection = CustomStickDirectionUp;

    if (stickShaped) {
        control.type = CustomControlTypeStick;
        control.sizePt = 120.0;
        control.label = nil;
    } else {
        control.type = CustomControlTypeButton;
        control.sizePt = 56.0;
        control.label = @"Mouse";
        // A fixed-direction button is usually wanted as a hold, so leave sticky
        // off; the menu can turn it on for a latched scroll-like behaviour.
    }

    NSUInteger count = _document.controls.count;
    control.offsetX = ((double)(count % 5) - 2.0) * 0.06;
    control.offsetY = ((double)(count % 3) - 1.0) * 0.08;

    NSMutableArray *controls = [_document.controls mutableCopy];
    [controls addObject:control];
    _document.controls = controls;

    _selectedControlId = control.controlId;
    _dirty = YES;

    [self rebuildControlViews];
}

- (void)addHideOthersControl {
    CustomControl *control = [[CustomControl alloc] init];
    control.controlId = [[NSUUID UUID] UUIDString];
    control.aspect = 1.0;
    control.anchor = CustomAnchorCenter;
    control.type = CustomControlTypeButton;
    control.bindingKind = CustomBindingKindHideOthers;
    control.sizePt = 56.0;
    control.label = @"Hide";

    NSUInteger count = _document.controls.count;
    control.offsetX = ((double)(count % 5) - 2.0) * 0.06;
    control.offsetY = ((double)(count % 3) - 1.0) * 0.08;

    NSMutableArray *controls = [_document.controls mutableCopy];
    [controls addObject:control];
    _document.controls = controls;

    _selectedControlId = control.controlId;
    _dirty = YES;

    [self rebuildControlViews];
}

// Keyboard keys are grouped by category; 70-odd keys in one sheet is unusable.

- (void)addShowKeyboardControl {
    CustomControl *control = [[CustomControl alloc] init];
    control.controlId = [[NSUUID UUID] UUIDString];
    control.aspect = 1.0;
    control.anchor = CustomAnchorCenter;
    control.type = CustomControlTypeButton;
    control.bindingKind = CustomBindingKindShowKeyboard;
    control.sizePt = 56.0;
    control.label = @"OSK";

    NSUInteger count = _document.controls.count;
    control.offsetX = ((double)(count % 5) - 2.0) * 0.06;
    control.offsetY = ((double)(count % 3) - 1.0) * 0.08;

    NSMutableArray *controls = [_document.controls mutableCopy];
    [controls addObject:control];
    _document.controls = controls;

    _selectedControlId = control.controlId;
    _dirty = YES;

    [self rebuildControlViews];
}

- (void)showAddKeyCategoryMenu {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Keyboard Key"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *category in [CustomLayoutDocument keyCategories]) {
        [sheet addAction:[UIAlertAction actionWithTitle:category
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            [self showAddKeyMenuForCategory:category];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [self presentSheet:sheet fromView:_toolbarHandle];
}

- (void)showAddKeyMenuForCategory:(NSString *)category {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:category
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *name in [CustomLayoutDocument keyNamesInCategory:category]) {
        [sheet addAction:[UIAlertAction actionWithTitle:name
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            [self addKeyControlNamed:name];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [self presentSheet:sheet fromView:_toolbarHandle];
}

- (void)addKeyControlNamed:(NSString *)name {
    uint16_t code = [CustomLayoutDocument keyCodeForName:name];
    if (code == 0) {
        return;
    }

    CustomControl *control = [[CustomControl alloc] init];
    control.controlId = [[NSUUID UUID] UUIDString];
    control.aspect = 1.0;
    control.anchor = CustomAnchorCenter;
    control.type = CustomControlTypeButton;
    control.bindingKind = CustomBindingKindKey;
    control.keyCode = code;
    control.label = name;
    control.sizePt = 56.0;
    // A modifier that is only held while a finger is down is nearly useless on a
    // touch screen, since the second key needs a second finger, so modifiers
    // start sticky. The per-control menu can change it either way.
    control.sticky = [CustomLayoutDocument isModifierKeyCode:code];

    NSUInteger count = _document.controls.count;
    control.offsetX = ((double)(count % 5) - 2.0) * 0.06;
    control.offsetY = ((double)(count % 3) - 1.0) * 0.08;

    NSMutableArray *controls = [_document.controls mutableCopy];
    [controls addObject:control];
    _document.controls = controls;

    _selectedControlId = control.controlId;
    _dirty = YES;

    [self rebuildControlViews];
}

- (void)addControlFromPaletteEntry:(NSDictionary *)entry {
    CustomControl *control = [[CustomControl alloc] init];
    control.controlId = [[NSUUID UUID] UUIDString];
    control.aspect = 1.0;
    control.anchor = CustomAnchorCenter;

    if (entry[@"button"] != nil) {
        control.type = CustomControlTypeButton;
        control.bindingKind = CustomBindingKindButton;
        control.buttonFlag = [CustomLayoutDocument flagForButtonName:entry[@"button"]];
        control.sizePt = 56.0;
    } else if (entry[@"stick"] != nil) {
        control.type = CustomControlTypeStick;
        control.bindingKind = CustomBindingKindStick;
        control.bindLeft = [entry[@"stick"] isEqualToString:@"left"];
        control.sizePt = 120.0;
    } else {
        // Triggers have no bit flag, so they are analog and use the button shape.
        control.type = CustomControlTypeButton;
        control.bindingKind = CustomBindingKindTrigger;
        control.bindLeft = [entry[@"trigger"] isEqualToString:@"left"];
        control.sizePt = 56.0;
    }
    control.icon = entry[@"icon"];
    control.label = entry[@"title"];

    // Reject a second control on the same analog axis before it is added: the
    // validator would refuse to save the layout otherwise.
    for (CustomControl *existing in _document.controls) {
        if (control.bindingKind != CustomBindingKindButton && [control bindsSameInputAs:existing]) {
            [self showMessage:[NSString stringWithFormat:@"'%@' is already bound to that analog axis.",
                               [self displayTitleForControl:existing]]];
            return;
        }
    }

    // Cascade from the centre so a new control is never hidden behind another.
    NSUInteger count = _document.controls.count;
    control.offsetX = ((double)(count % 5) - 2.0) * 0.06;
    control.offsetY = ((double)(count % 3) - 1.0) * 0.08;

    NSMutableArray *controls = [_document.controls mutableCopy];
    [controls addObject:control];
    _document.controls = controls;

    _selectedControlId = control.controlId;
    _dirty = YES;

    [self rebuildControlViews];
}

- (void)showControlMenuForView:(EditorControlView *)view {
    // The floating slider would otherwise sit over this sheet.
    [self dismissSliderPanel];

    CustomControl *control = view.control;
    NSString *title = [NSString stringWithFormat:@"%@  (%.0f pt)",
                       [self displayTitleForControl:control], control.sizePt];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Change Binding"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [self showBindingMenuForView:view];
    }]];
    if (control.bindingKind == CustomBindingKindSpecialStick) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Directions"
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            [self showDirectionsMenuForView:view];
        }]];
    }
    if (control.bindingKind == CustomBindingKindMouse) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Mouse Rate"
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            [self showRateMenuForView:view];
        }]];
        if (![control isStickShaped]) {
            // A button has no drag, so its direction has to be stored.
            [sheet addAction:[UIAlertAction actionWithTitle:
                              [NSString stringWithFormat:@"Mouse Direction: %@",
                               [CustomLayoutDocument nameForDirection:control.mouseDirection]]
                                                     style:UIAlertActionStyleDefault
                                                   handler:^(UIAlertAction *action) {
                [self showMouseDirectionMenuForView:view];
            }]];
        }
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Size"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [self showSizeMenuForView:view];
    }]];

    // Only a stick-shaped control reads a dead zone, so it would be a no-op
    // everywhere else.
    if ([control isStickShaped]) {
        [sheet addAction:[UIAlertAction actionWithTitle:
                          [NSString stringWithFormat:@"Dead Zone: %.2f", control.deadZone]
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            [self showDeadZoneMenuForView:view];
        }]];
    }

    // Every control has one, and it decides which point the offsets are measured
    // from, so it is shown even though most layouts leave it at the default.
    [sheet addAction:[UIAlertAction actionWithTitle:
                      [NSString stringWithFormat:@"Anchor: %@", [self displayNameForAnchor:control.anchor]]
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [self showAnchorMenuForView:view];
    }]];

    // Sticky only means something for a control that is held and that sends a
    // level. A stick's value is its position, and hide-others is already a
    // toggle, so the flag is meaningless for both.
    if (![control isStickShaped] &&
        control.bindingKind != CustomBindingKindHideOthers &&
        control.bindingKind != CustomBindingKindShowKeyboard) {
        NSString *stickyTitle = control.sticky ? @"Sticky: On" : @"Sticky: Off";
        [sheet addAction:[UIAlertAction actionWithTitle:stickyTitle
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            control.sticky = !control.sticky;
            self->_dirty = YES;
            [view refreshFromControl];
            [self layoutControlViews];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Delete"
                                             style:UIAlertActionStyleDestructive
                                           handler:^(UIAlertAction *action) {
        [self deleteControlView:view];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [self presentSheet:sheet fromView:view];
}

// Mirrors the Add Control sheet so the categories match, and so a control can be
// converted into every kind that can be added, including the special ones that
// were previously only reachable at creation time.
- (void)showBindingMenuForView:(EditorControlView *)view {
    [self dismissSliderPanel];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Change Binding"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Gamepad"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [self showBindingGamepadMenuForView:view];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Keyboard Key\u2026"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [self showBindingKeyCategoryMenuForView:view];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Special Stick"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [self applySpecialStickToControlView:view];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Mouse Nub"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [self applyMouseToControlView:view stickShaped:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Mouse Button"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [self applyMouseToControlView:view stickShaped:NO];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Hide Others"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [self applyHideOthersToControlView:view];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Show Keyboard"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [self applyShowKeyboardToControlView:view];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [self presentSheet:sheet fromView:view];
}

- (void)showBindingGamepadMenuForView:(EditorControlView *)view {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Gamepad"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *entry in [self palette]) {
        [sheet addAction:[UIAlertAction actionWithTitle:entry[@"title"]
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            [self applyPaletteEntry:entry toControlView:view];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [self presentSheet:sheet fromView:view];
}

- (void)showBindingKeyCategoryMenuForView:(EditorControlView *)view {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Keyboard Key"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *category in [CustomLayoutDocument keyCategories]) {
        [sheet addAction:[UIAlertAction actionWithTitle:category
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            [self showBindingKeyMenuForView:view category:category];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [self presentSheet:sheet fromView:view];
}

- (void)showBindingKeyMenuForView:(EditorControlView *)view category:(NSString *)category {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:category
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *name in [CustomLayoutDocument keyNamesInCategory:category]) {
        [sheet addAction:[UIAlertAction actionWithTitle:name
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            [self applyKeyNamed:name toControlView:view];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [self presentSheet:sheet fromView:view];
}

- (void)applyKeyNamed:(NSString *)name toControlView:(EditorControlView *)view {
    uint16_t code = [CustomLayoutDocument keyCodeForName:name];
    if (code == 0) {
        return;
    }

    CustomControl *control = view.control;
    CustomControlType previousType = control.type;

    control.type = CustomControlTypeButton;
    control.bindingKind = CustomBindingKindKey;
    control.keyCode = code;
    control.label = name;

    // Keys are digital, so unlike sticks there is no uniqueness rule to check:
    // the renderer diffs the aggregate desired set.
    if (control.type != previousType) {
        control.sizePt = 56.0;
    }

    // A modifier wants to be sticky by default; anything else keeps whatever the
    // user had chosen, since a sticky W is a legitimate toggle-to-run.
    if ([CustomLayoutDocument isModifierKeyCode:code]) {
        control.sticky = YES;
    }

    _dirty = YES;
    [view refreshFromControl];
    [self layoutControlViews];
}

// Converts an existing control into a special stick. The directions default to
// the D-pad the first time so the control is immediately useful and passes the
// validator, which refuses a special stick with nothing bound.
- (void)applySpecialStickToControlView:(EditorControlView *)view {
    CustomControl *control = view.control;

    control.type = CustomControlTypeStick;
    control.bindingKind = CustomBindingKindSpecialStick;
    control.icon = nil;
    control.label = nil;
    // A stick's value is its position, so a sticky flag would be rejected.
    control.sticky = NO;

    BOOL anyAssigned = [[control bindingForDirection:CustomStickDirectionUp] isAssigned] ||
                       [[control bindingForDirection:CustomStickDirectionDown] isAssigned] ||
                       [[control bindingForDirection:CustomStickDirectionLeft] isAssigned] ||
                       [[control bindingForDirection:CustomStickDirectionRight] isAssigned];
    if (!anyAssigned) {
        NSArray<NSString *> *defaults = @[ @"Up", @"Down", @"Left", @"Right" ];
        for (NSInteger d = 0; d <= (NSInteger)CustomStickDirectionRight; d++) {
            uint32_t flag = [CustomLayoutDocument flagForButtonName:defaults[(NSUInteger)d]];
            [control setBinding:[CustomDigitalBinding bindingWithButtonFlag:flag]
                   forDirection:(CustomStickDirection)d];
        }
    }

    control.sizePt = MAX(control.sizePt, 96.0);

    _dirty = YES;
    [view refreshFromControl];
    [self layoutControlViews];
}

- (void)applyMouseToControlView:(EditorControlView *)view stickShaped:(BOOL)stickShaped {
    CustomControl *control = view.control;

    control.bindingKind = CustomBindingKindMouse;
    control.type = stickShaped ? CustomControlTypeStick : CustomControlTypeButton;
    control.icon = nil;

    if (stickShaped) {
        // A nub takes its direction from the drag, so there is nothing to store
        // and sticky cannot apply.
        control.label = nil;
        control.sticky = NO;
        control.sizePt = MAX(control.sizePt, 96.0);
    } else {
        control.label = @"Mouse";
        control.sizePt = MIN(control.sizePt, 72.0);
    }

    _dirty = YES;
    [view refreshFromControl];
    [self layoutControlViews];
}

- (void)applyHideOthersToControlView:(EditorControlView *)view {
    CustomControl *control = view.control;

    control.bindingKind = CustomBindingKindHideOthers;
    control.type = CustomControlTypeButton;
    control.icon = nil;
    control.label = @"Hide";
    // Hide-others is already a toggle, so a sticky flag on top would be rejected.
    control.sticky = NO;

    _dirty = YES;
    [view refreshFromControl];
    [self layoutControlViews];
}

// Size and rate are both continuous, so they use the floating slider rather than
// a list of presets: the value above the track updates as the thumb moves.

- (void)applyShowKeyboardToControlView:(EditorControlView *)view {
    CustomControl *control = view.control;

    control.bindingKind = CustomBindingKindShowKeyboard;
    control.type = CustomControlTypeButton;
    control.icon = nil;
    control.label = @"OSK";
    // It sends nothing, so there is no level for a latch to hold.
    control.sticky = NO;

    _dirty = YES;
    [view refreshFromControl];
    [self layoutControlViews];
}

- (void)showSizeMenuForView:(EditorControlView *)view {
    [self presentSliderPanelWithTitle:@"Size"
                                  min:kEditorMinSizePt
                                  max:kEditorMaxSizePt
                                 step:0.0
                                value:view.control.sizePt
                               format:@"%.0f pt"
                             onChange:^(double value) {
        view.control.sizePt = value;
        self->_dirty = YES;
        [self layoutControlViews];
    }];
}

- (void)showRateMenuForView:(EditorControlView *)view {
    [self presentSliderPanelWithTitle:@"Mouse Rate"
                                  min:kEditorMinMouseRate
                                  max:kEditorMaxMouseRate
                                 step:0.0
                                value:view.control.mouseRate
                               format:@"%.0f pt/s"
                             onChange:^(double value) {
        view.control.mouseRate = value;
        self->_dirty = YES;
    }];
}

// Dead zone as a fraction of the stick radius. Stepped so it lands on the 0.01
// grid, which makes a value easy to read and to reproduce.
- (void)showDeadZoneMenuForView:(EditorControlView *)view {
    [self presentSliderPanelWithTitle:@"Dead Zone"
                                  min:kEditorMinDeadZone
                                  max:kEditorMaxDeadZone
                                 step:kEditorDeadZoneStep
                                value:view.control.deadZone
                               format:@"%.2f"
                             onChange:^(double value) {
        view.control.deadZone = value;
        self->_dirty = YES;
    }];
}

// A button-shaped mouse control has no drag to take a direction from, so it
// needs one stored.
- (void)showMouseDirectionMenuForView:(EditorControlView *)view {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Mouse Direction"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSInteger d = 0; d <= (NSInteger)CustomStickDirectionRight; d++) {
        CustomStickDirection direction = (CustomStickDirection)d;
        NSString *title = [CustomLayoutDocument nameForDirection:direction];
        if (view.control.mouseDirection == direction) {
            title = [title stringByAppendingString:@"  \u2713"];
        }

        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            view.control.mouseDirection = direction;
            self->_dirty = YES;
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentSheet:sheet fromView:view];
}

// ---------------------------------------------------------------------------
// Anchor
// ---------------------------------------------------------------------------

- (NSString *)displayNameForAnchor:(CustomAnchor)anchor {
    switch (anchor) {
        case CustomAnchorTopLeft:     return @"Top Left";
        case CustomAnchorTopRight:    return @"Top Right";
        case CustomAnchorBottomLeft:  return @"Bottom Left";
        case CustomAnchorBottomRight: return @"Bottom Right";
        case CustomAnchorCenter:      return @"Center";
    }
    return @"Center";
}

- (void)showAnchorMenuForView:(EditorControlView *)view {
    UIAlertController *sheet =
        [UIAlertController alertControllerWithTitle:@"Anchor"
                                            message:@"Offsets are measured from this point on the safe area."
                                     preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray<NSNumber *> *anchors = @[ @(CustomAnchorTopLeft),
                                      @(CustomAnchorTopRight),
                                      @(CustomAnchorBottomLeft),
                                      @(CustomAnchorBottomRight),
                                      @(CustomAnchorCenter) ];

    for (NSNumber *value in anchors) {
        CustomAnchor anchor = (CustomAnchor)value.integerValue;
        NSString *title = [self displayNameForAnchor:anchor];
        if (view.control.anchor == anchor) {
            title = [title stringByAppendingString:@"  \u2713"];
        }

        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            [self applyAnchor:anchor toControlView:view];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentSheet:sheet fromView:view];
}

// Changing the anchor keeps the control where it is on screen. The offset is
// re-derived from the centre it is drawn at under the *old* anchor against the
// *new* origin, so the control becomes pinned to a different corner instead of
// jumping there.
- (void)applyAnchor:(CustomAnchor)anchor toControlView:(EditorControlView *)view {
    CustomControl *control = view.control;
    if (control.anchor == anchor) {
        return;
    }

    CGSize size = _canvasView.bounds.size;
    if (size.width <= 0.0 || size.height <= 0.0) {
        return;
    }

    UIEdgeInsets insets = _canvasView.safeAreaInsets;

    CGPoint center = [control renderedCenterInBounds:size safeInsets:insets];

    control.anchor = anchor;

    CGPoint origin = [control anchorOriginInBounds:size safeInsets:insets];
    control.offsetX = (center.x - origin.x) / size.width;
    control.offsetY = (center.y - origin.y) / size.height;

    // Each anchor sits at a different corner of the safe area, so a corner change
    // can put a formerly legal centre outside it. Clamp and re-derive, exactly as
    // dragging does, so the stored offset keeps describing what is drawn.
    CGPoint clamped = [control renderedCenterInBounds:size safeInsets:insets];
    control.offsetX = (clamped.x - origin.x) / size.width;
    control.offsetY = (clamped.y - origin.y) / size.height;

    _dirty = YES;
    [self layoutControlViews];
}

- (void)applyPaletteEntry:(NSDictionary *)entry toControlView:(EditorControlView *)view {
    CustomControl *control = view.control;

    // Snapshot so a rejected rebind leaves the control untouched.
    CustomControlType previousType = control.type;
    CustomBindingKind previousKind = control.bindingKind;
    uint32_t previousFlag = control.buttonFlag;
    BOOL previousLeft = control.bindLeft;

    if (entry[@"button"] != nil) {
        control.type = CustomControlTypeButton;
        control.bindingKind = CustomBindingKindButton;
        control.buttonFlag = [CustomLayoutDocument flagForButtonName:entry[@"button"]];
    } else if (entry[@"stick"] != nil) {
        control.type = CustomControlTypeStick;
        control.bindingKind = CustomBindingKindStick;
        control.bindLeft = [entry[@"stick"] isEqualToString:@"left"];
    } else {
        control.type = CustomControlTypeButton;
        control.bindingKind = CustomBindingKindTrigger;
        control.bindLeft = [entry[@"trigger"] isEqualToString:@"left"];
    }

    for (CustomControl *other in _document.controls) {
        if (other == control) {
            continue;
        }
        if (control.bindingKind != CustomBindingKindButton && [control bindsSameInputAs:other]) {
            control.type = previousType;
            control.bindingKind = previousKind;
            control.buttonFlag = previousFlag;
            control.bindLeft = previousLeft;
            [self showMessage:[NSString stringWithFormat:@"'%@' is already bound to that analog axis.",
                               [self displayTitleForControl:other]]];
            return;
        }
    }

    control.label = entry[@"title"];
    control.icon = entry[@"icon"];
    if (control.type != previousType) {
        // A stick and a button need very different footprints.
        control.sizePt = (control.type == CustomControlTypeStick) ? 120.0 : 56.0;
    }
    if (control.type == CustomControlTypeStick) {
        // Sticky is about being held without a finger; a stick's value is its
        // position, so the flag means nothing and must not linger in the model.
        control.sticky = NO;
    }

    _dirty = YES;
    [view refreshFromControl];
    [self layoutControlViews];
}

- (void)deleteControlView:(EditorControlView *)view {
    NSMutableArray *controls = [_document.controls mutableCopy];
    [controls removeObject:view.control];
    _document.controls = controls;

    if ([_selectedControlId isEqualToString:view.control.controlId]) {
        _selectedControlId = nil;
    }

    _dirty = YES;
    [self rebuildControlViews];
}

// ---------------------------------------------------------------------------
// Special stick directions
// ---------------------------------------------------------------------------

// Directions are digital, so sticks and the analog triggers are excluded from
// what can be mapped onto one.
- (NSArray<NSDictionary *> *)gamepadButtonPalette {
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSDictionary *entry in [self palette]) {
        if (entry[@"button"] != nil) {
            [buttons addObject:entry];
        }
    }
    return buttons;
}

- (void)showDirectionsMenuForView:(EditorControlView *)view {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Directions"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSInteger d = 0; d <= (NSInteger)CustomStickDirectionRight; d++) {
        CustomStickDirection direction = (CustomStickDirection)d;
        CustomDigitalBinding *binding = [view.control bindingForDirection:direction];
        NSString *title = [NSString stringWithFormat:@"%@: %@",
                           [CustomLayoutDocument nameForDirection:direction],
                           [binding displayName]];

        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            [self showDirectionPickerForView:view direction:direction];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentSheet:sheet fromView:view];
}

- (void)showDirectionPickerForView:(EditorControlView *)view direction:(CustomStickDirection)direction {
    NSString *title = [NSString stringWithFormat:@"%@ Direction",
                       [CustomLayoutDocument nameForDirection:direction]];

    [self presentDigitalBindingPickerForTitle:title fromView:view onChoose:^(CustomDigitalBinding *binding) {
        [view.control setBinding:binding forDirection:direction];
        self->_dirty = YES;
        [self layoutControlViews];
    }];
}

// Shared picker for "one digital input": a gamepad button, a keyboard key, or
// nothing at all. Reused for each of a special stick's four directions.
- (void)presentDigitalBindingPickerForTitle:(NSString *)title
                                   fromView:(UIView *)sourceView
                                   onChoose:(void (^)(CustomDigitalBinding *binding))onChoose {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Gamepad Button"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [weakSelf presentGamepadButtonPickerForTitle:title fromView:sourceView onChoose:onChoose];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Keyboard Key\u2026"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [weakSelf presentKeyPickerForTitle:title fromView:sourceView onChoose:onChoose];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Clear"
                                             style:UIAlertActionStyleDestructive
                                           handler:^(UIAlertAction *action) {
        onChoose([CustomDigitalBinding unassigned]);
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [self presentSheet:sheet fromView:sourceView];
}

- (void)presentGamepadButtonPickerForTitle:(NSString *)title
                                  fromView:(UIView *)sourceView
                                  onChoose:(void (^)(CustomDigitalBinding *binding))onChoose {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *entry in [self gamepadButtonPalette]) {
        [sheet addAction:[UIAlertAction actionWithTitle:entry[@"title"]
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            onChoose([CustomDigitalBinding bindingWithButtonFlag:
                      [CustomLayoutDocument flagForButtonName:entry[@"button"]]]);
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentSheet:sheet fromView:sourceView];
}

- (void)presentKeyPickerForTitle:(NSString *)title
                        fromView:(UIView *)sourceView
                        onChoose:(void (^)(CustomDigitalBinding *binding))onChoose {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *category in [CustomLayoutDocument keyCategories]) {
        [sheet addAction:[UIAlertAction actionWithTitle:category
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            [self presentKeyPickerForTitle:title category:category fromView:sourceView onChoose:onChoose];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentSheet:sheet fromView:sourceView];
}

- (void)presentKeyPickerForTitle:(NSString *)title
                        category:(NSString *)category
                        fromView:(UIView *)sourceView
                        onChoose:(void (^)(CustomDigitalBinding *binding))onChoose {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:category
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *name in [CustomLayoutDocument keyNamesInCategory:category]) {
        [sheet addAction:[UIAlertAction actionWithTitle:name
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            onChoose([CustomDigitalBinding bindingWithKeyCode:[CustomLayoutDocument keyCodeForName:name]]);
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentSheet:sheet fromView:sourceView];
}

// ---------------------------------------------------------------------------
// Save and exit
// ---------------------------------------------------------------------------

- (void)saveTapped {
    if (_document == nil) {
        // Never write back a document we failed to decode: that would erase the
        // stored layout.
        [self showMessage:@"This layout could not be read and cannot be saved."];
        return;
    }

    NSError *error = nil;
    if (![_document validate:&error]) {
        [self showMessage:error.localizedDescription];
        return;
    }

    _layout.document = _document;
    _layout.name = _document.name;
    [[[DataManager alloc] init] updateCustomLayout:_layout];

    _dirty = NO;
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)exitTapped {
    if (!_dirty) {
        [self dismissViewControllerAnimated:YES completion:nil];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Discard changes?"
                                                                  message:@"The layout has unsaved edits."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Keep Editing" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Discard"
                                             style:UIAlertActionStyleDestructive
                                           handler:^(UIAlertAction *action) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

- (void)presentSheet:(UIAlertController *)sheet fromView:(UIView *)view {
    // Required on iPad, otherwise presenting an action sheet throws.
    sheet.popoverPresentationController.sourceView = view;
    sheet.popoverPresentationController.sourceRect = view.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
