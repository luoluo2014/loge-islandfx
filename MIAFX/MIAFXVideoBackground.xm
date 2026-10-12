//
//  MIAFXVideoBackground.xm
//  MIAFX
//
//  视频背景：hook SpringBoard 灵动岛渲染表面 _SPIslandRenderSurface，
//  在系统原生 _playerLayer（AVPlayerLayer）上播放用户选择的背景视频。
//
//  触发策略（完整对齐 DynamicFX 的触发面）：
//   - _sp_set_render_visible:        岛显示/隐藏；
//   - setLastPresentationRadius:     尺寸/圆角变化（同时记录半径供裁切用）；
//   - setLastPresentationSize:       尺寸变化；
//   - layoutSubviews                 每次布局（岛出现/移动/改大小必经）；
//   - _sp_display_tick:              每帧刷新（动画期间持续保活）。
//   任一触发都走节流评估（默认 0.4s），避免每帧读配置/stat 文件。
//
//  挂载时的关键动作（1.2.x 无效的根因）：
//   - 系统 _playerLayer 可能已存在但 hidden / 不在层树 / frame 为零，
//     这里强制：入层树（index 0，压在黑色底色之上、岛内容之下）、hidden=NO、
//     按 bounds/缩放/偏移设置 frame、按圆角模式设置 cornerRadius。
//   - 若 ivar 为空但类声明了该 ivar：自建 AVPlayerLayer 写入 ivar 并插入层树；
//   - 若类根本没有该 ivar：退化为普通子图层。
//
//  诊断：所有关键步骤写入 Logs/video-diag.log（常开，512KB 轮转），
//  同时走 os_log（Console / idevicesyslog 可见）。排障时让用户发这个文件即可。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

#import "MIAFXConfig.h"
#import "MIAFXConstants.h"
#import "MIAFXPath.h"
#import "MIAFXLog.h"

@interface _SPIslandRenderSurface : UIView
@end

static const void *kMIAFXVideoBackgroundKey = &kMIAFXVideoBackgroundKey;
static const NSTimeInterval kMIAFXVideoEvalInterval = 0.4;   // 评估节流
static const NSTimeInterval kMIAFXVideoLogInterval = 2.0;    // 日志节流

@interface MIAFXVideoBackground : NSObject
@property (nonatomic, weak) UIView *surface;
@property (nonatomic, strong) AVPlayerLayer *layer;          // 当前承载视频的 layer（系统的或自建的）
@property (nonatomic, strong) AVQueuePlayer *player;
@property (nonatomic, strong) AVPlayerLooper *looper;
@property (nonatomic, copy, nullable) NSString *loadedPath;
@property (nonatomic) BOOL needsSync;
@property (nonatomic) double presentationRadius;
@property (nonatomic) CGSize presentationSize;
@property (nonatomic) NSTimeInterval lastEvaluation;
@property (nonatomic) NSTimeInterval lastLog;
@end

@implementation MIAFXVideoBackground

+ (MIAFXVideoBackground *)backgroundForSurface:(UIView *)surface {
    MIAFXVideoBackground *background = objc_getAssociatedObject(surface, kMIAFXVideoBackgroundKey);
    if (background == nil) {
        background = [[MIAFXVideoBackground alloc] init];
        objc_setAssociatedObject(surface, kMIAFXVideoBackgroundKey, background, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        MIAFXDiag(@"新 surface=%p class=%@", surface, NSStringFromClass([surface class]));
    }
    background.surface = surface;
    return background;
}

#pragma mark - 诊断日志

- (void)diagNow:(NSString *)message {
    self.lastLog = [NSDate timeIntervalSinceReferenceDate];
    MIAFXDiag(@"%@", message);
}

- (void)diag:(NSString *)message {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - self.lastLog < kMIAFXVideoLogInterval) return;
    self.lastLog = now;
    MIAFXDiag(@"%@", message);
}

#pragma mark - 配置解析

- (BOOL)isExpanded {
    if (self.surface != NULL && self.surface.bounds.size.width > 0) {
        return self.surface.bounds.size.width >= 220.0;
    }
    return self.presentationSize.width >= 220.0;
}

- (NSString *)configPrefix {
    return [self isExpanded] ? @"Expanded.Video" : @"Compact.Video";
}

