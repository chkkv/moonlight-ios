//
//  VideoDecoderRenderer.h
//  Moonlight
//
//  Created by Cameron Gutman on 10/18/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

@import AVFoundation;

#import "ConnectionCallbacks.h"
#import "FrameStatsRecorder.h"

#include "Limelight.h"

@interface VideoDecoderRenderer : NSObject

// Rolling per-frame submission timing for the stats overlay graph. Written on
// the main thread from displayLinkCallback:.
@property (nonatomic, strong, readonly) FrameStatsRecorder *frameStats;

// Playout buffer depth in frames. 0 (default) keeps the original lowest latency
// behaviour, submitting each frame as soon as it arrives. A value > 0 holds
// frames for that many frame periods before submitting them, so a network gap
// (Wi-Fi off-channel scan, roaming, ...) does not stall the display right away.
// The cost is that same amount of added input latency, and audio is delayed by
// the matching time so A/V stay in sync.
@property (nonatomic) int bufferFrames;

// Frames currently buffered, and the depth at which the renderer starts
// dropping to catch up. For the stats overlay.
- (int)pendingBufferedFrames;
- (int)bufferCapacity;

- (id)initWithView:(UIView*)view callbacks:(id<ConnectionCallbacks>)callbacks streamAspectRatio:(float)aspectRatio useFramePacing:(BOOL)useFramePacing;

- (void)setupWithVideoFormat:(int)videoFormat width:(int)videoWidth height:(int)videoHeight frameRate:(int)frameRate;
- (void)start;
- (void)stop;
- (void)setHdrMode:(BOOL)enabled;

- (int)submitDecodeBuffer:(unsigned char *)data length:(int)length bufferType:(int)bufferType decodeUnit:(PDECODE_UNIT)du;

@end
