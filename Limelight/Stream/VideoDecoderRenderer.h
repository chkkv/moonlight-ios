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

- (id)initWithView:(UIView*)view callbacks:(id<ConnectionCallbacks>)callbacks streamAspectRatio:(float)aspectRatio useFramePacing:(BOOL)useFramePacing;

- (void)setupWithVideoFormat:(int)videoFormat width:(int)videoWidth height:(int)videoHeight frameRate:(int)frameRate;
- (void)start;
- (void)stop;
- (void)setHdrMode:(BOOL)enabled;

- (int)submitDecodeBuffer:(unsigned char *)data length:(int)length bufferType:(int)bufferType decodeUnit:(PDECODE_UNIT)du;

@end
