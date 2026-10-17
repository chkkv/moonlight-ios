//
//  SettingsViewController.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/27/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"

@interface SettingsViewController : UIViewController
@property (strong, nonatomic) IBOutlet UILabel *bitrateLabel;
@property (strong, nonatomic) IBOutlet UISlider *bitrateSlider;
@property (strong, nonatomic) IBOutlet UISegmentedControl *framerateSelector;
@property (strong, nonatomic) IBOutlet UISegmentedControl *resolutionSelector;
@property (strong, nonatomic) IBOutlet UIView *resolutionDisplayView;
@property (strong, nonatomic) IBOutlet UISegmentedControl *touchModeSelector;
// Touchscreen only: No keeps the absolute-mouse emulation, Yes forwards real
// multi-touch touches. The two are mutually exclusive, so this row is only
// enabled while Touchscreen is selected.
@property (strong, nonatomic) IBOutlet UISegmentedControl *multitouchSelector;
@property (strong, nonatomic) IBOutlet UISegmentedControl *onscreenControlSelector;
@property (strong, nonatomic) IBOutlet UISegmentedControl *optimizeSettingsSelector;
@property (strong, nonatomic) IBOutlet UISegmentedControl *multiControllerSelector;
@property (strong, nonatomic) IBOutlet UISegmentedControl *swapABXYButtonsSelector;
@property (strong, nonatomic) IBOutlet UISegmentedControl *audioOnPCSelector;
@property (strong, nonatomic) IBOutlet UISegmentedControl *codecSelector;
@property (strong, nonatomic) IBOutlet UISegmentedControl *hdrSelector;
@property (strong, nonatomic) IBOutlet UISegmentedControl *framePacingSelector;
@property (strong, nonatomic) IBOutlet UISegmentedControl *btMouseSelector;
@property (strong, nonatomic) IBOutlet UISegmentedControl *statsOverlaySelector;
@property (strong, nonatomic) IBOutlet UISegmentedControl *bufferFramesSelector;
// Custom overlay: Off/On, plus a single-segment row that opens the layout list.
@property (strong, nonatomic) IBOutlet UISegmentedControl *customOverlaySelector;
@property (strong, nonatomic) IBOutlet UISegmentedControl *customLayoutsSelector;
// No/Yes: always show the host list on launch instead of going straight into the
// only saved host. Stored in NSUserDefaults, not in the CoreData settings.
@property (strong, nonatomic) IBOutlet UISegmentedControl *showHostListSelector;
@property (strong, nonatomic) IBOutlet UIScrollView *scrollView;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"

// This is okay because it's just an enum and access uses @available checks
@property(nonatomic) UIUserInterfaceStyle overrideUserInterfaceStyle;

#pragma clang diagnostic pop

- (void) saveSettings;

@end
