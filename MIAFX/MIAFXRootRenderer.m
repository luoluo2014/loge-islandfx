//
//  MIAFXRootRenderer.m
//  MIAFX
//
//  管理 compact / expanded 两套完整特效栈。
//

#import "MIAFXRootRenderer.h"

#import <QuartzCore/QuartzCore.h>

#import "MIAFXBreathing.h"
#import "MIAFXClock.h"
#import "MIAFXConfig.h"
#import "MIAFXConstants.h"
#import "MIAFXLog.h"
#import "MIAFXMarqueeFX.h"
#import "MIAFXMetaballFX.h"
#import "MIAFXNativeElementBridge.h"
#import "MIAFXOrbitFX.h"
#import "MIAFXPassthroughView.h"
#import "MIAFXProbe.h"
#import "MIAFXSafe.h"
#import "MIAFXSafeInline.h"
#import "MIAFXSpectrumView.h"
#import "MIAFXVideoLayer.h"

static CGFloat MIAFXRendererClamp(CGFloat value, CGFloat low, CGFloat high) {
    if (!isfinite((double)value)) {
        return low;
    }
    return value < low ? low : (value > high ? high : value);
}

#pragma mark - Stage

/// 一套完整特效（视频 + 呼吸 + 流光 + 轨道 + 元球 + 频谱）
///
/// 视图层级：
///   videoRhythmRoot   ← 节奏 transform
///     └ videoRoot     ← 视频容器
///   effectRhythmRoot  ← 节奏 transform
///     └ effectRoot    ← 呼吸 transform
///         ├ marquee / orbit / metaball / spectrum
@interface MIAFXRenderStage : NSObject
- (instancetype)initWithVideoPrefix:(NSString *)prefix NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, copy, readonly) NSString *videoPrefix;

@property (nonatomic, strong, readonly) MIAFXPassthroughView *videoRhythmRoot;
@property (nonatomic, strong, readonly) MIAFXPassthroughView *videoRoot;
@property (nonatomic, strong, readonly) MIAFXPassthroughView *effectRhythmRoot;
@property (nonatomic, strong, readonly) MIAFXPassthroughView *effectRoot;

@property (nonatomic, strong, readonly) MIAFXVideoLayer *video;
@property (nonatomic, strong, readonly) MIAFXBreathing *breathing;
@property (nonatomic, strong, readonly) MIAFXMarqueeFX *marquee;
@property (nonatomic, strong, readonly) MIAFXOrbitFX *orbit;
@property (nonatomic, strong, readonly) MIAFXMetaballFX *metaball;
@property (nonatomic, strong, readonly) MIAFXSpectrumView *spectrum;

@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (nonatomic, readonly, getter=isActive) BOOL active;

- (void)setActive:(BOOL)active;
- (void)layoutInBounds:(CGRect)bounds;
- (void)reloadConfiguration;
- (void)setRunning:(BOOL)running;
- (void)tickWithTimestamp:(NSTimeInterval)timestamp delta:(NSTimeInterval)delta;
- (void)applyRhythmTransform;
- (NSString *)runtimeDescription;
@end

@implementation MIAFXRenderStage {
    BOOL _running;
    BOOL _active;
    CGRect _cachedBounds;
}

