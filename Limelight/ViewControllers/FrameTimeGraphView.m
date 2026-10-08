//
//  FrameTimeGraphView.m
//  Moonlight
//

#import "FrameTimeGraphView.h"

#include <float.h>

// The trace is drawn with CAShapeLayer instead of drawRect: so a 20 Hz refresh
// only rebuilds a path (GPU composited). Implicit layer animations must be
// disabled or the path would animate behind the data.
#define KM_PLOT_INSET_TOP     2.0
#define KM_PLOT_INSET_BOTTOM  2.0
#define KM_PLOT_INSET_RIGHT   3.0
#define KM_GUTTER_PADDING     4.0

static UIColor *KMGraphLineColor(void) {
    return [UIColor colorWithRed:0.30 green:0.90 blue:0.46 alpha:1.0];
}

static UIColor *KMMeanLineColor(void) {
    return [UIColor colorWithWhite:1.0 alpha:0.55];
}

static UIColor *KMBudgetLineColor(void) {
    return [UIColor colorWithRed:1.0 green:0.62 blue:0.20 alpha:0.9];
}

// Note on the Y axis: the half range is kept continuous on purpose. Snapping it
// to a coarse ladder after each decay step would trap the axis, because ceil()
// pulls the value back up to the step it is trying to leave, so the range would
// never contract. Label width is cached instead (see setAxisLabel:).

@interface FrameTimeGraphView ()

- (void)commonInit;
- (UILabel *)newAxisLabelWithFont:(UIFont *)font;
- (CGRect)plotRectForBounds:(CGRect)bounds;
- (void)updateGutterWidth;
- (void)applyGeometry;
- (BOOL)setAxisLabel:(UILabel *)label text:(NSString *)text;
- (void)clearPaths;

@end

@implementation FrameTimeGraphView {
    CAShapeLayer *_traceLayer;
    CAShapeLayer *_meanLayer;
    CAShapeLayer *_budgetLayer;

    UILabel *_topLabel;
    UILabel *_midLabel;
    UILabel *_bottomLabel;
    UILabel *_idleLabel;

    CGFloat _gutterWidth;
    CGRect _lastPlotRect;

    // Y axis state, persisted across refreshes so the range can expand fast and
    // contract slowly.
    double _halfRangeMs;
    double _meanMs;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    _windowSeconds = 1.0;
    _minimumHalfRangeMs = 1.0;
    _budgetMs = 16.67;
    _halfRangeMs = _minimumHalfRangeMs;
    _meanMs = 0;
    _gutterWidth = 0;
    _lastPlotRect = CGRectZero;

    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = NO;
    self.clipsToBounds = YES;

    _traceLayer = [CAShapeLayer layer];
    _traceLayer.fillColor = nil;
    _traceLayer.lineJoin = kCALineJoinRound;
    _traceLayer.lineCap = kCALineCapRound;
    _traceLayer.strokeColor = KMGraphLineColor().CGColor;
    [self.layer addSublayer:_traceLayer];

    _meanLayer = [CAShapeLayer layer];
    _meanLayer.fillColor = nil;
    _meanLayer.lineDashPattern = @[@2, @3];
    _meanLayer.strokeColor = KMMeanLineColor().CGColor;
    [self.layer addSublayer:_meanLayer];

    _budgetLayer = [CAShapeLayer layer];
    _budgetLayer.fillColor = nil;
    _budgetLayer.lineDashPattern = @[@3, @3];
    _budgetLayer.strokeColor = KMBudgetLineColor().CGColor;
    [self.layer addSublayer:_budgetLayer];

#if TARGET_OS_TV
    CGFloat fontSize = 18.0;
    CGFloat lineWidth = 2.0;
#else
    CGFloat fontSize = 9.0;
    CGFloat lineWidth = 1.0;
#endif
    _traceLayer.lineWidth = lineWidth;
    _meanLayer.lineWidth = lineWidth;
    _budgetLayer.lineWidth = lineWidth;

    UIFont *labelFont = [UIFont monospacedDigitSystemFontOfSize:fontSize weight:UIFontWeightRegular];

    _topLabel = [self newAxisLabelWithFont:labelFont];
    _midLabel = [self newAxisLabelWithFont:labelFont];
    _bottomLabel = [self newAxisLabelWithFont:labelFont];

    _idleLabel = [[UILabel alloc] init];
    _idleLabel.font = labelFont;
    _idleLabel.textColor = [UIColor lightGrayColor];
    _idleLabel.textAlignment = NSTextAlignmentCenter;
    _idleLabel.text = @"waiting for frames";
    [self addSubview:_idleLabel];

    [self clear];
}

