//
//  LOGXVideoBackground.m
//  LogeIsland — 落格Loge·灵动岛 v2.0
//
//  视频背景：在 SpringBoard 灵动岛渲染表面 _SPIslandRenderSurface 上播放
//  用户选择的背景视频。紧凑/展开两态独立配置（启用/路径/填充/透明度/
//  缩放/偏移/圆角），配置经 CFPreferences 跨进程域读取。
//
//  设计取舍（v2.0 重做，只保留背景视频一个功能）：
//   - 不持有任何跨 trigger 的 CFPreferences 缓存超过 0.5 秒，保证设置端
//     改动最多 0.5 秒 + 一次 trigger 内生效；
//   - 图层挂载三级兜底：系统 _playerLayer → 自建写入 ivar → 纯子图层；
//   - 所有几何/外观参数随每次 trigger 刷新，展开动画期间自动跟随。
//

#import "LOGXVideoBackground.h"

#import "LOGXConfig.h"
#import "LOGXConstants.h"
#import "LOGXLog.h"
#import "LOGXPath.h"

#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

@interface _SPIslandRenderSurface : UIView
@end

/// 运行时查找灵动岛渲染表面类（2.0.11）：私有类不在任何 SDK 里，
/// 且 dylib 注入时该类可能尚未注册，不能用编译期符号引用
///（那会迫使链接器加 -undefined dynamic_lookup，进而禁用 chained fixups，
/// 弄丢 arm64e 类指针的 PAC 签名）。类不存在时返回 Nil，调用方需判空。
static Class LOGXSurfaceClass(void) {
    static Class cls;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ cls = objc_getClass("_SPIslandRenderSurface"); });
    return cls;
}

@interface LOGXVideoBackground ()
@property (nonatomic, weak) UIView *surface;
@property (nonatomic, strong) AVPlayerLayer *layer;
@property (nonatomic, strong) AVQueuePlayer *player;
@property (nonatomic, strong) AVPlayerLooper *looper;
@property (nonatomic, copy, nullable) NSString *loadedPath;
@property (nonatomic, copy) NSString *activePrefix;
@property (nonatomic) BOOL needsSync;
@property (nonatomic) double presentationRadius;
@property (nonatomic) CGSize presentationSize;
@property (nonatomic) NSTimeInterval lastEvaluation;
@property (nonatomic) NSTimeInterval lastLog;
@end

@implementation LOGXVideoBackground

static const void *kLOGXVideoBackgroundKey = &kLOGXVideoBackgroundKey;
static const NSTimeInterval kLOGXVideoEvalInterval = 0.4;    // 评估节流
static const NSTimeInterval kLOGXVideoLogInterval = 2.0;     // 日志节流
static const NSTimeInterval kLOGXConfigCacheInterval = 0.5;  // 配置快照节流
static const double kLOGXExpandedWidthThreshold = 220.0;     // 展开态宽度阈值

#pragma mark - 已知 surface 弱表 + 配置快照

static NSHashTable *_LOGXKnownSurfaces(void) {
    static NSHashTable *table;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ table = [NSHashTable weakObjectsHashTable]; });
    return table;
}

static NSDictionary<NSString *, id> *s_configSnapshot = nil;
static NSTimeInterval s_configSnapshotAt = 0;

+ (void)invalidateConfigCache {
    s_configSnapshotAt = 0;
}