- (instancetype)initWithVideoPrefix:(NSString *)prefix {
    self = [super init];
    if (!self) {
        return nil;
    }
    _videoPrefix = [prefix copy];
    _cachedBounds = CGRectZero;
    _running = NO;
    _active = NO;

    _videoRhythmRoot = [[MIAFXPassthroughView alloc] initWithFrame:CGRectZero];
    _videoRoot = [[MIAFXPassthroughView alloc] initWithFrame:CGRectZero];
    _effectRhythmRoot = [[MIAFXPassthroughView alloc] initWithFrame:CGRectZero];
    _effectRoot = [[MIAFXPassthroughView alloc] initWithFrame:CGRectZero];

    for (UIView *view in @[ _videoRhythmRoot, _videoRoot, _effectRhythmRoot, _effectRoot ]) {
        view.backgroundColor = [UIColor clearColor];
        view.opaque = NO;
    }

    _video = [[MIAFXVideoLayer alloc] initWithConfigurationPrefix:prefix];
    [_videoRoot addSubview:_video.contentView];

    _marquee = [[MIAFXMarqueeFX alloc] initWithFrame:CGRectZero];
    _orbit = [[MIAFXOrbitFX alloc] initWithFrame:CGRectZero];
    _metaball = [[MIAFXMetaballFX alloc] initWithFrame:CGRectZero];
    _spectrum = [[MIAFXSpectrumView alloc] initWithFrame:CGRectZero];

    [_effectRoot addSubview:_marquee.contentView];
    [_effectRoot addSubview:_orbit.contentView];
    [_effectRoot addSubview:_metaball.contentView];
    [_effectRoot addSubview:_spectrum];

    _breathing = [[MIAFXBreathing alloc] initWithTargetView:_effectRoot];

    [self reloadConfiguration];
    return self;
}

- (BOOL)isRunning {
    return _running;
}

- (BOOL)isActive {
    return _active;
}

- (void)setActive:(BOOL)active {
    _active = active;
    self.videoRhythmRoot.hidden = !active;
    self.effectRhythmRoot.hidden = !active;
}

- (void)reloadConfiguration {
    [self.video reloadConfiguration];
    [self.breathing reloadConfiguration];
    [self.marquee reloadConfiguration];
    [self.orbit reloadConfiguration];
    [self.metaball reloadConfiguration];
    [self.spectrum reloadConfiguration];
    [self layoutInBounds:_cachedBounds];
}

- (void)layoutInBounds:(CGRect)bounds {
    if (CGRectIsEmpty(bounds) || !isfinite((double)bounds.size.width) || !isfinite((double)bounds.size.height)) {
        return;
    }
    _cachedBounds = bounds;
    CGRect local = CGRectMake(0.0, 0.0, bounds.size.width, bounds.size.height);

    for (UIView *view in @[ self.videoRhythmRoot, self.videoRoot, self.effectRhythmRoot, self.effectRoot ]) {
        view.frame = bounds;
        view.bounds = local;
    }

    self.marquee.contentView.frame = local;
    self.orbit.contentView.frame = local;
    self.metaball.contentView.frame = local;
    self.spectrum.frame = local;

    [self.video layoutInBounds:local];
    [self.marquee layoutInBounds:local];
    [self.orbit layoutInBounds:local];
    [self.metaball layoutInBounds:local];
    [self.spectrum layoutInBounds:local];
}

- (void)setRunning:(BOOL)running {
    if (_running == running) {
        return;
    }
    _running = running;
    [self.breathing setRunning:running];
    [self.marquee setRunning:running];
    [self.orbit setRunning:running];
    [self.metaball setRunning:running];
    [self.spectrum setRunning:running];
    if (running) {
        [self.video resume];
    } else {
        [self.video pause];
    }
}

- (void)pausePlaybackOnly {
    [self.video pause];
}

- (void)tickWithTimestamp:(NSTimeInterval)timestamp delta:(NSTimeInterval)delta {
    [self.breathing tickWithTimestamp:timestamp delta:delta];
    [self.marquee tickWithTimestamp:timestamp delta:delta];
    [self.orbit tickWithTimestamp:timestamp delta:delta];
    [self.metaball tickWithTimestamp:timestamp delta:delta];
    [self.spectrum tickWithTimestamp:timestamp delta:delta];
}

