//
//  MIAFXVideoLayer.m
//  MIAFX
//

#import "MIAFXVideoLayer.h"

#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

#import "MIAFXConfig.h"
#import "MIAFXLog.h"
#import "MIAFXPath.h"
#import "MIAFXSafe.h"
#import "MIAFXSafeInline.h"

static NSString * _Nullable MIAFXVideoResolvedPath(NSString *rawPath) {
    if (rawPath.length == 0) {
        return nil;
    }
    NSString *trimmed = [rawPath stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *videosPrefix = @"Videos/";
    if ([trimmed hasPrefix:videosPrefix]) {
        trimmed = [trimmed substringFromIndex:videosPrefix.length];
    }
    trimmed = [trimmed stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
    if (trimmed.length == 0) {
        return nil;
    }
    if ([trimmed rangeOfString:@".."].location != NSNotFound) {
        MIAFXLog(@"视频路径包含非法片段，已忽略：%@", rawPath);
        return nil;
    }
    NSString *base = [MIAFXDataDirectory() stringByAppendingPathComponent:@"Videos"];
    return [base stringByAppendingPathComponent:trimmed];
}

static NSString *MIAFXVideoGravityForMode(MIAFXVideoFillMode mode) {
    switch (mode) {
        case MIAFXVideoFillModeAspectFill: return AVLayerVideoGravityResizeAspectFill;
        case MIAFXVideoFillModeStretch: return AVLayerVideoGravityResize;
        case MIAFXVideoFillModeAspectFit: return AVLayerVideoGravityResizeAspect;
    }
    return AVLayerVideoGravityResizeAspectFill;
}

static CGFloat MIAFXVideoClamp(CGFloat value, CGFloat low, CGFloat high) {
    if (!isfinite((double)value)) {
        return low;
    }
    return value < low ? low : (value > high ? high : value);
}

@interface MIAFXVideoLayer ()
@property (nonatomic, strong, readwrite) UIView *contentView;
@property (nonatomic, copy, readwrite) NSString *configurationPrefix;
@property (nonatomic, readwrite, getter=isEnabled) BOOL enabled;
@property (nonatomic, readwrite, getter=isPlaying) BOOL playing;
@property (nonatomic, readwrite) BOOL hasError;
@property (nonatomic, copy, readwrite) NSString *statusDescription;

@property (nonatomic, strong, nullable) AVQueuePlayer *queuePlayer;
@property (nonatomic, strong, nullable) AVPlayerLooper *playerLooper;
@property (nonatomic, strong, nullable) AVPlayerItem *templateItem;
@property (nonatomic, strong, nullable) AVPlayerLayer *playerLayer;

@property (nonatomic) MIAFXVideoFillMode fillMode;
@property (nonatomic) MIAFXVideoCornerMode cornerMode;
@property (nonatomic) CGFloat videoAlpha;
@property (nonatomic) CGFloat videoScale;
@property (nonatomic) CGFloat offsetX;
@property (nonatomic) CGFloat offsetY;
@property (nonatomic) CGFloat cornerRadius;
@property (nonatomic, copy, nullable) NSString *loadedPath;
/// 外部 -play 之后就算 detach / reload 也自动恢复播放
@property (nonatomic) BOOL shouldAutoplay;
@end

@implementation MIAFXVideoLayer

- (instancetype)initWithConfigurationPrefix:(NSString *)prefix {
    self = [super init];
    if (!self) {
        return nil;
    }
    _configurationPrefix = [prefix copy];
    _enabled = NO;
    _playing = NO;
    _hasError = NO;
    _statusDescription = @"idle";
    _fillMode = MIAFXVideoFillModeStretch;
    _cornerMode = MIAFXVideoCornerModeRadius;
    _videoAlpha = 1.0;
    _videoScale = 1.0;
    _offsetX = 0.0;
    _offsetY = 0.0;
    _cornerRadius = 0.0;

    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    view.backgroundColor = [UIColor clearColor];
    view.opaque = NO;
    view.userInteractionEnabled = NO;
    view.clipsToBounds = YES;
    _contentView = view;
    return self;
}

- (void)dealloc {
    [self detach];
}

#pragma mark - Configuration

- (void)reloadConfiguration {
    MIAFXRunProtected(@"VideoLayer", ^{
        MIAFXConfig *config = [MIAFXConfig sharedConfig];
        NSString *prefix = self.configurationPrefix;

        self.enabled = [config boolForKey:[prefix stringByAppendingString:@".Enabled"]];
        if (!self.enabled) {
            self.statusDescription = @"disabled";
            [self detach];
            self.contentView.hidden = YES;
            return;
        }

        NSString *rawPath = [config stringForKey:[prefix stringByAppendingString:@".Path"]];
        NSString *resolved = MIAFXVideoResolvedPath(rawPath);
        if (resolved.length == 0) {
            self.statusDescription = @"empty-path";
            [self detach];
            self.contentView.hidden = YES;
            return;
        }

        NSInteger fill = [config integerForKey:[prefix stringByAppendingString:@".FillMode"]];
        self.fillMode = (MIAFXVideoFillMode)MIAFXVideoClamp((CGFloat)fill, 0, 2);

        NSInteger corner = [config integerForKey:[prefix stringByAppendingString:@".CornerMode"]];
        self.cornerMode = (MIAFXVideoCornerMode)MIAFXVideoClamp((CGFloat)corner, 0, 2);

        self.videoAlpha = MIAFXVideoClamp([config doubleForKey:[prefix stringByAppendingString:@".Alpha"]], 0.0, 1.0);
        self.videoScale = MIAFXVideoClamp([config doubleForKey:[prefix stringByAppendingString:@".Scale"]], 0.05, 8.0);
        self.offsetX = MIAFXVideoClamp([config doubleForKey:[prefix stringByAppendingString:@".OffsetX"]], -2000.0, 2000.0);
        self.offsetY = MIAFXVideoClamp([config doubleForKey:[prefix stringByAppendingString:@".OffsetY"]], -2000.0, 2000.0);
        self.cornerRadius = MIAFXVideoClamp([config doubleForKey:[prefix stringByAppendingString:@".CornerRadius"]], 0.0, 500.0);

        if (self.loadedPath && [self.loadedPath isEqualToString:resolved] && !self.hasError) {
            // 资源没变，只需要刷新显示参数
            [self applyDisplayProperties];
            return;
        }

        [self detach];
        self.contentView.hidden = NO;
        [self loadResourceAtPath:resolved];
    });
}

- (void)applyDisplayProperties {
    self.playerLayer.videoGravity = MIAFXVideoGravityForMode(self.fillMode);
    self.contentView.alpha = self.videoAlpha;
    CGFloat radius = self.cornerRadius;
    if (self.cornerMode == MIAFXVideoCornerModeCapsule) {
        radius = CGRectGetHeight(self.contentView.bounds) * 0.5;
    } else if (self.cornerMode == MIAFXVideoCornerModeNone) {
        radius = 0.0;
    }
    self.contentView.layer.cornerRadius = radius;
    self.contentView.layer.masksToBounds = YES;
}

- (void)loadResourceAtPath:(NSString *)path {
    NSURL *url = [NSURL fileURLWithPath:path isDirectory:NO];
    BOOL reachable = [[NSFileManager defaultManager] fileExistsAtPath:path];
    if (!reachable) {
        self.hasError = YES;
        self.statusDescription = [NSString stringWithFormat:@"missing:%@", path.lastPathComponent];
        MIAFXLog(@"视频文件不存在：%@", path);
        return;
    }

    AVURLAsset *asset = [AVURLAsset assetWithURL:url];
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    if (!item) {
        self.hasError = YES;
        self.statusDescription = @"item-failed";
        return;
    }

    AVQueuePlayer *player = [AVQueuePlayer queuePlayerWithItems:@[item]];
    player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    player.muted = YES;

    AVPlayerLooper *looper = [AVPlayerLooper playerLooperWithPlayer:player templateItem:item];
    AVPlayerLayer *layer = [AVPlayerLayer playerLayerWithPlayer:player];

    self.queuePlayer = player;
    self.playerLooper = looper;
    self.templateItem = item;
    self.playerLayer = layer;
    self.loadedPath = [path copy];
    self.hasError = NO;
    self.statusDescription = @"loaded";

    [item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:NULL];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleItemFailedToPlayToEnd:)
                                                 name:AVPlayerItemFailedToPlayToEndTimeNotification
                                               object:item];

    layer.frame = self.contentView.bounds;
    layer.backgroundColor = [UIColor clearColor].CGColor;
    [self.contentView.layer addSublayer:layer];
    [self applyDisplayProperties];

    if (self.shouldAutoplay) {
        [player play];
        self.playing = YES;
    }
}

