//
//  DataManager.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/28/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "AppDelegate.h"
#import "TemporaryHost.h"
#import "TemporaryApp.h"
#import "TemporarySettings.h"
#import "TemporaryCustomLayout.h"

@interface DataManager : NSObject

- (void) saveSettingsWithBitrate:(NSInteger)bitrate
                       framerate:(NSInteger)framerate
                          height:(NSInteger)height
                           width:(NSInteger)width
                audioConfig:(NSInteger)audioConfig
                onscreenControls:(NSInteger)onscreenControls
                   optimizeGames:(BOOL)optimizeGames
                 multiController:(BOOL)multiController
                 swapABXYButtons:(BOOL)swapABXYButtons
                       audioOnPC:(BOOL)audioOnPC
                  preferredCodec:(uint32_t)preferredCodec
                  useFramePacing:(BOOL)useFramePacing
                       enableHdr:(BOOL)enableHdr
                  btMouseSupport:(BOOL)btMouseSupport
               absoluteTouchMode:(BOOL)absoluteTouchMode
                    statsOverlay:(BOOL)statsOverlay
                    bufferFrames:(NSInteger)bufferFrames
           customOverlayEnabled:(BOOL)customOverlayEnabled
                  multitouchMode:(BOOL)multitouchMode;

- (NSArray*) getHosts;
- (void) updateHost:(TemporaryHost*)host;
- (void) updateAppsForExistingHost:(TemporaryHost *)host;
- (void) removeHost:(TemporaryHost*)host;
- (void) removeApp:(TemporaryApp*)app;

- (TemporarySettings*) getSettings;

- (void) updateUniqueId:(NSString*)uniqueId;
- (NSString*) getUniqueId;

#pragma mark - Custom overlay layouts

// All layouts, ordered by sortOrder.
- (NSArray<TemporaryCustomLayout*>*) getCustomLayouts;

// The layout named by Settings.activeLayoutId, or nil if none is set or the
// referenced row no longer exists.
- (TemporaryCustomLayout*) getActiveCustomLayout;

// YES only when the overlay is enabled, the on-screen control presets are not
// in effect, and the active layout has something to draw. This is the single
// predicate shared by ControllerSupport (virtual gamepad presence) and the
// stream view (whether to build the overlay).
- (BOOL) isCustomOverlayActive;

// Inserts a new row at the end of the order. A missing layoutId is assigned.
- (void) addCustomLayout:(TemporaryCustomLayout*)layout;

- (void) updateCustomLayout:(TemporaryCustomLayout*)layout;

// Deleting the active layout also clears activeLayoutId, otherwise the runtime
// would keep resolving a row that no longer exists.
- (void) removeCustomLayout:(TemporaryCustomLayout*)layout;

// nil clears the selection, which makes the overlay inert.
- (void) activateCustomLayout:(NSString*)layoutId;

@end