- (void)applyRhythmTransform {
    MIAFXConfig *config = [MIAFXConfig sharedConfig];
    if (![config isFeatureEnabled:MIAFXFeatureRhythm]) {
        self.videoRhythmRoot.transform = CGAffineTransformIdentity;
        self.effectRhythmRoot.transform = CGAffineTransformIdentity;
        return;
    }
    CGFloat offsetX = [config doubleForKey:@"MIAFXRhythmOffsetX"];
    CGFloat offsetY = [config doubleForKey:@"MIAFXRhythmOffsetY"];
    CGFloat scaleAmount = [config doubleForKey:@"MIAFXRhythmScale"];
    CGFloat level = (CGFloat)self.spectrum.level;
    CGFloat scale = 1.0 + level * scaleAmount;

    CGAffineTransform transform = CGAffineTransformIdentity;
    transform = CGAffineTransformTranslate(transform, offsetX * level, offsetY * level);
    transform = CGAffineTransformScale(transform, scale, scale);
    self.videoRhythmRoot.transform = transform;
    self.effectRhythmRoot.transform = transform;
}

- (NSString *)runtimeDescription {
    return [NSString stringWithFormat:@"video=%@ breathing=%ld(%.3f/%.3f) orbit=%ld/%ld metaball=%ld@%.0f spectrum=%ld/%ld",
            self.video.statusDescription,
            (long)self.breathing.currentType,
            self.breathing.currentScale,
            self.breathing.currentBrightness,
            (long)self.orbit.assetCount,
            (long)self.orbit.orbitCount,
            (long)self.metaball.ballCount,
            self.metaball.activeFPS,
            (long)self.spectrum.form,
            (long)self.spectrum.barCount];
}

@end

#pragma mark - RootRenderer

@interface MIAFXRootRenderer ()
@property (nonatomic, weak, readwrite) UIView *hostView;
@property (nonatomic, strong, readwrite) MIAFXPassthroughView *backgroundView;
@property (nonatomic, strong, readwrite) MIAFXPassthroughView *overlayView;
@property (nonatomic, readwrite, getter=isAttached) BOOL attached;
@property (nonatomic, readwrite, getter=isRunning) BOOL running;
@property (nonatomic, readwrite, getter=isSuspended) BOOL suspended;
@property (nonatomic, readwrite, getter=isExpanded) BOOL expanded;
@property (nonatomic, readwrite) CGRect hostBounds;
@property (nonatomic, copy, readwrite) NSString *runtimeDescription;

@property (nonatomic, strong) MIAFXRenderStage *compactStage;
@property (nonatomic, strong) MIAFXRenderStage *expandedStage;
@property (nonatomic, strong) NSArray<MIAFXNativeElementBridge *> *nativeBridges;
@property (nonatomic) NSUInteger clockToken;
@property (nonatomic) MIAFXLayerMode layerMode;
@property (nonatomic) NSInteger maxFPS;
@property (nonatomic) NSTimeInterval startStamp;
@end

@implementation MIAFXRootRenderer

- (instancetype)initWithHostView:(UIView *)hostView {
    self = [super init];
    if (!self) {
        return nil;
    }
    _hostView = hostView;
    _hostBounds = hostView ? hostView.bounds : CGRectZero;
    _expanded = NO;
    _attached = NO;
    _running = NO;
    _suspended = NO;
    _clockToken = 0;
    _layerMode = MIAFXLayerModeBackground;
    _maxFPS = 30;
    _startStamp = CACurrentMediaTime();
    _runtimeDescription = @"idle";

    _backgroundView = [[MIAFXPassthroughView alloc] initWithFrame:_hostBounds];
    _backgroundView.backgroundColor = [UIColor clearColor];
    _backgroundView.opaque = NO;
    _backgroundView.clipsToBounds = YES;
    _backgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _overlayView = [[MIAFXPassthroughView alloc] initWithFrame:_hostBounds];
    _overlayView.backgroundColor = [UIColor clearColor];
    _overlayView.opaque = NO;
    _overlayView.clipsToBounds = NO;
    _overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _compactStage = [[MIAFXRenderStage alloc] initWithVideoPrefix:@"Compact.Video"];
    _expandedStage = [[MIAFXRenderStage alloc] initWithVideoPrefix:@"Expanded.Video"];

    MIAFXNativeElementBridge *left = [[MIAFXNativeElementBridge alloc] initWithSlot:MIAFXNativeSlotCompactLeft];
    MIAFXNativeElementBridge *right = [[MIAFXNativeElementBridge alloc] initWithSlot:MIAFXNativeSlotCompactRight];
    MIAFXNativeElementBridge *track = [[MIAFXNativeElementBridge alloc] initWithSlot:MIAFXNativeSlotExpandedTrack];
    MIAFXNativeElementBridge *side = [[MIAFXNativeElementBridge alloc] initWithSlot:MIAFXNativeSlotExpandedSide];
    _nativeBridges = @[ left, right, track, side ];

    [self reloadConfiguration];
    return self;
}

