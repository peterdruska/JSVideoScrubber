//
//  JSVideoScrubber.m
//  JSVideoScrubber
//
//  Created by jaminschubert on 9/8/12.
//  Copyright (c) 2012 jaminschubert. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

#import "JSAssetDefines.h"
#import "UIImage+JSScrubber.h"
#import "JSRenderOperation.h"
#import "JSVideoScrubber.h"
#import "Constants.h"

#define js_marker_center (self.slider.size.width / 2.)
#define js_marker_w (self.slider.size.width)
#define js_marker_start 0
#define js_marker_stop (self.frame.size.width - (js_marker_w / 2.))
#define js_marker_y_offset (self.frame.size.height - (kJSFrameInset))
#define js_zoomed_duration 0.8f

#define kJSAnimateIn 0.15f
#define kJSTrackingYFudgeFactor 24.0f

@interface JSVideoScrubber (){
    BOOL _allowZoomIn;
    BOOL zoomed; // if video si beeing zoomed
    CGFloat beforeZoomOffset;
}

@property (strong, nonatomic) NSOperationQueue *renderQueue;
@property (strong, nonatomic) AVAsset *asset;

@property (strong, nonatomic) UIImage *scrubberFrame;
@property (strong, nonatomic) UIImage *slider;
@property (assign, nonatomic) CGFloat markerLocation;
@property (assign, nonatomic) CGFloat touchOffset;
@property (assign, nonatomic) BOOL blockOffsetUpdates;

@property (strong, nonatomic) CALayer *stripLayer;
@property (strong, nonatomic) CALayer *markerLayer;

@end

@implementation JSVideoScrubber

@synthesize offset = _offset, timer = _timer, markerView = _markerView;

#pragma mark - Initialization

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    
    if (self) {
        [self initScrubber];
    }
    
    return self;
}

- (id) initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    
    if (self) {
        [self initScrubber];
    }
    
    return self;
}

- (void) initScrubber
{
    self.renderQueue = [[NSOperationQueue alloc] init];
    self.renderQueue.maxConcurrentOperationCount = 1;
    [self.renderQueue setSuspended:NO];
    
    //    self.scrubberFrame = [[UIImage imageNamed:@"border"] resizableImageWithCapInsets:UIEdgeInsetsMake(kJSFrameInset, 0.0f, kJSFrameInset, 0.0f)];
    self.slider = [[UIImage imageNamed:@"slider"] resizableImageWithCapInsets:UIEdgeInsetsMake(2.0f, 6.0f, 2.0f, 6.0f)];
    
    self.markerLocation = js_marker_start;
    self.blockOffsetUpdates = NO;
    zoomed = NO;
    _allowZoomIn = YES;
    
    [self setupControlLayers];
    self.layer.opacity = 0.0f;
}

#pragma mark - UIView

- (void) drawRect:(CGRect) rect
{
    CGPoint offset = CGPointMake((rect.origin.x + self.markerLocation), rect.origin.y + kJSMarkerInset);
    self.markerLayer.position = offset;
    self.markerView.frame = CGRectMake(offset.x, self.markerView.frame.origin.y, self.markerView.frame.size.width, self.markerView.frame.size.height);
    [self setNeedsDisplay];
}

- (void) layoutSubviews
{
    [self setupControlLayers];
    
    if (!self.asset) {
        return;
    }
    
    [UIView animateWithDuration:kJSAnimateIn
                     animations:^{
                         self.layer.opacity = 0.0f;
                     }
                     completion:^(BOOL finished) {
                         [self setupControlWithAVAsset:self.asset];
                         [self setNeedsDisplay];
                     }
     ];
}

#pragma mark - UIControl