/// 读取一份配置快照（带默认值），0.5 秒内重复调用直接复用。
/// 快照过期时先 CFPreferencesAppSynchronize 一次——把设置端（另一进程）
/// 写入的值拉进来，否则只会读到本进程的旧缓存。
+ (NSDictionary<NSString *, id> *)configSnapshot {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (s_configSnapshot != nil && (now - s_configSnapshotAt) < kLOGXConfigCacheInterval) {
        return s_configSnapshot;
    }
    LOGXPrefsSynchronize();
    NSMutableDictionary<NSString *, id> *snapshot = [NSMutableDictionary dictionary];
    snapshot[LOGX_KEY_ENABLED] = @(LOGXConfigBool(LOGX_KEY_ENABLED));
    for (NSString *mode in @[LOGX_MODE_COMPACT, LOGX_MODE_EXPANDED]) {
        snapshot[LOGXModeKey(LOGX_KEY_MODE_ENABLED_FMT, mode)] = @(LOGXConfigBool(LOGXModeKey(LOGX_KEY_MODE_ENABLED_FMT, mode)));
        snapshot[LOGXModeKey(LOGX_KEY_MODE_PATH_FMT, mode)] = LOGXConfigString(LOGXModeKey(LOGX_KEY_MODE_PATH_FMT, mode));
        snapshot[LOGXModeKey(LOGX_KEY_MODE_FILL_FMT, mode)] = @(LOGXConfigInteger(LOGXModeKey(LOGX_KEY_MODE_FILL_FMT, mode)));
        snapshot[LOGXModeKey(LOGX_KEY_MODE_ALPHA_FMT, mode)] = @(LOGXConfigDouble(LOGXModeKey(LOGX_KEY_MODE_ALPHA_FMT, mode)));
        snapshot[LOGXModeKey(LOGX_KEY_MODE_SCALE_FMT, mode)] = @(LOGXConfigDouble(LOGXModeKey(LOGX_KEY_MODE_SCALE_FMT, mode)));
        snapshot[LOGXModeKey(LOGX_KEY_MODE_OFFSETX_FMT, mode)] = @(LOGXConfigDouble(LOGXModeKey(LOGX_KEY_MODE_OFFSETX_FMT, mode)));
        snapshot[LOGXModeKey(LOGX_KEY_MODE_OFFSETY_FMT, mode)] = @(LOGXConfigDouble(LOGXModeKey(LOGX_KEY_MODE_OFFSETY_FMT, mode)));
        snapshot[LOGXModeKey(LOGX_KEY_MODE_CORNER_FMT, mode)] = @(LOGXConfigInteger(LOGXModeKey(LOGX_KEY_MODE_CORNER_FMT, mode)));
        snapshot[LOGXModeKey(LOGX_KEY_MODE_RADIUS_FMT, mode)] = @(LOGXConfigDouble(LOGXModeKey(LOGX_KEY_MODE_RADIUS_FMT, mode)));
    }
    s_configSnapshot = snapshot;
    s_configSnapshotAt = now;
    return snapshot;
}

+ (void)triggerAll:(NSString *)reason {
    for (id surface in [_LOGXKnownSurfaces() copy]) {
        if (LOGXSurfaceClass() == Nil || ![surface isKindOfClass:LOGXSurfaceClass()]) continue;
        @autoreleasepool {
            [[LOGXVideoBackground backgroundForSurface:surface] handleTrigger:reason];
        }
    }
}

+ (void)stopAll {
    for (id surface in [_LOGXKnownSurfaces() copy]) {
        if (LOGXSurfaceClass() == Nil || ![surface isKindOfClass:LOGXSurfaceClass()]) continue;
        @autoreleasepool {
            [[LOGXVideoBackground backgroundForSurface:surface] stop];
        }
    }
}

+ (void)suspendAll {
    for (id surface in [_LOGXKnownSurfaces() copy]) {
        if (LOGXSurfaceClass() == Nil || ![surface isKindOfClass:LOGXSurfaceClass()]) continue;
        @autoreleasepool {
            LOGXVideoBackground *background = [LOGXVideoBackground backgroundForSurface:surface];
            [background stop];
            background.layer.hidden = YES;   // 双保险：连最后一帧也不留
        }
    }
    LOGXDiag(@"注销前置：已停止全部视频渲染");
}

+ (LOGXVideoBackground *)backgroundForSurface:(UIView *)surface {
    LOGXVideoBackground *background = objc_getAssociatedObject(surface, kLOGXVideoBackgroundKey);
    if (background == nil) {
        background = [[LOGXVideoBackground alloc] init];
        objc_setAssociatedObject(surface, kLOGXVideoBackgroundKey, background, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LOGXDiag(@"新 surface=%p class=%@", surface, NSStringFromClass(surface.class));
    }
    background.surface = surface;
    [_LOGXKnownSurfaces() addObject:surface];
    return background;
}

#pragma mark - 诊断日志（节流）

- (void)diagNow:(NSString *)message {
    self.lastLog = [NSDate timeIntervalSinceReferenceDate];
    LOGXDiag(@"%@", message);
}

- (void)diag:(NSString *)message {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - self.lastLog < kLOGXVideoLogInterval) return;
    self.lastLog = now;
    LOGXDiag(@"%@", message);
}

