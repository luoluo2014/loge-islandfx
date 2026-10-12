//
//  MIAFXVideoBackground.xm
//  MIAFX
//
//  视频背景的「正确」触发方式：直接 hook SpringBoard 的灵动岛渲染表面
//  _SPIslandRenderSurface，复用系统原生的 _playerLayer（AVPlayerLayer）来播放
//  用户选择的背景视频（参考 DynamicFX 的实现路径）。
//
//  之前用 MRU/SAUI 宿主视图挂载的方式在 iOS 17.1 上不生效，这里改为命中
//  岛体渲染层本身。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

#import "MIAFXConfig.h"
#import "MIAFXConstants.h"
#import "MIAFXPath.h"

/// 灵动岛渲染表面（SpringBoard 私有类）
@interface _SPIslandRenderSurface : UIView
@end

static const void *kMIAFXVideoBackgroundKey = &kMIAFXVideoBackgroundKey;

/// 每个 _SPIslandRenderSurface 实例关联一个视频背景管理器
@interface MIAFXVideoBackground : NSObject
@property (nonatomic, weak) UIView *surface;
@property (nonatomic, strong) AVQueuePlayer *player;
@property (nonatomic, strong) AVPlayerLooper *looper;
@property (nonatomic, copy, nullable) NSString *loadedPath;
@property (nonatomic) BOOL expanded;
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

/// 读取系统类原生的 _playerLayer（AVPlayerLayer）
static AVPlayerLayer *MIAFXPlayerLayerOfSurface(UIView *surface) {
    Ivar ivar = class_getInstanceVariable([surface class], "_playerLayer");
    if (ivar == NULL) return nil;
    id layer = object_getIvar(surface, ivar);
    return [layer isKindOfClass:[AVPlayerLayer class]] ? (AVPlayerLayer *)layer : nil;
}

/// 根据当前岛的尺寸决定用紧凑还是展开配置
- (NSString *)targetPath {
    MIAFXConfig *config = [MIAFXConfig sharedConfig];
    if (![config boolForKey:@"Global.Enabled"]) return nil;
    if (![config isFeatureEnabled:MIAFXFeatureVideo]) return nil;

    // 紧凑岛宽度约 126pt，展开岛约 340pt，取中间值 220 区分
    BOOL expanded = self.surface.bounds.size.width >= 220.0;
    self.expanded = expanded;
    NSString *prefix = expanded ? @"Expanded.Video" : @"Compact.Video";
    if (![config boolForKey:[prefix stringByAppendingString:@".Enabled"]]) return nil;

    NSString *path = [config stringForKey:[prefix stringByAppendingString:@".Path"]];
    if (path.length == 0) return nil;
    NSString *resolved = [path hasPrefix:@"/"] ? path : MIAFXRootPath(path);
    if (![[NSFileManager defaultManager] fileExistsAtPath:resolved]) return nil;
    return resolved;
}

- (void)sync {
    NSString *path = [self targetPath];
    if (path == nil) {
        [self stop];
        return;
    }
    AVPlayerLayer *layer = MIAFXPlayerLayerOfSurface(self.surface);
    if (layer == nil) return;   // 系统尚未创建 _playerLayer，等下次刷新

    // 已加载同一视频：只保证在播放，避免频繁重建
    if ([path isEqualToString:self.loadedPath] && self.player != nil) {
        if (self.player.rate == 0.0) [self.player play];
        return;
    }

    [self stop];

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:path]];
    self.player = [AVQueuePlayer queuePlayerWithItems:@[item]];
    self.player.muted = YES;   // 背景视频静音
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
        [background sync];
    } else {
        [background stop];
    }
}

- (void)setLastPresentationRadius:(double)radius {
    %orig;
    (void)radius;
    [[MIAFXVideoBackground backgroundForSurface:self] sync];
}

%end
