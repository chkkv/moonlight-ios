//
//  DataManager.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/28/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "DataManager.h"
#import "TemporaryApp.h"
#import "TemporarySettings.h"
#import "OnScreenControls.h"

@implementation DataManager {
    NSManagedObjectContext *_managedObjectContext;
    AppDelegate *_appDelegate;
}

- (id) init {
    self = [super init];
    
    // HACK: Avoid calling [UIApplication delegate] off the UI thread to keep
    // Main Thread Checker happy.
    if ([NSThread isMainThread]) {
        _appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
    }
    else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            self->_appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
        });
    }
    
    _managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    [_managedObjectContext setParentContext:[_appDelegate managedObjectContext]];
    
    return self;
}

- (void) updateUniqueId:(NSString*)uniqueId {
    [_managedObjectContext performBlockAndWait:^{
        [self retrieveSettings].uniqueId = uniqueId;
        [self saveData];
    }];
}

- (NSString*) getUniqueId {
    __block NSString *uid;
    
    [_managedObjectContext performBlockAndWait:^{
        uid = [self retrieveSettings].uniqueId;
    }];

    return uid;
}

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
                  multitouchMode:(BOOL)multitouchMode {
    
    [_managedObjectContext performBlockAndWait:^{
        Settings* settingsToSave = [self retrieveSettings];
        settingsToSave.framerate = [NSNumber numberWithInteger:framerate];
        settingsToSave.bitrate = [NSNumber numberWithInteger:bitrate];
        settingsToSave.height = [NSNumber numberWithInteger:height];
        settingsToSave.width = [NSNumber numberWithInteger:width];
        settingsToSave.audioConfig = [NSNumber numberWithInteger:audioConfig];
        settingsToSave.onscreenControls = [NSNumber numberWithInteger:onscreenControls];
        settingsToSave.optimizeGames = optimizeGames;
        settingsToSave.multiController = multiController;
        settingsToSave.swapABXYButtons = swapABXYButtons;
        settingsToSave.playAudioOnPC = audioOnPC;
        settingsToSave.preferredCodec = preferredCodec;
        settingsToSave.useFramePacing = useFramePacing;
        settingsToSave.enableHdr = enableHdr;
        settingsToSave.btMouseSupport = btMouseSupport;
        settingsToSave.absoluteTouchMode = absoluteTouchMode;
        settingsToSave.statsOverlay = statsOverlay;
        settingsToSave.bufferFrames = (int16_t)bufferFrames;
        settingsToSave.customOverlayEnabled = customOverlayEnabled;
        settingsToSave.multitouchMode = multitouchMode;
        
        [self saveData];
    }];
}

- (void) updateHost:(TemporaryHost *)host {
    [_managedObjectContext performBlockAndWait:^{
        // Add a new persistent managed object if one doesn't exist
        Host* parent = [self getHostForTemporaryHost:host withHostRecords:[self fetchRecords:@"Host"]];
        if (parent == nil) {
            NSEntityDescription* entity = [NSEntityDescription entityForName:@"Host" inManagedObjectContext:self->_managedObjectContext];
            parent = [[Host alloc] initWithEntity:entity insertIntoManagedObjectContext:self->_managedObjectContext];
        }
        
        // Push changes from the temp host to the persistent one
        [host propagateChangesToParent:parent];
        
        [self saveData];
    }];
}

- (void) updateAppsForExistingHost:(TemporaryHost *)host {
    [_managedObjectContext performBlockAndWait:^{
        Host* parent = [self getHostForTemporaryHost:host withHostRecords:[self fetchRecords:@"Host"]];
        if (parent == nil) {
            // The host must exist to be updated
            return;
        }
        
        NSMutableSet *applist = [[NSMutableSet alloc] init];
        NSArray *appRecords = [self fetchRecords:@"App"];
        for (TemporaryApp* app in host.appList) {
            // Add a new persistent managed object if one doesn't exist
            App* parentApp = [self getAppForTemporaryApp:app withAppRecords:appRecords];
            if (parentApp == nil) {
                NSEntityDescription* entity = [NSEntityDescription entityForName:@"App" inManagedObjectContext:self->_managedObjectContext];
                parentApp = [[App alloc] initWithEntity:entity insertIntoManagedObjectContext:self->_managedObjectContext];
            }
            
            [app propagateChangesToParent:parentApp withHost:parent];
            
            [applist addObject:parentApp];
        }
        
        parent.appList = applist;
        
        [self saveData];
    }];
}

