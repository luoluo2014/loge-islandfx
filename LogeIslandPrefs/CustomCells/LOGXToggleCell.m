//
//  LOGXToggleCell.m
//  品牌色开关（学 MagmaEvo MEVOToggle）
//

#import "LOGXBrand.h"
#import "LOGXStage.h"

@interface LOGXToggleCell : PSSwitchTableCell
@end

@implementation LOGXToggleCell

// 2.0.21：开关事件打点。PSControlTableCell 的 control 变化经 controlChanged: 汇入，
// 再走 specifier setter / setPreferenceValue:specifier:。若用户反馈「开关拨不动」，
// 这一行在不在 stage.log 里直接区分是 UISwitch 没收事件还是后续链路断了。
- (void)controlChanged:(UIControl *)control {
    LOGXStage("cell-toggle-controlChanged");
    [super controlChanged:control];
    LOGXStage("cell-toggle-controlChanged-ok");
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style
             reuseIdentifier:(NSString *)reuseIdentifier
                  specifier:(PSSpecifier *)specifier {
    LOGXStage("cell-toggle-init-enter");
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) {
        UISwitch *toggle = (UISwitch *)self.control;
        if ([toggle isKindOfClass:UISwitch.class]) {
            toggle.onTintColor = kLOGXColor;
        }
        self.textLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    LOGXStage("cell-toggle-init-done");
    return self;
}

@end
