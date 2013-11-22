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
@property (assign, nonatomic) CGFloat pauseMarkerLocation;
@property (assign, nonatomic) CGFloat playMarkerLocation;
@property (assign, nonatomic) CGFloat moveMarkerLocation;
@property (assign, nonatomic) NSTimer *timer;

- (void) setupControlWithAVAsset:(AVAsset *) asset;
- (void) setupControlWithAVAsset:(AVAsset *) asset indexedAt:(NSArray *) requestedTimes;
- (void) reset;

-(void)animateMarker:(id)sender withPlayTimeInterval:(NSTimeInterval)timeInterval;
// timeInterval is the value of marker, where we pause played video
-(void)stopAnimateMarker:(id)sender withPauseTimeInterval:(NSTimeInterval)timeInterval;
-(void)moveMarkerToTimeInterval:(NSTimeInterval)timeInterval;

@end