#pragma mark - 状态与目标解析

- (BOOL)isExpanded {
    if (self.surface != NULL && self.surface.bounds.size.width > 0) {
        return self.surface.bounds.size.width >= kLOGXExpandedWidthThreshold;
    }
    return self.presentationSize.width >= kLOGXExpandedWidthThreshold;
}

- (NSString *)configPrefix {
    return [self isExpanded] ? LOGX_MODE_EXPANDED : LOGX_MODE_COMPACT;
}

/// 解析目标视频路径：只存文件名，落在真实 Videos 目录；旧版绝对路径仍然兼容
- (NSString *)resolvedTargetPath:(NSString **)reason {
    NSDictionary *config = [LOGXVideoBackground configSnapshot];
    if (![config[LOGX_KEY_ENABLED] boolValue]) {
        if (reason) *reason = @"总开关未开启";
        return nil;
    }
    NSString *prefix = [self configPrefix];
    self.activePrefix = prefix;
    if (![config[LOGXModeKey(LOGX_KEY_MODE_ENABLED_FMT, prefix)] boolValue]) {
        if (reason) *reason = [prefix isEqualToString:LOGX_MODE_EXPANDED] ? @"展开背景未启用" : @"紧凑背景未启用";
        return nil;
    }
    NSString *raw = config[LOGXModeKey(LOGX_KEY_MODE_PATH_FMT, prefix)];
    if (![raw isKindOfClass:NSString.class] || raw.length == 0) {
        if (reason) *reason = @"未选择视频文件";
        return nil;
    }

    NSFileManager *manager = NSFileManager.defaultManager;
    // 1) 绝对路径直接可用（含真实 /var/jb 路径）
    if ([raw hasPrefix:@"/"] && [manager fileExistsAtPath:raw]) {
        if (reason) *reason = nil;
        return raw;
    }
    // 2) 视为文件名，解析到真实 Videos 目录
    NSString *candidate = [LOGXVideosDirectory() stringByAppendingPathComponent:raw.lastPathComponent];
    if ([manager fileExistsAtPath:candidate]) {
        if (reason) *reason = nil;
        return candidate;
    }
    if (reason) *reason = [NSString stringWithFormat:@"视频文件不存在：%@（已试 %@）", raw, candidate];
    return nil;
}

#pragma mark - 图层挂载

/// 沿继承链查找 ivar（系统类的 _playerLayer 可能声明在父类）
static Ivar LOGXFindIvar(Class cls, const char *name) {
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

    Ivar ivar = LOGXFindIvar(surface.class, "_playerLayer");
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

    if (ivar != NULL) {
        AVPlayerLayer *layer = [AVPlayerLayer layer];
        object_setIvar(surface, ivar, layer);
        [surface.layer insertSublayer:layer atIndex:0];
        self.layer = layer;
        [self diagNow:[NSString stringWithFormat:@"_playerLayer 为空，已自建 AVPlayerLayer 写入 ivar（surface=%p）", surface]];
        return layer;
    }

    AVPlayerLayer *layer = [AVPlayerLayer layer];
    [surface.layer insertSublayer:layer atIndex:0];
    self.layer = layer;
    [self diagNow:[NSString stringWithFormat:@"类 %@ 无 _playerLayer ivar，已作为子图层插入 index 0", NSStringFromClass(surface.class)]];
    return layer;
}

#pragma mark - 几何 / 外观