- (BOOL) beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event
{
    [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_HIDE_PLAY_BUTTON object:nil];
    
    self.blockOffsetUpdates = YES;
    
    CGPoint l = [touch locationInView:self];
    
    // meassure time if user do not move finger on timeline
    [self stopMeassureTime]; // stop timer before we start it again
    if (_allowZoomIn) {
        [self meassureTime];
    }
    
    if ([self markerHitTest:l]) {
        self.touchOffset = l.x - self.markerLocation;
    } else {
        self.touchOffset = js_marker_center;
    }
    
    [self updateMarkerToPoint:l];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    
    return YES;
}

- (BOOL) continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event
{
    CGPoint p = [touch locationInView:self];
    CGPoint p_old = [touch previousLocationInView:self]; // previous touch point
    
    [self meassureTime]; // start timer with moving marker
    CGFloat differenceOfTwoPointsInTime = abs(p.x - p_old.x);
    
    // if finger moves more than 5 pixels, then stop timer
    if ( differenceOfTwoPointsInTime >= .1 ) {
        [self stopMeassureTime];
    }
    
    [self updateMarkerToPoint:p];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    
    return YES;
}

- (void) cancelTrackingWithEvent:(UIEvent *)event
{
    self.blockOffsetUpdates = NO;
    self.touchOffset = 0.0f;
    
    [super cancelTrackingWithEvent:event];
}

- (void) endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event
{
    self.blockOffsetUpdates = NO;
    self.touchOffset = 0.0f;
    
    [self stopMeassureTime];
    // with tracking end we send notification to RFPreviewViewController and we have to zoom out timeline
    // only if video is zoomed
    if ( zoomed ) [self zoomOut];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_SHOW_PLAY_BUTTON object:nil];
    
    [super endTrackingWithTouch:touch withEvent:event];
}

- (void) updateMarkerToPoint:(CGPoint) touchPoint
{
    FLOG();
    if ((touchPoint.x - self.touchOffset) < js_marker_start) {
        self.markerLocation = js_marker_start;
    } else if (touchPoint.x - self.touchOffset > js_marker_stop) {
        self.markerLocation = js_marker_stop;
    } else {
        self.markerLocation = touchPoint.x - self.touchOffset;
    }
    
    _offset = [self offsetForMarkerLocation];
    [self setNeedsDisplay];
}

#pragma mark - Interface

- (CGFloat) offset
{
    return _offset;
}

- (void) setOffset:(CGFloat)offset
{
    if (self.blockOffsetUpdates) {
        return;
    }
    
    CGFloat x = (offset / CMTimeGetSeconds(self.duration)) * (self.frame.size.width - js_marker_w);
    [self updateMarkerToPoint:CGPointMake(x + js_marker_start, 0.0f)];
	
    _offset = offset;
}

- (void) setupControlWithAVAsset:(AVAsset *) asset
{
    self.asset = asset;
    self.duration = asset.duration;
    
    [self queueRenderOperationForAsset:self.asset indexedAt:nil];
}

- (void) setupControlWithAVAsset:(AVAsset *) asset indexedAt:(NSArray *) requestedTimes
{
    self.asset = asset;
    self.duration = asset.duration;
    
    [self queueRenderOperationForAsset:self.asset indexedAt:requestedTimes];
}

- (void) reset
{
    [self.renderQueue cancelAllOperations];
    
    [UIView animateWithDuration:0.25f
                     animations:^{
                         self.layer.opacity = 0.0f;
                     }
                     completion:^(BOOL finished) {
                         self.asset = nil;
                         self.duration = CMTimeMakeWithSeconds(0.0, 1);
                         self.offset = 0.0f;
                         
                         self.markerLocation = js_marker_start;
                     }];
}

#pragma mark - Internal

