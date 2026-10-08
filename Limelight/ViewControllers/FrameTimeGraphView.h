//
//  FrameTimeGraphView.h
//  Moonlight
//
//  Scrolling per-frame submission time graph for the stats overlay.
//
//  X axis is a fixed 1 second window that scrolls under the cursor (the right
//  edge is always "now"). The Y axis is dynamic and always centred on the mean
//  of the window, so the mean line is a straight horizontal line through the
//  middle of the plot by construction.
//

#import <UIKit/UIKit.h>

#import "FrameStatsRecorder.h"

@interface FrameTimeGraphView : UIView

// Width of the scrolling time window in seconds. Default 1.0.
@property (nonatomic) double windowSeconds;

// Minimum half-range of the Y axis in ms. Keeps a flat trace from being
// amplified into full scale noise. Default 1.0.
@property (nonatomic) double minimumHalfRangeMs;

// Reference line for the per-frame budget (1000 / stream fps). Default 16.67.
@property (nonatomic) double budgetMs;

- (void)updateWithSamples:(const FrameSample *)samples count:(NSUInteger)count now:(double)now;

// Hides the trace and shows the idle placeholder.
- (void)clear;

@end