- (void)dealloc {
    [self detach];
}

#pragma mark - Mounting

- (BOOL)attachToHost {
    MIAFXRunProtected(@"RootRenderer", ^{
        UIView *host = self.hostView;
        if (!host) {
            self.attached = NO;
            return;
        }
        if (self.backgroundView.superview != host) {
            [self.backgroundView removeFromSuperview];
            self.backgroundView.frame = host.bounds;
            // 背景层：subviews 的 index 0
            [host insertSubview:self.backgroundView atIndex:0];
        }
        if (self.overlayView.superview != host) {
            [self.overlayView removeFromSuperview];
            self.overlayView.frame = host.bounds;
            // 覆盖层：最上方
            [host addSubview:self.overlayView];
        }
        self.attached = YES;
        [self applyLayerMode];
    });
    return self.attached;
}

- (BOOL)attachWithBackgroundContainer:(UIView *)backgroundContainer
                    overlayContainer:(UIView *)overlayContainer {
    MIAFXRunProtected(@"RootRenderer", ^{
        if (!backgroundContainer || !overlayContainer) {
            self.attached = NO;
            return;
        }
        if (self.backgroundView.superview != backgroundContainer) {
            [self.backgroundView removeFromSuperview];
            self.backgroundView.frame = backgroundContainer.bounds;
            [backgroundContainer insertSubview:self.backgroundView atIndex:0];
        }
        if (self.overlayView.superview != overlayContainer) {
            [self.overlayView removeFromSuperview];
            self.overlayView.frame = overlayContainer.bounds;
            [overlayContainer addSubview:self.overlayView];
        }
        self.attached = YES;
        [self applyLayerMode];
    });
    return self.attached;
}

- (void)detach {
    MIAFXRunProtected(@"RootRenderer", ^{
        [self stop];
        [self.backgroundView removeFromSuperview];
        [self.overlayView removeFromSuperview];
        for (MIAFXNativeElementBridge *bridge in self.nativeBridges) {
            [bridge restore];
        }
        self.attached = NO;
    });
}

- (void)applyLayerMode {
    UIView *videoTarget = self.backgroundView;
    UIView *effectTarget = self.backgroundView;

    switch (self.layerMode) {
        case MIAFXLayerModeBackground:
            videoTarget = self.backgroundView;
            effectTarget = self.backgroundView;
            break;
        case MIAFXLayerModeOverlay:
            videoTarget = self.overlayView;
            effectTarget = self.overlayView;
            break;
        case MIAFXLayerModeBoth:
            videoTarget = self.backgroundView;
            effectTarget = self.overlayView;
            break;
    }

    for (MIAFXRenderStage *stage in @[ self.compactStage, self.expandedStage ]) {
        if (stage.videoRhythmRoot.superview != videoTarget) {
            [stage.videoRhythmRoot removeFromSuperview];
            [videoTarget addSubview:stage.videoRhythmRoot];
        }
        if (stage.effectRhythmRoot.superview != effectTarget) {
            [stage.effectRhythmRoot removeFromSuperview];
            [effectTarget addSubview:stage.effectRhythmRoot];
        }
    }
}

#pragma mark - Configuration

