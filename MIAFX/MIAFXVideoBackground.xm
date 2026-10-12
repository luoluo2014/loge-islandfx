//
//  MIAFXVideoBackground.xm
//  MIAFX
//
//  视频背景：hook SpringBoard 的灵动岛渲染表面 _SPIslandRenderSurface，
//  复用系统原生 _playerLayer（AVPlayerLayer）播放用户选择的背景视频。
//
//  触发策略（对齐 DynamicFX）：
//   - _sp_set_render_visible: 岛显示/隐藏时打标记；
//   - setLastPresentationRadius: 尺寸变化（紧凑/展开切换）时打标记；
//   - _sp_display_tick: 每帧节流检查，只在有标记且 _playerLayer 已就绪时装载一次。
//   这样既能在正确时机挂载，又不会每帧重复创建 player 造成卡顿与耗电。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

#import "MIAFXConfig.h"
#import "MIAFXConstants.h"
#import "MIAFXPath.h"

@interface _SPIslandRenderSurface : UIView
@end

static const void *kMIAFXVideoBackgroundKey = &kMIAFXVideoBackgroundKey;

@interface MIAFXVideoBackground : NSObject
@property (nonatomic, weak) UIView *surface;
@property (nonatomic, strong) AVQueuePlayer *player;
@property (nonatomic, strong) AVPlayerLooper *looper;
@property (nonatomic, copy, nullable) NSString *loadedPath;
@property (nonatomic) BOOL needsSync;
- (void)markNeedsSync;
- (void)sync;
- (void)stop;
@end

@implementation MIAFXVideoBackground

+ (MIAFXVideoBackground *)backgroundForSurface:(UIView *)surface {
    MIAFXVideoBackground *background = objc_getAssociatedObject(surface, kMIAFXVideoBackgroundKey);
    if (background == nil) {
        background = [[MIAFXVideoBackground alloc] init];
        objc_setAssociatedObject(surface, kMIAFXVideoBackgroundKey, background, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    background.surface = surface;
    return background;
}

/// 沿继承链查找 ivar（系统类的 _playerLayer 可能声明在父类）
static Ivar MIAFXFindIvar(Class cls, const char *name) {
    while (cls != NULL) {
        Ivar ivar = class_getInstanceVariable(cls, name);
        if (ivar != NULL) return ivar;
        cls = class_getSuperclass(cls);
    }
    return NULL;
}

static AVPlayerLayer *MIAFXPlayerLayerOfSurface(UIView *surface) {
    Ivar ivar = MIAFXFindIvar([surface class], "_playerLayer");
    if (ivar != NULL) {
        id layer = object_getIvar(surface, ivar);
        if ([layer isKindOfClass:[AVPlayerLayer class]]) return (AVPlayerLayer *)layer;
    }
    // KVC 兜底（KVC 会沿继承链查找）
    id layer = [surface valueForKey:@"_playerLayer"];
    return [layer isKindOfClass:[AVPlayerLayer class]] ? (AVPlayerLayer *)layer : nil;
}

- (NSString *)targetPath {
    MIAFXConfig *config = [MIAFXConfig sharedConfig];
    if (![config boolForKey:@"Global.Enabled"]) return nil;
    if (![config isFeatureEnabled:MIAFXFeatureVideo]) return nil;

    BOOL expanded = self.surface.bounds.size.width >= 220.0;
    NSString *prefix = expanded ? @"Expanded.Video" : @"Compact.Video";
    if (![config boolForKey:[prefix stringByAppendingString:@".Enabled"]]) return nil;

    NSString *path = [config stringForKey:[prefix stringByAppendingString:@".Path"]];
    if (path.length == 0) return nil;
    NSString *resolved = [path hasPrefix:@"/"] ? path : MIAFXRootPath(path);
    if (![[NSFileManager defaultManager] fileExistsAtPath:resolved]) return nil;
    return resolved;
}

- (void)markNeedsSync {
    self.needsSync = YES;
}

- (void)sync {
    self.needsSync = NO;

    NSString *path = [self targetPath];
    if (path == nil) {
        [self stop];
        return;
    }

    // 已加载同一视频且仍在播放：直接返回，零开销
    if ([path isEqualToString:self.loadedPath] && self.player != nil) {
        if (self.player.rate == 0.0) [self.player play];
        return;
    }

    AVPlayerLayer *layer = MIAFXPlayerLayerOfSurface(self.surface);
    if (layer == nil) {
        // _playerLayer 还没就绪，下一帧再试
        self.needsSync = YES;
        return;
    }

    [self stop];

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:path]];
    self.player = [AVQueuePlayer queuePlayerWithItems:@[item]];
    self.player.muted = YES;
    self.looper = [AVPlayerLooper playerLooperWithPlayer:self.player templateItem:item];
    layer.player = self.player;
    layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.loadedPath = path;
    [self.player play];
}

- (void)stop {
    AVPlayerLayer *layer = MIAFXPlayerLayerOfSurface(self.surface);
    if (layer != nil && layer.player == self.player) {
        layer.player = nil;
    }
    if (self.player != nil) {
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
        [background markNeedsSync];
    } else {
        [background stop];
    }
}

- (void)_sp_display_tick:(id)tick {
    %orig;
    MIAFXVideoBackground *background = [MIAFXVideoBackground backgroundForSurface:self];
    if (background.needsSync) {
        [background sync];
    }
}

- (void)setLastPresentationRadius:(double)radius {
    %orig;
    (void)radius;
    [[MIAFXVideoBackground backgroundForSurface:self] markNeedsSync];
}

%end