- (TemporarySettings*) getSettings {
    __block TemporarySettings *tempSettings;
    
    [_managedObjectContext performBlockAndWait:^{
        tempSettings = [[TemporarySettings alloc] initFromSettings:[self retrieveSettings]];
    }];
    
    return tempSettings;
}

- (Settings*) retrieveSettings {
    NSArray* fetchedRecords = [self fetchRecords:@"Settings"];
    if (fetchedRecords.count == 0) {
        // create a new settings object with the default values
        NSEntityDescription* entity = [NSEntityDescription entityForName:@"Settings" inManagedObjectContext:_managedObjectContext];
        Settings* settings = [[Settings alloc] initWithEntity:entity insertIntoManagedObjectContext:_managedObjectContext];
        
        return settings;
    } else {
        // we should only ever have 1 settings object stored
        return [fetchedRecords objectAtIndex:0];
    }
}

- (void) removeApp:(TemporaryApp*)app {
    [_managedObjectContext performBlockAndWait:^{
        App* managedApp = [self getAppForTemporaryApp:app withAppRecords:[self fetchRecords:@"App"]];
        if (managedApp != nil) {
            [self->_managedObjectContext deleteObject:managedApp];
            [self saveData];
        }
    }];
}

- (void) removeHost:(TemporaryHost*)host {
    [_managedObjectContext performBlockAndWait:^{
        Host* managedHost = [self getHostForTemporaryHost:host withHostRecords:[self fetchRecords:@"Host"]];
        if (managedHost != nil) {
            [self->_managedObjectContext deleteObject:managedHost];
            [self saveData];
        }
    }];
}

- (void) saveData {
    NSError* error;
    if ([_managedObjectContext hasChanges] && ![_managedObjectContext save:&error]) {
        Log(LOG_E, @"Unable to save hosts to database: %@", error);
    }

    [_appDelegate saveContext];
}

- (NSArray*) getHosts {
    __block NSMutableArray *tempHosts = [[NSMutableArray alloc] init];
    
    [_managedObjectContext performBlockAndWait:^{
        NSArray *hosts = [self fetchRecords:@"Host"];
        
        for (Host* host in hosts) {
            [tempHosts addObject:[[TemporaryHost alloc] initFromHost:host]];
        }
    }];
    
    return tempHosts;
}

// Only call from within performBlockAndWait!!!
- (Host*) getHostForTemporaryHost:(TemporaryHost*)tempHost withHostRecords:(NSArray*)hosts {
    for (Host* host in hosts) {
        if ([tempHost.uuid isEqualToString:host.uuid]) {
            return host;
        }
    }
    
    return nil;
}

// Only call from within performBlockAndWait!!!
- (App*) getAppForTemporaryApp:(TemporaryApp*)tempApp withAppRecords:(NSArray*)apps {
    for (App* app in apps) {
        if ([app.id isEqualToString:tempApp.id] &&
            [app.host.uuid isEqualToString:tempApp.host.uuid]) {
            return app;
        }
    }
    
    return nil;
}

- (NSArray*) fetchRecords:(NSString*)entityName {
    NSArray* fetchedRecords;
    
    NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription* entity = [NSEntityDescription entityForName:entityName inManagedObjectContext:_managedObjectContext];
    [fetchRequest setEntity:entity];
    
    NSError* error;
    fetchedRecords = [_managedObjectContext executeFetchRequest:fetchRequest error:&error];
    //TODO: handle errors
    
    return fetchedRecords;
}

#pragma mark - Custom overlay layouts

// Only call from within performBlockAndWait!!!
- (CustomLayout*) getCustomLayoutForTemporaryLayout:(TemporaryCustomLayout*)tempLayout
                                withLayoutRecords:(NSArray*)layouts {
    for (CustomLayout* layout in layouts) {
        if (tempLayout.layoutId != nil && [layout.id isEqualToString:tempLayout.layoutId]) {
            return layout;
        }
    }
    
    return nil;
}

- (NSArray<TemporaryCustomLayout*>*) getCustomLayouts {
    __block NSMutableArray *tempLayouts = [[NSMutableArray alloc] init];
    
    [_managedObjectContext performBlockAndWait:^{
        for (CustomLayout* layout in [self fetchRecords:@"CustomLayout"]) {
            [tempLayouts addObject:[[TemporaryCustomLayout alloc] initFromCustomLayout:layout]];
        }
    }];
    
    [tempLayouts sortUsingSelector:@selector(compareSortOrder:)];
    
    return tempLayouts;
}

