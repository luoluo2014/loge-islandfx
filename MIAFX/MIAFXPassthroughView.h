//
//  MIAFXPassthroughView.h
//  MIAFX
//
//  所有 MIAFX 自己挂上去的 view / window 都必须完全不吃触摸，
//  否则会挡住灵动岛本身的点击与长按展开手势。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// hitTest 恒返回 nil、pointInside 恒返回 NO 的容器视图。
@interface MIAFXPassthroughView : UIView
@end

/// hitTest 恒返回 nil、pointInside 恒返回 NO 的窗口。
/// 用于 host 挂载失败时的 fallback。
@interface MIAFXPassthroughWindow : UIWindow
@end

NS_ASSUME_NONNULL_END