- (void)updateGeometry {
    if (self.layer == NULL || self.surface == NULL) return;
    NSDictionary *config = [LOGXVideoBackground configSnapshot];
    NSString *prefix = self.activePrefix.length > 0 ? self.activePrefix : [self configPrefix];

    CGRect bounds = self.surface.bounds;
    if (bounds.size.width <= 0.0 || bounds.size.height <= 0.0) {
        if (self.presentationSize.width > 0.0 && self.presentationSize.height > 0.0) {
            bounds = (CGRect){CGPointZero, self.presentationSize};
        } else {
            return;
        }
    }

    double scale = [config[LOGXModeKey(LOGX_KEY_MODE_SCALE_FMT, prefix)] doubleValue];
    double offsetX = [config[LOGXModeKey(LOGX_KEY_MODE_OFFSETX_FMT, prefix)] doubleValue];
    double offsetY = [config[LOGXModeKey(LOGX_KEY_MODE_OFFSETY_FMT, prefix)] doubleValue];
    double alpha = [config[LOGXModeKey(LOGX_KEY_MODE_ALPHA_FMT, prefix)] doubleValue];
    NSInteger fill = [config[LOGXModeKey(LOGX_KEY_MODE_FILL_FMT, prefix)] integerValue];
    NSInteger cornerMode = [config[LOGXModeKey(LOGX_KEY_MODE_CORNER_FMT, prefix)] integerValue];
    double customRadius = [config[LOGXModeKey(LOGX_KEY_MODE_RADIUS_FMT, prefix)] doubleValue];

    if (scale <= 0.05) scale = 1.0;
    if (alpha < 0.05) alpha = 0.05;
    if (alpha > 1.0) alpha = 1.0;

    CGSize size = CGSizeMake(bounds.size.width * scale, bounds.size.height * scale);
    CGPoint origin = CGPointMake((bounds.size.width - size.width) / 2.0 + offsetX,
                                 (bounds.size.height - size.height) / 2.0 + offsetY);
    self.layer.frame = (CGRect){origin, size};
    self.layer.opacity = (float)alpha;
    self.layer.videoGravity = (fill == 0) ? AVLayerVideoGravityResizeAspect      // 适应
                         : (fill == 2) ? AVLayerVideoGravityResize              // 拉伸
                         : AVLayerVideoGravityResizeAspectFill;                 // 填充

    double radius = 0.0;
    if (cornerMode == 1) {
        radius = (self.presentationRadius > 0.0) ? self.presentationRadius
                 : MIN(size.width, size.height) / 2.0;
    } else if (cornerMode == 2) {
        radius = customRadius;
    }
    if (radius < 0.0) radius = 0.0;
    self.layer.cornerRadius = radius;
    self.layer.masksToBounds = YES;
}

#pragma mark - 同步主逻辑

- (void)handleTrigger:(NSString *)reason {
    if (self.surface == NULL) return;
    if (reason.length > 0) {
        [self diag:[NSString stringWithFormat:@"触发[%@] surface=%p bounds=%@", reason, self.surface, NSStringFromCGRect(self.surface.bounds)]];
    }
    if (self.layer != NULL) [self updateGeometry];
    [self syncIfNeeded];
}

- (void)syncIfNeeded {
    if (self.surface == NULL) return;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (!self.needsSync && (now - self.lastEvaluation) < kLOGXVideoEvalInterval) return;
    self.needsSync = NO;
    self.lastEvaluation = now;

    NSString *reason = nil;
    NSString *path = [self resolvedTargetPath:&reason];

    if (path == nil) {
        if (self.player != NULL) {
            [self diagNow:[NSString stringWithFormat:@"视频背景停止：%@", reason ?: @"未知原因"]];
            [self stop];
        } else if (reason.length > 0) {
            [self diag:[NSString stringWithFormat:@"视频背景未播放：%@", reason]];
        }
        return;
    }

    // 同一状态位下已加载同一文件：只修几何，必要时恢复播放
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
        self.needsSync = YES;
        self.lastEvaluation = now - kLOGXVideoEvalInterval;
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

    [self diagNow:[NSString stringWithFormat:@"视频背景已挂载[%@]：%@ frame=%@ radius=%.1f gravity=%ld",
                   self.activePrefix, path.lastPathComponent, NSStringFromCGRect(layer.frame),
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