- (void) queueRenderOperationForAsset:(AVAsset *)asset indexedAt:(NSArray *)indexes
{
    [self.renderQueue cancelAllOperations];
    
    JSRenderOperation *op = nil;
    
    if (indexes) {
        op = [[JSRenderOperation alloc] initWithAsset:asset indexAt:indexes targetFrame:self.frame];
    } else {
        op = [[JSRenderOperation alloc] initWithAsset:asset targetFrame:self.frame];
    }
    
    __weak JSVideoScrubber *ref = self;
    
    op.renderCompletionBlock = ^(UIImage *strip, NSError *error) {
        if (error) {
            NSLog(@"error rendering image strip: %@", error);
        }
        
        UIGraphicsBeginImageContext(ref.stripLayer.frame.size);
        CGContextRef context = UIGraphicsGetCurrentContext();
        
        CGImageRef cg_img = strip.CGImage;
        
        size_t masked_h = CGImageGetHeight(cg_img);
        size_t masked_w = CGImageGetWidth(cg_img);
        
        CGFloat x = ref.stripLayer.frame.origin.x;
        CGFloat y = ref.stripLayer.frame.origin.y + kJSFrameInset;
        
        CGContextDrawImage(context, CGRectMake(x, y, masked_w, masked_h), cg_img);
        [ref.scrubberFrame drawInRect:ref.stripLayer.frame];
        
        UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
        ref.stripLayer.contents = (__bridge id)img.CGImage;
        
        UIGraphicsEndImageContext();
        
        ref.markerLayer.contents = (__bridge id)ref.slider.CGImage;
        //ref.markerLocation = [ref markerLocationForCurrentOffset];
        
        [ref setNeedsDisplay];
        
        [UIView animateWithDuration:kJSAnimateIn animations:^{
            ref.markerView.alpha = 1.0f;
            ref.layer.opacity = 1.0f;
        }];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_SHOW_RATING_VIEWS object:nil];
    };
    
    [self.renderQueue addOperation:op];
}

- (CGFloat) offsetForMarkerLocation
{
    FLOG();
    CGFloat ratio = (self.markerLocation / (selfWidth - js_marker_w));
    if (zoomed) {
        return ((ratio * CMTimeGetSeconds(self.duration)) + CMTimeGetSeconds(_zoomedTimeRange.start));
    } else {
        return (ratio * CMTimeGetSeconds(self.duration));
    }
}

- (CGFloat) markerLocationForCurrentOffset
{
    FLOG();
    CGFloat ratio = self.offset / CMTimeGetSeconds(self.duration);
    CGFloat location = ratio * (js_marker_stop - js_marker_start);
    
    if (location < js_marker_start) {
        return js_marker_start;
    }
    
    if (location > js_marker_stop) {
        return js_marker_stop;
    }
    
    return location;
}

- (BOOL) markerHitTest:(CGPoint) point
{
    if (point.x < self.markerLocation || point.x > (self.markerLocation + self.slider.size.width)) { //x test
        return NO;
    }
    
    if (point.y < kJSMarkerInset || point.y > (kJSMarkerInset + self.slider.size.height)) { //y test
        return NO;
    }
    
    return YES;
}

- (void) setupControlLayers
{
    self.stripLayer = [CALayer layer];
    self.markerLayer = [CALayer layer];
    
    self.stripLayer.bounds = self.bounds;
    self.markerLayer.bounds = CGRectMake(0, 0.0, self.slider.size.width, self.bounds.size.height - (2 * kJSMarkerInset) + 4.0);
    
    self.stripLayer.anchorPoint = CGPointZero;
    self.markerLayer.anchorPoint = CGPointMake(0.0, 0.0);
    
    //do not apply animations on these properties
    NSDictionary *d =  @{@"position":[NSNull null], @"bounds":[NSNull null], @"anchorPoint": [NSNull null]};
    self.stripLayer.actions = d;
    self.markerLayer.actions = d;
    self.markerLayer.hidden = YES; // if user continues tracking marker, app doesn't need it to show
    
    // prepare marker view
    self.markerView = [[UIView alloc] initWithFrame:CGRectMake(0. - (5. - 1.) / 2., -2., 5., self.frame.size.height+4.)];
    self.markerView.backgroundColor = [UIColor whiteColor];
    self.markerView.alpha = 0.0f;
    self.markerView.hidden = NO;
    
    [self.layer addSublayer:self.markerLayer];
    [self.layer addSublayer:self.markerView.layer];
    [self.layer insertSublayer:self.stripLayer below:self.markerLayer];
    [self.layer insertSublayer:self.markerLayer below:self.markerView.layer];
}

