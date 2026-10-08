//
//  Connection.h
//  Moonlight
//
//  Created by Diego Waxemberg on 1/19/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "VideoDecoderRenderer.h"
#import "StreamConfiguration.h"

#define CONN_TEST_SERVER "ios.conntest.moonlight-stream.org"

typedef struct {
    CFTimeInterval startTime;
    CFTimeInterval endTime;
    int totalFrames;
    int receivedFrames;
    int networkDroppedFrames;
    int totalHostProcessingLatency;
    int framesWithHostProcessingLatency;
    int maxHostProcessingLatency;
    int minHostProcessingLatency;
} video_stats_t;

// Session-lifetime diagnostic counters (not reset by the 1-second stats window)
typedef struct {
    // Frames whose submission went backwards relative to the previous frame:
    // either the frame number regressed/duplicated (queue reordering) or the
    // presentation timestamp was not monotonic (the display layer drops those
    // as late frames). Should stay 0 in normal operation.
    uint32_t frameOrderErrors;

    // Recovery frames submitted after the reference frame chain broke (network
    // frame drop or decoder reset). The first frame submitted after such a
    // discontinuity may carry picture content derived from an older reference
    // frame than the previously displayed one. An IDR recovery frame does not
    // count, since it establishes a brand new reference.
    uint32_t contentRegressionFrames;
} stream_error_stats_t;

@interface Connection : NSOperation <NSStreamDelegate>

-(id) initWithConfig:(StreamConfiguration*)config renderer:(VideoDecoderRenderer*)myRenderer connectionCallbacks:(id<ConnectionCallbacks>)callbacks;
-(void) terminate;
-(void) main;
-(BOOL) getVideoStats:(video_stats_t*)stats;
-(void) getStreamErrorStats:(stream_error_stats_t*)stats;
-(NSString*) getActiveCodecName;

@end
