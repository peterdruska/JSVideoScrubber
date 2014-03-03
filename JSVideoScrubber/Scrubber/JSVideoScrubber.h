//
//  JSVideoScrubber.h
//  JSVideoScrubber
//
//  Created by jaminschubert on 9/8/12.
//  Copyright (c) 2012 jaminschubert. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

@interface JSVideoScrubber : UIControl

@property (assign, nonatomic) CMTime duration;
@property (assign, nonatomic) CGFloat offset;
@property (strong, nonatomic) NSTimer *timer;
@property (strong, nonatomic) UIView *markerView;
@property (assign, nonatomic) BOOL allowZoomIn;
@property (assign, nonatomic) CMTimeRange zoomedTimeRange;

- (void) setupControlWithAVAsset:(AVAsset *) asset;
- (void) setupControlWithAVAsset:(AVAsset *) asset indexedAt:(NSArray *) requestedTimes;
- (void) reset;

@end
