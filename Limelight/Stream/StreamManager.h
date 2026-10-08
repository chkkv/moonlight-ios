//
//  StreamManager.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "StreamConfiguration.h"
#import "Connection.h"

@class FrameStatsRecorder;

@interface StreamManager : NSOperation

- (id) initWithConfig:(StreamConfiguration*)config renderView:(UIView*)view connectionCallbacks:(id<ConnectionCallbacks>)callback;

- (void) stopStream;

- (NSString*) getStatsOverlayText;

// Rolling per-frame submission timing of the active renderer. nil until the
// stream has been set up.
@property (nonatomic, strong, readonly) FrameStatsRecorder *frameStats;

@end
