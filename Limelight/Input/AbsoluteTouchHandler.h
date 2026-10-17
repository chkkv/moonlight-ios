//
//  AbsoluteTouchHandler.h
//  Moonlight
//
//  Created by Cameron Gutman on 11/1/20.
//  Copyright © 2020 Moonlight Game Streaming Project. All rights reserved.
//

#import "StreamView.h"

NS_ASSUME_NONNULL_BEGIN

@interface AbsoluteTouchHandler : UIResponder

// multitouch: when YES the touches are forwarded to the host as real touch
// events instead of driving an emulated absolute mouse. The two behaviours are
// mutually exclusive.
-(id)initWithView:(StreamView*)view multitouch:(BOOL)multitouch;

@end

NS_ASSUME_NONNULL_END