- (UILabel *)newAxisLabelWithFont:(UIFont *)font {
    UILabel *label = [[UILabel alloc] init];
    label.font = font;
    label.textColor = [UIColor lightGrayColor];
    label.textAlignment = NSTextAlignmentRight;
    label.text = @"";
    [self addSubview:label];
    return label;
}

#pragma mark - Geometry

- (CGRect)plotRectForBounds:(CGRect)bounds {
    CGFloat gutter = _gutterWidth;
    CGFloat width = bounds.size.width - gutter - KM_PLOT_INSET_RIGHT;
    CGFloat height = bounds.size.height - KM_PLOT_INSET_TOP - KM_PLOT_INSET_BOTTOM;
    if (width < 1.0 || height < 1.0) {
        return CGRectZero;
    }
    return CGRectMake(gutter, KM_PLOT_INSET_TOP, width, height);
}

- (void)layoutSubviews {
    [super layoutSubviews];

    [self updateGutterWidth];
    [self applyGeometry];

    CGRect plot = [self plotRectForBounds:self.bounds];
    if (!CGRectEqualToRect(_lastPlotRect, plot)) {
        _lastPlotRect = plot;
        // Bounds changed (rotation): the cached paths are in the old coordinate
        // space. Drop them; the next update rebuilds them.
        [self clearPaths];
    }
}