#pragma mark - Timer of changing marker position

-(void)meassureTime{
    [self stopMeassureTime];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:TIME_TO_ZOOM_IN
                                                  target:self
                                                selector:@selector(timer:)
                                                userInfo:nil repeats:NO];
}

-(void)stopMeassureTime{
    // reset timer
    [self.timer invalidate];
    self.timer = nil;
}

-(void)timer:(id)sender{
    // if difference of marker points is less then 5 pixels in some time, zoom in - send notification to RFPreviewViewController
    // ==
    // if timer reaches time of .5 second
    if (_allowZoomIn) {
        [self zoomIn];
    }
    [self stopMeassureTime];
}

#pragma mark - Zoom in

-(void)setAllowZoomIn:(BOOL)allowZoomIn {
    _allowZoomIn = allowZoomIn;
    if (!_allowZoomIn) {
        [self stopMeassureTime];
    }
}

#pragma mark - Zoom actions

-(void)zoomIn {
    
    zoomed = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_ZOOM_IN object:self];
    
    beforeZoomOffset = _offset;
    CMTime currentTime = CMTimeMakeWithSeconds(_offset, RF_NSEC_PER_SEC);
    CGFloat zoomed_timeRation = beforeZoomOffset / CMTimeGetSeconds(self.duration);
    
    CMTime startTime = CMTimeMakeWithSeconds(CMTimeGetSeconds(currentTime) - (js_zoomed_duration * zoomed_timeRation), RF_NSEC_PER_SEC);
    
    NSLog(@"current offset %f", beforeZoomOffset);
    NSLog(@"current time %f", CMTimeGetSeconds(currentTime));
    NSLog(@"zoomed_time_ratio %f", zoomed_timeRation);
    NSLog(@"start time %f", CMTimeGetSeconds(startTime));
    
	CMTime durationTime = CMTimeMakeWithSeconds(js_zoomed_duration, RF_NSEC_PER_SEC);
	_zoomedTimeRange = CMTimeRangeMake(startTime, durationTime);
    _duration = durationTime;
    
    CGFloat startTimeSecs = CMTimeGetSeconds(startTime);
    
    // fill out screenshot array
    NSMutableArray * requestedTimes = [NSMutableArray array];
    for (int i=0; i<9; i++) {
        [requestedTimes addObject:[NSNumber numberWithDouble:startTimeSecs + i*0.1]];
    }
    [self queueRenderOperationForAsset:self.asset indexedAt:requestedTimes];
    
    [self updateMarkerToPoint:CGPointMake(self.markerLocation + self.touchOffset, 0.0f)];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

-(void)zoomOut {
    
    zoomed = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_ZOOM_OUT object:self];
    
    self.duration = self.asset.duration;
    _zoomedTimeRange = kCMTimeRangeZero;
    [self queueRenderOperationForAsset:self.asset indexedAt:nil];
    
    CGFloat x = (beforeZoomOffset / CMTimeGetSeconds(self.duration)) * (self.frame.size.width - js_marker_w);
    [UIView animateWithDuration:0.3 animations:^{
        self.markerView.frame = CGRectMake(x, self.markerView.frame.origin.y, self.markerView.frame.size.width, self.markerView.frame.size.height);
        self.offset = beforeZoomOffset;
    } completion:^(BOOL finished) {
        self.offset = beforeZoomOffset;
        [self sendActionsForControlEvents:UIControlEventValueChanged];
    }];
    
}

@end
