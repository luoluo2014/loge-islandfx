//
//  MIAFXVideoLayer.h
//  MIAFX
//
//  AVQueuePlayer + AVPlayerLooper + AVPlayerLayer 的循环背景视频。
//

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, MIAFXVideoFillMode) {
    MIAFXVideoFillModeAspectFill = 0, // 等比填充（裁切）
    MIAFXVideoFillModeStretch = 1,    // 拉伸铺满
    MIAFXVideoFillModeAspectFit = 2,  // 等比适应（留边）
};

typedef NS_ENUM(NSUInteger, MIAFXVideoCornerMode) {
    MIAFXVideoCornerModeNone = 0,
    MIAFXVideoCornerModeCapsule = 1, // 胶囊：高度为直径
    MIAFXVideoCornerModeRadius = 2,  // 自定义圆角
};

/// 配置前缀，例如 @"Compact.Video" / @"Expanded.Video"
@interface MIAFXVideoLayer : NSObject

- (instancetype)initWithConfigurationPrefix:(NSString *)prefix NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// 由 MIAFXVideoLayer 自己拥有的宿主视图，交给 stage 摆放
@property (nonatomic, strong, readonly) UIView *contentView;
@property (nonatomic, copy, readonly) NSString *configurationPrefix;

@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;
@property (nonatomic, readonly, getter=isPlaying) BOOL playing;
@property (nonatomic, readonly) BOOL hasError;
@property (nonatomic, copy, readonly) NSString *statusDescription;

/// 读取配置并（重新）装载资源
- (void)reloadConfiguration;

/// 布局到给定的岛区域
- (void)layoutInBounds:(CGRect)bounds;

- (void)play;
- (void)pause;
/// 与 -pause 的区别：出错后不再恢复循环
- (void)resume;
/// 卸载：暂停 + 移除 layer + 释放 player
- (void)detach;

@end

NS_ASSUME_NONNULL_END