- (void)reloadConfiguration {
    MIAFXRunProtected(@"RootRenderer", ^{
        MIAFXConfig *config = [MIAFXConfig sharedConfig];
        NSInteger mode = [config integerForKey:@"Global.LayerMode"];
        self.layerMode = (MIAFXLayerMode)MIAFXRendererClamp((CGFloat)mode, 0, 2);
        NSInteger fps = [config integerForKey:@"Global.MaxFPS"];
        self.maxFPS = (NSInteger)MIAFXRendererClamp((CGFloat)fps, 15, 60);

        [self.compactStage reloadConfiguration];
        [self.expandedStage reloadConfiguration];

        for (MIAFXNativeElementBridge *bridge in self.nativeBridges) {
            [bridge reloadConfiguration];
        }

        [self applyLayerMode];
        [self updateHostBounds:self.hostBounds expanded:self.expanded];
        [self resubscribeClock];
        [self updateRuntimeDescription];
    });
}

- (void)resubscribeClock {
    if (self.clockToken != 0) {
        [[MIAFXClock sharedClock] unsubscribe:self.clockToken];
        self.clockToken = 0;
    }
    __weak typeof(self) weakSelf = self;
    self.clockToken = [[MIAFXClock sharedClock] subscribeWithFPS:(double)self.maxFPS block:^(NSTimeInterval timestamp, NSTimeInterval delta) {
        [weakSelf tick:timestamp delta:delta];
    }];
    if (!self.running || self.suspended) {
        [[MIAFXClock sharedClock] setPaused:YES];
    }
}

#pragma mark - Geometry

- (void)updateHostBounds:(CGRect)bounds expanded:(BOOL)expanded {
    MIAFXRunProtected(@"RootRenderer", ^{
        CGRect resolved = bounds;
        if (CGRectIsEmpty(resolved) || !isfinite((double)resolved.size.width) || !isfinite((double)resolved.size.height)) {
            resolved = self.hostBounds;
        }
        if (CGRectIsEmpty(resolved)) {
            resolved = [MIAFXRootRenderer fallbackBoundsForExpanded:expanded];
        }

        MIAFXConfig *config = [MIAFXConfig sharedConfig];
        CGFloat offsetX = MIAFXRendererClamp([config doubleForKey:@"Geometry.ManualOffsetX"], -500.0, 500.0);
        CGFloat offsetY = MIAFXRendererClamp([config doubleForKey:@"Geometry.ManualOffsetY"], -500.0, 500.0);
        resolved.origin.x += offsetX;
        resolved.origin.y += offsetY;

        self.hostBounds = resolved;
        self.expanded = expanded;

        UIView *backgroundSuperview = self.backgroundView.superview;
        UIView *overlaySuperview = self.overlayView.superview;
        if (backgroundSuperview) {
            self.backgroundView.frame = backgroundSuperview.bounds;
        }
        if (overlaySuperview) {
            self.overlayView.frame = overlaySuperview.bounds;
        }

        [self.compactStage setActive:!expanded];
        [self.expandedStage setActive:expanded];
        [self.compactStage layoutInBounds:resolved];
        [self.expandedStage layoutInBounds:resolved];

        UIView *root = self.hostView;
        for (MIAFXNativeElementBridge *bridge in self.nativeBridges) {
            BOOL wantsExpanded = (bridge.slot == MIAFXNativeSlotExpandedTrack || bridge.slot == MIAFXNativeSlotExpandedSide);
            if (wantsExpanded == expanded) {
                [bridge updateWithRootView:root];
            } else {
                [bridge restore];
            }
        }

        [self updateRuntimeDescription];
    });
}

+ (CGRect)fallbackBoundsForExpanded:(BOOL)expanded {
    MIAFXConfig *config = [MIAFXConfig sharedConfig];
    CGFloat width = MIAFXRendererClamp([config doubleForKey:@"Geometry.CompactWidth"], 40.0, 600.0);
    CGFloat height = expanded
        ? MIAFXRendererClamp([config doubleForKey:@"Geometry.ExpandedHeight"], 40.0, 600.0)
        : MIAFXRendererClamp([config doubleForKey:@"Geometry.CompactHeight"], 10.0, 300.0);
    CGRect screen = [UIScreen mainScreen].bounds;
    CGFloat x = (screen.size.width - width) * 0.5;
    if (!isfinite(x)) {
        x = 0.0;
    }
    return CGRectMake(x, 0.0, width, height);
}

