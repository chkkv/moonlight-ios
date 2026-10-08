//
//  FrameStatsRecorder.h
//  Moonlight
//
//  Rolling per-frame submission timing probes used by the stats overlay graph.
//
//  There are two probes per frame because the work is split across two files:
//
//    prepareUs  Connection.m  - decode unit malloc, parameter set submission and
//                               the full-frame memcpy into the contiguous buffer.
//    enqueueUs  VideoDecoderRenderer.m - format description rebuild (IDR only),
//                               CMBlockBuffer assembly and enqueueSampleBuffer:.
//    totalUs    VideoDecoderRenderer.m - wall clock around the whole
//                               DrSubmitDecodeUnit() call.
//
//  This measures the CPU cost of getting a frame onto the display layer. It is
//  NOT the GPU draw time: AVSampleBufferDisplayLayer does not expose GPU
//  timestamps, and this path includes a full-frame memcpy.
//

#import <Foundation/Foundation.h>

// ~2 seconds of headroom at 120 FPS.
#define FRAME_STATS_CAPACITY 256

typedef struct {
    uint32_t prepareUs;
    uint32_t enqueueUs;
    uint32_t totalUs;
} FrameTiming;

typedef struct {
    double   t;          // CACurrentMediaTime() when this frame's submit started
    uint32_t totalUs;
    uint32_t prepareUs;
    uint32_t enqueueUs;
} FrameSample;

typedef struct {
    uint32_t count;         // frames inside the window
    double   span;          // newest.t - oldest.t
    double   fps;           // submit rate derived from the frame timestamps
    uint32_t totalAvgUs;
    uint32_t totalMaxUs;
    uint32_t totalP99Us;
    uint32_t prepareAvgUs;
    uint32_t enqueueAvgUs;
} FrameWindowStats;

@interface FrameStatsRecorder : NSObject

// Called once per submitted frame. Keep this cheap: it is on the main thread
// inside the CADisplayLink callback, so it holds a lock only long enough to
// store one struct.
- (void)recordTiming:(FrameTiming)timing atTime:(double)t;

// Called when a new stream starts.
- (void)reset;

// Copies the samples inside [now - window, now] into out, oldest first.
// Returns the number of samples written (never more than maxCount).
- (NSUInteger)copySamplesInto:(FrameSample *)out maxCount:(NSUInteger)maxCount now:(double)now window:(double)window;

// Aggregates the same window. FPS is derived from the timestamps of the first
// and last sample, so a stalled stream decays to 0 instead of freezing on the
// last good value.
- (FrameWindowStats)statsAtTime:(double)now window:(double)window;

@end
