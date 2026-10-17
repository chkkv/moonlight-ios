//
//  TemporarySettings.h
//  Moonlight
//
//  Created by Cameron Gutman on 12/1/15.
//  Copyright © 2015 Moonlight Stream. All rights reserved.
//

#import "Settings+CoreDataClass.h"

@interface TemporarySettings : NSObject

@property (nonatomic, retain) Settings * parent;

@property (nonatomic, retain) NSNumber * bitrate;
@property (nonatomic, retain) NSNumber * framerate;
@property (nonatomic, retain) NSNumber * height;
@property (nonatomic, retain) NSNumber * width;
@property (nonatomic, retain) NSNumber * audioConfig;
@property (nonatomic, retain) NSNumber * onscreenControls;
@property (nonatomic, retain) NSString * uniqueId;
@property (nonatomic) enum {
    CODEC_PREF_AUTO,
    CODEC_PREF_H264,
    CODEC_PREF_HEVC,
    CODEC_PREF_AV1,
} preferredCodec;
@property (nonatomic) BOOL useFramePacing;
@property (nonatomic) BOOL multiController;
@property (nonatomic) BOOL swapABXYButtons;
@property (nonatomic) BOOL playAudioOnPC;
@property (nonatomic) BOOL optimizeGames;
@property (nonatomic) BOOL enableHdr;
@property (nonatomic) BOOL btMouseSupport;
@property (nonatomic) BOOL absoluteTouchMode;
@property (nonatomic) BOOL statsOverlay;

// Playout buffer depth in frames for the renderer's frame hold. 0 is the
// original lowest-latency behaviour (drain the queue down to 1 frame).
@property (nonatomic) NSInteger bufferFrames;

// Whether the user-authored custom control overlay is turned on. The overlay
// and the on-screen control presets are mutually exclusive: when the presets
// are enabled (onscreenControls != Off) the overlay is inert.
@property (nonatomic) BOOL customOverlayEnabled;

// Touchscreen mode only: forward real multi-touch touches to the host instead of
// emulating an absolute mouse. The two are mutually exclusive, and this setting is
// what chooses between them. It needs a host that advertises
// LI_FF_PEN_TOUCH_EVENTS (Sunshine); touch events are not part of GFE's protocol.
@property (nonatomic) BOOL multitouchMode;

// Whether the host list is always shown on launch instead of going straight into
// the only saved host. A launch preference rather than a stream parameter, so it
// lives in NSUserDefaults instead of the CoreData Settings entity and needs no
// model version change. Declared here so the settings screen and the main screen
// cannot drift apart on the key; the tvOS settings bundle spells the same key out
// in Root.plist, which cannot reference a constant.
extern NSString * const AlwaysShowHostListKey;

- (id) initFromSettings:(Settings*)settings;

@end