#pragma mark - Lifecycle

- (void)start {
    if (self.running) {
        return;
    }
    self.running = YES;
    self.suspended = NO;
    self.startStamp = CACurrentMediaTime();
    [self.compactStage setRunning:YES];
    [self.expandedStage setRunning:YES];
    for (MIAFXNativeElementBridge *bridge in self.nativeBridges) {
        [bridge setRunning:YES];
    }
    [[MIAFXClock sharedClock] setPaused:NO];
}

- (void)stop {
    if (!self.running) {
        return;
    }
    self.running = NO;
    [self.compactStage setRunning:NO];
    [self.expandedStage setRunning:NO];
    for (MIAFXNativeElementBridge *bridge in self.nativeBridges) {
        [bridge setRunning:NO];
    }
    [[MIAFXClock sharedClock] setPaused:YES];
}

- (void)suspendForDisplayOff {
    if (self.suspended) {
        return;
    }
    self.suspended = YES;
    [self.compactStage setRunning:NO];
    [self.expandedStage setRunning:NO];
    [self.compactStage pausePlaybackOnly];
    [self.expandedStage pausePlaybackOnly];
    for (MIAFXNativeElementBridge *bridge in self.nativeBridges) {
        [bridge setRunning:NO];
    }
    [[MIAFXClock sharedClock] setPaused:YES];
    MIAFXLog(@"渲染已因屏幕状态挂起");
}

- (void)resumeFromDisplayOff {
    if (!self.suspended) {
        return;
    }
    self.suspended = NO;
    if (!self.running) {
        return;
    }
    [self.compactStage setRunning:YES];
    [self.expandedStage setRunning:YES];
    for (MIAFXNativeElementBridge *bridge in self.nativeBridges) {
        [bridge setRunning:YES];
    }
    [[MIAFXClock sharedClock] setPaused:NO];
    MIAFXLog(@"渲染已从挂起恢复");
}

#pragma mark - Tick

- (void)tick:(NSTimeInterval)timestamp delta:(NSTimeInterval)delta {
    if (!self.running || self.suspended) {
        return;
    }
    MIAFXRenderStage *stage = self.expanded ? self.expandedStage : self.compactStage;
    [stage tickWithTimestamp:timestamp delta:delta];

    for (MIAFXNativeElementBridge *bridge in self.nativeBridges) {
        [bridge tickWithTimestamp:timestamp delta:delta];
    }

    [stage applyRhythmTransform];
}

#pragma mark - Diagnostics

- (void)updateRuntimeDescription {
    MIAFXRenderStage *stage = self.expanded ? self.expandedStage : self.compactStage;
    NSMutableString *description = [NSMutableString string];
    [description appendFormat:@"expanded=%@ ", self.expanded ? @"YES" : @"NO"];
    [description appendFormat:@"bounds=%@ ", NSStringFromCGRect(self.hostBounds)];
    [description appendFormat:@"attached=%@ ", self.attached ? @"YES" : @"NO"];
    [description appendFormat:@"running=%@ ", self.running ? @"YES" : @"NO"];
    [description appendFormat:@"suspended=%@ ", self.suspended ? @"YES" : @"NO"];
    [description appendFormat:@"layerMode=%ld ", (long)self.layerMode];
    [description appendString:[stage runtimeDescription]];

    for (MIAFXNativeElementBridge *bridge in self.nativeBridges) {
        [description appendFormat:@" | %@:%@", bridge.configurationPrefix,
         bridge.matched ? (bridge.matchedClassName ?: @"?") : @"none"];
    }

    self.runtimeDescription = [description copy];
    [[MIAFXProbe sharedProbe] recordRuntimeStatus:description];
}

@end