/// 解析目标视频路径；返回 nil 时 reason 说明为什么没启用
- (NSString *)resolvedTargetPath:(NSString **)reason {
    MIAFXConfig *config = [MIAFXConfig sharedConfig];
    if (![config boolForKey:@"Global.Enabled"]) {
        if (reason) *reason = @"全局开关未开启";
        return nil;
    }
    if (![config isFeatureEnabled:MIAFXFeatureVideo]) {
        if (reason) *reason = @"全局「视频层」功能位未开启";
        return nil;
    }
    NSString *prefix = [self configPrefix];
    if (![config boolForKey:[prefix stringByAppendingString:@".Enabled"]]) {
        if (reason) *reason = [NSString stringWithFormat:@"%@ 未启用", [self isExpanded] ? @"展开背景" : @"紧凑背景"];
        return nil;
    }
    NSString *path = [config stringForKey:[prefix stringByAppendingString:@".Path"]];
    if (path.length == 0) {
        if (reason) *reason = @"未选择视频文件";
        return nil;
    }
    NSString *resolved = [path hasPrefix:@"/"] ? path : MIAFXRootPath(path);
    if (![[NSFileManager defaultManager] fileExistsAtPath:resolved]) {
        if (reason) *reason = [NSString stringWithFormat:@"视频文件不存在：%@", resolved];
        return nil;
    }
    if (reason) *reason = nil;
    return resolved;
}

#pragma mark - 图层挂载

/// 沿继承链查找 ivar（系统类的 _playerLayer 可能声明在父类）
static Ivar MIAFXFindIvar(Class cls, const char *name) {
    while (cls != NULL) {
        Ivar ivar = class_getInstanceVariable(cls, name);
        if (ivar != NULL) return ivar;
        cls = class_getSuperclass(cls);
    }
    return NULL;
}

- (AVPlayerLayer *)attachPlayerLayer {
    UIView *surface = self.surface;
    if (surface == NULL) return nil;

    Ivar ivar = MIAFXFindIvar([surface class], "_playerLayer");
    id existing = (ivar != NULL) ? object_getIvar(surface, ivar) : nil;
    if (![existing isKindOfClass:AVPlayerLayer.class]) {
        @try {
            existing = [surface valueForKey:@"_playerLayer"];
        } @catch (NSException *exception) {
            (void)exception;
            existing = nil;
        }
    }

    if ([existing isKindOfClass:AVPlayerLayer.class]) {
        AVPlayerLayer *layer = (AVPlayerLayer *)existing;
        if (layer.superlayer == NULL) {
            [surface.layer insertSublayer:layer atIndex:0];
            [self diagNow:[NSString stringWithFormat:@"系统 _playerLayer 不在层树，已插入 index 0（surface=%p）", surface]];
        }
        if (layer.hidden) {
            layer.hidden = NO;
            [self diagNow:@"系统 _playerLayer 原为 hidden，已取消隐藏"];
        }
        self.layer = layer;
        return layer;
    }

    // ivar 存在但为空：自建 layer 写入 ivar，让系统后续 layout 时也能管到它
    if (ivar != NULL) {
        AVPlayerLayer *layer = [AVPlayerLayer layer];
        object_setIvar(surface, ivar, layer);
        [surface.layer insertSublayer:layer atIndex:0];
        self.layer = layer;
        [self diagNow:[NSString stringWithFormat:@"_playerLayer 为空，已自建 AVPlayerLayer 写入 ivar 并插入层树（surface=%p）", surface]];
        return layer;
    }

    // 类根本没有该 ivar：退化为普通子图层
    AVPlayerLayer *layer = [AVPlayerLayer layer];
    [surface.layer insertSublayer:layer atIndex:0];
    self.layer = layer;
    [self diagNow:[NSString stringWithFormat:@"类 %@ 无 _playerLayer ivar，已作为子图层插入 index 0", NSStringFromClass([surface class])]];
    return layer;
}

#pragma mark - 几何 / 外观

- (void)updateGeometry {
    if (self.layer == NULL || self.surface == NULL) return;
    MIAFXConfig *config = [MIAFXConfig sharedConfig];
    NSString *prefix = [self configPrefix];

    CGRect bounds = self.surface.bounds;
    if (bounds.size.width <= 0.0 || bounds.size.height <= 0.0) {
        if (self.presentationSize.width > 0.0 && self.presentationSize.height > 0.0) {
            bounds = (CGRect){CGPointZero, self.presentationSize};
        } else {
            return;
        }
    }

    double scale = [config doubleForKey:[prefix stringByAppendingString:@".Scale"]];
    double offsetX = [config doubleForKey:[prefix stringByAppendingString:@".OffsetX"]];
    double offsetY = [config doubleForKey:[prefix stringByAppendingString:@".OffsetY"]];
    double alpha = [config doubleForKey:[prefix stringByAppendingString:@".Alpha"]];
    NSInteger fill = [config integerForKey:[prefix stringByAppendingString:@".FillMode"]];
    NSInteger cornerMode = [config integerForKey:[prefix stringByAppendingString:@".CornerMode"]];
    double customRadius = [config doubleForKey:[prefix stringByAppendingString:@".CornerRadius"]];

    if (scale <= 0.0) scale = 1.0;
    CGSize size = CGSizeMake(bounds.size.width * scale, bounds.size.height * scale);
    CGPoint origin = CGPointMake((bounds.size.width - size.width) / 2.0 + offsetX,
                                 (bounds.size.height - size.height) / 2.0 + offsetY);
    self.layer.frame = (CGRect){origin, size};
    self.layer.opacity = (float)alpha;
    self.layer.videoGravity = (fill == 0) ? AVLayerVideoGravityResize
                         : (fill == 2) ? AVLayerVideoGravityResizeAspect
                         : AVLayerVideoGravityResizeAspectFill;

    double radius = 0.0;
    if (cornerMode == 1) {
        radius = (self.presentationRadius > 0.0) ? self.presentationRadius
                 : MIN(size.width, size.height) / 2.0;
    } else if (cornerMode == 2) {
        radius = customRadius;
    }
    self.layer.cornerRadius = radius;
    self.layer.masksToBounds = YES;
}

