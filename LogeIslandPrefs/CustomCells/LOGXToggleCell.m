//
//  LOGXToggleCell.m
//  品牌色开关（学 MagmaEvo MEVOToggle）
//

#import "LOGXBrand.h"
#import "LOGXStage.h"

@interface LOGXToggleCell : PSSwitchTableCell
@end

@implementation LOGXToggleCell

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