- (TemporaryCustomLayout*) getActiveCustomLayout {
    __block NSString *activeLayoutId = nil;
    
    // Reads the raw managed object rather than getSettings so this cannot
    // recurse through TemporarySettings while settings are being constructed.
    [_managedObjectContext performBlockAndWait:^{
        activeLayoutId = [self retrieveSettings].activeLayoutId;
    }];
    
    if (activeLayoutId.length == 0) {
        return nil;
    }
    
    for (TemporaryCustomLayout* layout in [self getCustomLayouts]) {
        if ([layout.layoutId isEqualToString:activeLayoutId]) {
            return layout;
        }
    }
    
    return nil;
}

- (BOOL) isCustomOverlayActive {
    TemporarySettings* settings = [self getSettings];
    if (!settings.customOverlayEnabled) {
        return NO;
    }
    
    // Mutual exclusion: the on-screen control presets win whenever they are
    // actually in effect. Absolute touch mode forces the presets off at runtime
    // (see StreamView), so the overlay is allowed there - that is the point of
    // the feature.
    BOOL presetsInEffect = ([settings.onscreenControls integerValue] != OnScreenControlsLevelOff) &&
                           !settings.absoluteTouchMode;
    if (presetsInEffect) {
        return NO;
    }
    
    // An enabled overlay with nothing to draw is inert rather than a virtual
    // gamepad that announces itself and never sends anything.
    TemporaryCustomLayout* active = [self getActiveCustomLayout];
    return active != nil && active.document != nil && ![active.document isEmpty];
}

- (void) addCustomLayout:(TemporaryCustomLayout*)layout {
    if (layout.document == nil) {
        Log(LOG_E, @"Refusing to add a custom layout without a decodable document.");
        return;
    }
    
    [_managedObjectContext performBlockAndWait:^{
        if (layout.layoutId.length == 0) {
            layout.layoutId = [[NSUUID UUID] UUIDString];
        }
        
        // Append at the end of the current order.
        int32_t maxOrder = -1;
        for (CustomLayout* row in [self fetchRecords:@"CustomLayout"]) {
            if (row.sortOrder > maxOrder) {
                maxOrder = row.sortOrder;
            }
        }
        layout.sortOrder = maxOrder + 1;
        
        NSEntityDescription* entity = [NSEntityDescription entityForName:@"CustomLayout" inManagedObjectContext:_managedObjectContext];
        CustomLayout* parent = [[CustomLayout alloc] initWithEntity:entity insertIntoManagedObjectContext:_managedObjectContext];
        parent.settings = [self retrieveSettings];
        [layout propagateChangesToParent:parent];
        
        [self saveData];
    }];
}

- (void) updateCustomLayout:(TemporaryCustomLayout*)layout {
    [_managedObjectContext performBlockAndWait:^{
        CustomLayout* parent = [self getCustomLayoutForTemporaryLayout:layout
                                                     withLayoutRecords:[self fetchRecords:@"CustomLayout"]];
        if (parent == nil) {
            Log(LOG_W, @"Custom layout '%@' no longer exists, update ignored.", layout.layoutId);
            return;
        }
        
        [layout propagateChangesToParent:parent];
        
        [self saveData];
    }];
}

- (void) removeCustomLayout:(TemporaryCustomLayout*)layout {
    [_managedObjectContext performBlockAndWait:^{
        CustomLayout* parent = [self getCustomLayoutForTemporaryLayout:layout
                                                     withLayoutRecords:[self fetchRecords:@"CustomLayout"]];
        if (parent == nil) {
            return;
        }
        
        // Clear the selection before deleting, otherwise activeLayoutId would
        // keep pointing at a row that no longer exists.
        Settings* settings = [self retrieveSettings];
        if (settings.activeLayoutId != nil && [settings.activeLayoutId isEqualToString:parent.id]) {
            settings.activeLayoutId = nil;
        }
        
        [self->_managedObjectContext deleteObject:parent];
        
        [self saveData];
    }];
}

- (void) activateCustomLayout:(NSString*)layoutId {
    [_managedObjectContext performBlockAndWait:^{
        Settings* settings = [self retrieveSettings];
        settings.activeLayoutId = (layoutId.length > 0) ? layoutId : nil;
        
        [self saveData];
    }];
}

@end