#pragma mark - 同步主逻辑

- (void)handleTrigger:(NSString *)reason {
    if (self.surface == NULL) return;
    if (reason.length > 0) [self diag:[NSString stringWithFormat:@"触发[%@] surface=%p bounds=%@", reason, self.surface, NSStringFromCGRect(self.surface.bounds)]];
    if (self.layer != NULL) [self updateGeometry];
    [self syncIfNeeded];
}

- (void)syncIfNeeded {
    if (self.surface == NULL) return;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (!self.needsSync && (now - self.lastEvaluation) < kMIAFXVideoEvalInterval) return;
    self.needsSync = NO;
    self.lastEvaluation = now;

    NSString *reason = nil;
    NSString *path = [self resolvedTargetPath:&reason];

    if (path == nil) {
        if (self.player != NULL) {
            [self diagNow:[NSString stringWithFormat:@"视频背景停止：%@", reason ?: @"未知原因"]];
            [self stop];
        } else if (reason.length > 0) {
            // 同一原因只立即记一次，之后交给节流日志
            [self diagNow:[NSString stringWithFormat:@"视频背景未播放：%@", reason]];
        }
        return;
    }

    if ([path isEqualToString:self.loadedPath] && self.player != NULL) {
        [self updateGeometry];
        if (self.player.rate == 0.0) {
            [self.player play];
            [self diagNow:[NSString stringWithFormat:@"恢复播放 %@", path.lastPathComponent]];
        }
        return;
    }

    AVPlayerLayer *layer = [self attachPlayerLayer];
    if (layer == NULL) {
        // layer 暂不可用，下次触发立即重试
        self.needsSync = YES;
        self.lastEvaluation = now - kMIAFXVideoEvalInterval;
        return;
    }

    [self stop];

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:path]];
    self.player = [AVQueuePlayer queuePlayerWithItems:@[item]];
    self.player.muted = YES;
    self.looper = [AVPlayerLooper playerLooperWithPlayer:self.player templateItem:item];
    layer.player = self.player;
    layer.hidden = NO;
    [self updateGeometry];
    self.loadedPath = path;
    [self.player play];

    [self diagNow:[NSString stringWithFormat:@"视频背景已挂载：%@ layer=%p frame=%@ radius=%.1f gravity=%ld",
                   path.lastPathComponent, layer, NSStringFromCGRect(layer.frame),
                   layer.cornerRadius, (long)layer.videoGravity]];
}

- (void)stop {
    if (self.layer != NULL && self.layer.player == self.player) {
        self.layer.player = nil;
    }
    if (self.player != NULL) {
        [self.player pause];
        self.player = nil;
    }
    self.looper = nil;
    self.loadedPath = nil;
    self.needsSync = NO;
}

- (void)dealloc {
    [self stop];
}

@end

%hook _SPIslandRenderSurface

- (void)_sp_set_render_visible:(BOOL)visible {
    %orig;
    MIAFXVideoBackground *background = [MIAFXVideoBackground backgroundForSurface:self];
    if (visible) {
        [background handleTrigger:@"岛显示"];
    } else {
        [background stop];
        MIAFXDiag(@"岛隐藏，视频背景停止（surface=%p）", self);
    }
}

- (void)_sp_display_tick:(id)tick {
    %orig;
    [[MIAFXVideoBackground backgroundForSurface:self] handleTrigger:@"display_tick"];
}

- (void)setLastPresentationRadius:(double)radius {
    %orig;
    MIAFXVideoBackground *background = [MIAFXVideoBackground backgroundForSurface:self];
    background.presentationRadius = radius;
    [background handleTrigger:[NSString stringWithFormat:@"radius=%.1f", radius]];
}

- (void)setLastPresentationSize:(CGSize)size {
    %orig;
    MIAFXVideoBackground *background = [MIAFXVideoBackground backgroundForSurface:self];
    background.presentationSize = size;
    [background handleTrigger:[NSString stringWithFormat:@"size=%@@", NSStringFromCGSize(size)]];
}

- (void)layoutSubviews {
    %orig;
    [[MIAFXVideoBackground backgroundForSurface:self] handleTrigger:@"layoutSubviews"];
}

%end