// The left gutter has to fit whatever the axis labels currently say.
- (void)updateGutterWidth {
    CGFloat gutter = 0;
    for (UILabel *label in @[_topLabel, _midLabel, _bottomLabel]) {
        CGSize size = [label sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
        gutter = MAX(gutter, ceil(size.width));
    }
    _gutterWidth = gutter + KM_GUTTER_PADDING;
}

- (void)applyGeometry {
    CGRect plot = [self plotRectForBounds:self.bounds];
    if (CGRectIsEmpty(plot)) {
        return;
    }

    CGFloat labelHeight = ceil(_midLabel.font.lineHeight);
    CGFloat gutter = _gutterWidth;

    _topLabel.frame = CGRectMake(0, plot.origin.y, gutter - KM_GUTTER_PADDING, labelHeight);
    _midLabel.frame = CGRectMake(0, CGRectGetMidY(plot) - labelHeight / 2.0, gutter - KM_GUTTER_PADDING, labelHeight);
    _bottomLabel.frame = CGRectMake(0, CGRectGetMaxY(plot) - labelHeight, gutter - KM_GUTTER_PADDING, labelHeight);
    _idleLabel.frame = CGRectMake(plot.origin.x, CGRectGetMidY(plot) - labelHeight / 2.0, plot.size.width, labelHeight);

    // Shape layer paths live in the view's coordinate space.
    for (CAShapeLayer *layer in @[_traceLayer, _meanLayer, _budgetLayer]) {
        layer.frame = self.bounds;
    }
}

#pragma mark - Data

- (void)updateWithSamples:(const FrameSample *)samples count:(NSUInteger)count now:(double)now {
    if (samples == NULL || count == 0) {
        [self clear];
        return;
    }

    double sum = 0;
    double minMs = DBL_MAX;
    double maxMs = 0;
    for (NSUInteger i = 0; i < count; i++) {
        double ms = samples[i].totalUs / 1000.0;
        sum += ms;
        if (ms < minMs) {
            minMs = ms;
        }
        if (ms > maxMs) {
            maxMs = ms;
        }
    }
    _meanMs = sum / (double)count;

    // Centre the axis on the mean: expand instantly when a spike needs room,
    // contract continuously so the trace does not jump around while the window
    // slides.
    double halfTarget = MAX(MAX(_meanMs - minMs, maxMs - _meanMs), self.minimumHalfRangeMs);
    if (halfTarget > _halfRangeMs) {
        _halfRangeMs = halfTarget;
    } else {
        _halfRangeMs = _halfRangeMs * 0.85 + halfTarget * 0.15;
    }
    _halfRangeMs = MAX(_halfRangeMs, self.minimumHalfRangeMs);

    // Axis labels first: the gutter has to fit them before the plot rect (and
    // therefore the trace) can be laid out. Only re-measure when a label
    // actually changed, since sizeThatFits: runs CoreText.
    NSString *format = _halfRangeMs < 10.0 ? @"%.1f" : @"%.0f";
    BOOL changedTop = [self setAxisLabel:_topLabel text:[NSString stringWithFormat:format, _meanMs + _halfRangeMs]];
    BOOL changedMid = [self setAxisLabel:_midLabel text:[NSString stringWithFormat:format, _meanMs]];
    BOOL changedBottom = [self setAxisLabel:_bottomLabel text:[NSString stringWithFormat:format, MAX(_meanMs - _halfRangeMs, 0.0)]];

    // Updates can arrive before the first layout pass, in which case the gutter
    // is still unknown and the labels would overlap the trace.
    if (changedTop || changedMid || changedBottom || _gutterWidth <= 0) {
        [self updateGutterWidth];
    }
    [self applyGeometry];

    CGRect plot = [self plotRectForBounds:self.bounds];
    if (CGRectIsEmpty(plot)) {
        return;
    }

    double window = MAX(self.windowSeconds, 0.05);
    double windowStart = now - window;
    double centerY = CGRectGetMidY(plot);
    double scale = (plot.size.height * 0.5) / _halfRangeMs;

    CGMutablePathRef trace = CGPathCreateMutable();
    NSUInteger pointCount = 0;
    CGFloat lastX = 0, lastY = 0;

    for (NSUInteger i = 0; i < count; i++) {
        if (samples[i].t < windowStart || samples[i].t > now) {
            continue;
        }
        double u = (samples[i].t - windowStart) / window;
        u = MIN(MAX(u, 0.0), 1.0);
        CGFloat x = plot.origin.x + u * plot.size.width;
        CGFloat y = centerY - (samples[i].totalUs / 1000.0 - _meanMs) * scale;
        y = MIN(MAX(y, CGRectGetMinY(plot)), CGRectGetMaxY(plot));

        if (pointCount == 0) {
            CGPathMoveToPoint(trace, NULL, x, y);
        } else {
            CGPathAddLineToPoint(trace, NULL, x, y);
        }
        lastX = x;
        lastY = y;
        pointCount++;
    }

    if (pointCount == 1) {
        // A single point has no segment to stroke; give it width so the first
        // refresh right after the stream starts is not blank.
        CGPathAddLineToPoint(trace, NULL, lastX + 0.5, lastY);
    }

    CGMutablePathRef mean = CGPathCreateMutable();
    CGPathMoveToPoint(mean, NULL, plot.origin.x, centerY);
    CGPathAddLineToPoint(mean, NULL, CGRectGetMaxX(plot), centerY);

    CGMutablePathRef budget = CGPathCreateMutable();
    CGFloat budgetY = centerY - (self.budgetMs - _meanMs) * scale;
    if (budgetY >= CGRectGetMinY(plot) && budgetY <= CGRectGetMaxY(plot)) {
        CGPathMoveToPoint(budget, NULL, plot.origin.x, budgetY);
        CGPathAddLineToPoint(budget, NULL, CGRectGetMaxX(plot), budgetY);
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _traceLayer.path = trace;
    _meanLayer.path = mean;
    _budgetLayer.path = budget;
    [CATransaction commit];
    CGPathRelease(trace);
    CGPathRelease(mean);
    CGPathRelease(budget);

    _traceLayer.hidden = NO;
    _meanLayer.hidden = NO;
    _budgetLayer.hidden = NO;
    _idleLabel.hidden = YES;
}

// Returns YES when the label width may have changed. The font uses monospaced
// digits, so only the character count matters: re-measuring with sizeThatFits:
// on every 20 Hz tick would run CoreText for nothing.
- (BOOL)setAxisLabel:(UILabel *)label text:(NSString *)text {
    if ([label.text isEqualToString:text]) {
        return NO;
    }
    NSUInteger oldLength = label.text.length;
    label.text = text;
    return oldLength != text.length;
}

- (void)clearPaths {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _traceLayer.path = NULL;
    _meanLayer.path = NULL;
    _budgetLayer.path = NULL;
    [CATransaction commit];
}

- (void)clear {
    _halfRangeMs = self.minimumHalfRangeMs;
    _meanMs = 0;
    [self clearPaths];
    _traceLayer.hidden = YES;
    _meanLayer.hidden = YES;
    _budgetLayer.hidden = YES;
    _idleLabel.hidden = NO;
    
    // Stale numbers next to an empty plot would be misleading.
    [self setAxisLabel:_topLabel text:@""];
    [self setAxisLabel:_midLabel text:@""];
    [self setAxisLabel:_bottomLabel text:@""];
    [self updateGutterWidth];
    [self applyGeometry];
}

@end
