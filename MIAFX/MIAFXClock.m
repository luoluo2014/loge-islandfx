//
//  MIAFXClock.m
//  MIAFX
//

#import "MIAFXClock.h"

#import <QuartzCore/QuartzCore.h>

#import "MIAFXLog.h"
#import "MIAFXSafe.h"
#import "MIAFXSafeInline.h"

@interface MIAFXClockSubscription : NSObject
@property (nonatomic) NSUInteger token;
@property (nonatomic) double fps;
@property (nonatomic) NSTimeInterval lastStamp;
@property (nonatomic, copy) MIAFXClockTick block;
@end

@implementation MIAFXClockSubscription
@end

@interface MIAFXClock ()
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, MIAFXClockSubscription *> *subscriptions;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *pendingRemovals;
@property (nonatomic) NSUInteger nextToken;
@property (nonatomic) NSTimeInterval lastStamp;
@property (nonatomic, getter=isLinkPaused) BOOL linkPaused;
@end

@implementation MIAFXClock

+ (instancetype)sharedClock {
    static MIAFXClock *sharedClock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedClock = [[MIAFXClock alloc] init];
    });
    return sharedClock;
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    _subscriptions = [NSMutableDictionary dictionary];
    _pendingRemovals = [NSMutableArray array];
    _nextToken = 1;
    _lastStamp = CACurrentMediaTime();
    _linkPaused = YES;
    return self;
}

- (NSTimeInterval)now {
    return CACurrentMediaTime();
}

- (NSUInteger)subscribe:(MIAFXClockTick)block {
    return [self subscribeWithFPS:60.0 block:block];
}

- (NSUInteger)subscribeWithFPS:(double)fps block:(MIAFXClockTick)block {
    if (!block) {
        return 0;
    }
    if (![NSThread isMainThread]) {
        MIAFXLog(@"Clock 订阅必须在主线程完成，已忽略一次订阅请求");
        return 0;
    }
    double normalized = fps;
    if (!isfinite(normalized) || normalized <= 0.0) {
        normalized = 60.0;
    }
    if (normalized > 60.0) {
        normalized = 60.0;
    }
    MIAFXClockSubscription *subscription = [[MIAFXClockSubscription alloc] init];
    subscription.token = self.nextToken++;
    subscription.fps = normalized;
    subscription.lastStamp = CACurrentMediaTime();
    subscription.block = block;
    self.subscriptions[@(subscription.token)] = subscription;
    [self syncDisplayLink];
    return subscription.token;
}

- (void)setFPS:(double)fps forToken:(NSUInteger)token {
    if (token == 0) {
        return;
    }
    MIAFXClockSubscription *subscription = self.subscriptions[@(token)];
    if (!subscription) {
        return;
    }
    double normalized = fps;
    if (!isfinite(normalized) || normalized <= 0.0) {
        normalized = 60.0;
    }
    if (normalized > 60.0) {
        normalized = 60.0;
    }
    subscription.fps = normalized;
    [self syncDisplayLink];
}

- (void)unsubscribe:(NSUInteger)token {
    if (token == 0) {
        return;
    }
    [self.subscriptions removeObjectForKey:@(token)];
    [self syncDisplayLink];
}

- (NSUInteger)subscriberCount {
    return self.subscriptions.count;
}

- (void)setPaused:(BOOL)paused {
    if (self.linkPaused == paused) {
        return;
    }
    self.linkPaused = paused;
    [self syncDisplayLink];
}

- (BOOL)isPaused {
    return self.linkPaused;
}

- (void)invalidate {
    if (self.displayLink) {
        [self.displayLink invalidate];
        self.displayLink = nil;
    }
    [self.subscriptions removeAllObjects];
}

#pragma mark - Internal

- (void)syncDisplayLink {
    BOOL shouldRun = (self.subscriptions.count > 0) && !self.linkPaused;

    if (!shouldRun) {
        if (self.displayLink) {
            self.displayLink.paused = YES;
        }
        return;
    }

    if (!self.displayLink) {
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(handleDisplayLink:)];
        link.paused = YES;
        [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        self.displayLink = link;
        self.lastStamp = CACurrentMediaTime();
    }

    double maximum = 0.0;
    for (MIAFXClockSubscription *subscription in self.subscriptions.allValues) {
        if (subscription.fps > maximum) {
            maximum = subscription.fps;
        }
    }
    NSInteger preferred = (NSInteger)llround(maximum);
    if (preferred < 30) {
        preferred = 30;
    }
    if (preferred > 60) {
        preferred = 60;
    }
    self.displayLink.preferredFramesPerSecond = preferred;
    self.displayLink.paused = NO;
}

- (void)handleDisplayLink:(CADisplayLink *)link {
    NSTimeInterval stamp = link.timestamp;
    NSTimeInterval delta = stamp - self.lastStamp;
    if (delta < 0.0 || !isfinite(delta)) {
        delta = 0.0;
    }
    self.lastStamp = stamp;

    NSArray<MIAFXClockSubscription *> *snapshot = self.subscriptions.allValues;
    for (MIAFXClockSubscription *subscription in snapshot) {
        if (!self.subscriptions[@(subscription.token)]) {
            continue;
        }
        double interval = 1.0 / MAX(subscription.fps, 1.0);
        NSTimeInterval elapsed = stamp - subscription.lastStamp;
        if (elapsed < interval - 0.0005) {
            continue;
        }
        subscription.lastStamp = stamp;
        if (elapsed < 0.0 || !isfinite(elapsed)) {
            elapsed = interval;
        }
        MIAFXClockTick block = subscription.block;
        if (!block) {
            continue;
        }
        MIAFXRunProtected(@"Clock", ^{
            block(stamp, elapsed);
        });
    }
}

- (void)dealloc {
    [self invalidate];
}

@end