#pragma mark - Playback

- (void)play {
    MIAFXRunProtected(@"VideoLayer", ^{
        self.shouldAutoplay = YES;
        if (!self.enabled || self.hasError || !self.queuePlayer) {
            return;
        }
        self.contentView.hidden = NO;
        [self.queuePlayer play];
        self.playing = YES;
        self.statusDescription = @"playing";
    });
}

- (void)pause {
    MIAFXRunProtected(@"VideoLayer", ^{
        self.shouldAutoplay = NO;
        if (!self.queuePlayer) {
            return;
        }
        [self.queuePlayer pause];
        self.playing = NO;
        if (!self.hasError) {
            self.statusDescription = @"paused";
        }
    });
}

- (void)resume {
    MIAFXRunProtected(@"VideoLayer", ^{
        if (self.hasError) {
            // 出错后不再恢复循环，避免失败循环刷日志
            self.statusDescription = @"error-stopped";
            return;
        }
        [self play];
    });
}

- (void)detach {
    MIAFXRunProtected(@"VideoLayer", ^{
        AVPlayerItem *item = self.templateItem;
        if (item) {
            @try {
                [item removeObserver:self forKeyPath:@"status"];
            } @catch (NSException *exception) {
                // 已经移除过，忽略
            }
            [[NSNotificationCenter defaultCenter] removeObserver:self
                                                            name:AVPlayerItemFailedToPlayToEndTimeNotification
                                                          object:item];
        }
        // disableLooping 是只读属性，只能通过释放 AVPlayerLooper 来停止循环，
        // 下面 self.playerLooper = nil 已经完成这件事。
        if (self.queuePlayer) {
            [self.queuePlayer pause];
            [self.queuePlayer removeAllItems];
        }
        if (self.playerLayer) {
            [self.playerLayer removeFromSuperlayer];
        }
        self.playerLayer = nil;
        self.playerLooper = nil;
        self.queuePlayer = nil;
        self.templateItem = nil;
        self.loadedPath = nil;
        self.playing = NO;
    });
}

