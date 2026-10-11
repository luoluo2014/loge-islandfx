//
//  MIAFXNumberControlCell.h
//  MIAFXPrefs
//
//  统一的数值控件 cell：同一行内含滑杆 + 手动输入框 + 减号/加号按钮。
//  · 三者双向同步
//  · 长按 +/- 连续微调
//  · 输入按 spec 范围 clamp
//  · 整数/浮点精度与单位
//  · 变更后 60ms debounce 才真正落盘（拖动期间只 stage，便于预览实时更新）
//

#import <UIKit/UIKit.h>

@class MIAFXSettingSpec;
@class MIAFXNumberControlCell;

NS_ASSUME_NONNULL_BEGIN

@protocol MIAFXNumberControlCellDelegate <NSObject>
/// 值发生了变化。continuous 为 YES 表示用户仍在拖动/长按，此时只暂存不落盘
- (void)numberCell:(MIAFXNumberControlCell *)cell didChangeValue:(double)value continuous:(BOOL)continuous;
/// 静止 60ms 后触发，此时应执行真正保存（setObject + save:）
- (void)numberCell:(MIAFXNumberControlCell *)cell didCommitValue:(double)value;
@optional
- (void)numberCellDidBeginEditing:(MIAFXNumberControlCell *)cell;
- (void)numberCellDidEndEditing:(MIAFXNumberControlCell *)cell;
@end

@interface MIAFXNumberControlCell : UITableViewCell

@property (nonatomic, weak, nullable) id<MIAFXNumberControlCellDelegate> controlDelegate;
@property (nonatomic, strong, nullable) MIAFXSettingSpec *spec;

/// 用一条设置项配置 cell（会重建全部显示内容）
- (void)configureWithSpec:(MIAFXSettingSpec *)spec;
/// 外部修改了该 key 时刷新显示；cell 自己的输入过程中不会自刷新
- (void)refreshCurrentValue;
/// 立即提交挂起的改动（页面消失/搜索切换时调用）
- (void)flushPendingCommit;

@end

NS_ASSUME_NONNULL_END
