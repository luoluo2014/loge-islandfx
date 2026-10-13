//
//  LOGXVideoCell.m
//  「背景视频」行：显示当前选择的视频名，点击进入选择页。
//

#import "LOGXBrand.h"
#import "LOGXStage.h"

@interface LOGXVideoCell : PSTableCell
@end

@implementation LOGXVideoCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
             reuseIdentifier:(NSString *)reuseIdentifier
                  specifier:(PSSpecifier *)specifier {
    LOGXStage("cell-video-init-enter");
    self = [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseIdentifier specifier:specifier];
    if (!self) return nil;
    self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    self.textLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular];
    self.detailTextLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    self.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self refreshCellContentsWithSpecifier:specifier];
    LOGXStage("cell-video-init-done");
    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    NSString *value = [[specifier performGetter] description] ?: @"";
    self.detailTextLabel.text = (value.length > 0) ? value : @"未选择";
    self.detailTextLabel.textColor = (value.length > 0) ? UIColor.labelColor : UIColor.tertiaryLabelColor;
}

@end