#pragma mark - Observation

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
    (void)change;
    (void)context;
    if (![keyPath isEqualToString:@"status"]) {
        return;
    }
    if (![object isKindOfClass:AVPlayerItem.class]) {
        return;
    }
    AVPlayerItem *item = (AVPlayerItem *)object;
    if (item.status == AVPlayerItemStatusFailed) {
        self.hasError = YES;
        self.playing = NO;
        self.playerLooper = nil;  /* 释放 looper 即停止循环 */
        [self.queuePlayer pause];
        self.statusDescription = @"failed";
        MIAFXLog(@"视频加载失败：%@", item.error.localizedDescription ?: @"unknown");
    } else if (item.status == AVPlayerItemStatusReadyToPlay) {
        self.hasError = NO;
        if (self.shouldAutoplay && self.queuePlayer) {
            [self.queuePlayer play];
            self.playing = YES;
            self.statusDescription = @"playing";
        }
    }
}

- (void)handleItemFailedToPlayToEnd:(NSNotification *)notification {
    (void)notification;
    self.hasError = YES;
    self.playing = NO;
    self.playerLooper = nil;  /* 释放 looper 即停止循环 */
    [self.queuePlayer pause];
    self.statusDescription = @"failed";
}

#pragma mark - Layout

- (void)layoutInBounds:(CGRect)bounds {
    MIAFXRunProtected(@"VideoLayer", ^{
        if (CGRectIsEmpty(bounds) || !isfinite((double)bounds.origin.x) || !isfinite((double)bounds.size.width)) {
            return;
        }
        CGFloat scale = self.videoScale;
        CGFloat extraWidth = bounds.size.width * (scale - 1.0);
        CGFloat extraHeight = bounds.size.height * (scale - 1.0);
        CGRect frame = CGRectInset(bounds, -extraWidth * 0.5, -extraHeight * 0.5);
        frame.origin.x += self.offsetX;
        frame.origin.y += self.offsetY;

        self.contentView.frame = frame;
        self.contentView.bounds = CGRectMake(0.0, 0.0, frame.size.width, frame.size.height);
        self.contentView.layer.anchorPoint = CGPointMake(0.5, 0.5);

        self.playerLayer.frame = self.contentView.bounds;
        [self applyDisplayProperties];
    });
}

@end
