//
//  MIAFXPreviewView.h
//  MIAFXPrefs
//
//  顶部小岛预览：按当前配置实时绘制（视频层 / 呼吸 / 跑马灯 / 轨迹 / 液滴 / 频谱 / 遮罩）
//  并在右上角显示运行状态徽章。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MIAFXPreviewView : UIView

/// 重新读取配置并刷新图层与徽章
- (void)refresh;
/// 开始/恢复动画（页面出现时）
- (void)startAnimating;
/// 暂停动画（页面消失时，省电）
- (void)stopAnimating;

@end

NS_ASSUME_NONNULL_END
