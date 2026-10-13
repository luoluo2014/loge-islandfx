//
//  LOGXSegmentCell.m
//  品牌色分段控件（学 MagmaEvo MEVOSegment）
//

#import "LOGXBrand.h"
#import "LOGXStage.h"

@interface PSSegmentTableCell : PSControlTableCell
@end

@interface LOGXSegmentCell : PSSegmentTableCell
@end

@implementation LOGXSegmentCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
             reuseIdentifier:(NSString *)reuseIdentifier
                  specifier:(PSSpecifier *)specifier {
    LOGXStage("cell-segment-init-enter");
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) {
        UISegmentedControl *segment = (UISegmentedControl *)self.control;
        if ([segment isKindOfClass:UISegmentedControl.class]) {
            segment.tintColor = kLOGXColor;
            // 段标题两字对齐，禁用系统自动等宽分配造成的视觉挤压
            segment.apportionsSegmentWidthsByContent = YES;
        }
        self.textLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    LOGXStage("cell-segment-init-done");
    return self;
}

@end
