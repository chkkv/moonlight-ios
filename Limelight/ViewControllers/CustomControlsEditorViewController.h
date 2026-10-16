//
//  CustomControlsEditorViewController.h
//  Moonlight
//
//  Authoring UI for one custom control layout.
//
//  The canvas IS the device screen: it fills the window and the controls are
//  laid out with exactly the same call the live overlay uses, so what the editor
//  shows is what streaming shows. There is no separate scale or "preview band"
//  that could drift out of sync.
//
//  The navigation bar is hidden; actions live in a toolbar that slides in from
//  the left edge so the canvas stays unobstructed while editing.
//

#import <UIKit/UIKit.h>

#import "TemporaryCustomLayout.h"

@interface CustomControlsEditorViewController : UIViewController

- (instancetype)initWithLayout:(TemporaryCustomLayout *)layout;

@end
