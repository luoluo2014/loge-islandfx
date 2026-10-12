//
//  LOGXHeaderCell.m
//  设置页头部（学 MagmaEvo MEVOHeader）：卡通岛图标 + 34pt 大标题
//  + 实时引擎状态。引擎每 5 秒发布心跳，本 cell 监听同一条通知自刷新。
//

#import "LOGXBrand.h"
#import <notify.h>

@interface LOGXHeaderCell : PSTableCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *resumeButton;
@property (nonatomic) int reloadToken;
@end

@implementation LOGXHeaderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
             reuseIdentifier:(NSString *)reuseIdentifier
                  specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil specifier:specifier];
    if (!self) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = UIColor.clearColor;

    _iconView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"header"
                                                             inBundle:[NSBundle bundleForClass:self.class]
                                                            compatibleWithTraitCollection:nil]];
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_iconView];

    // titleLabel 继承自 PSTableCell（只读），直接复用并重新排版
    NSMutableAttributedString *title = [[NSMutableAttributedString alloc] initWithString:@"落格 · 灵动岛"];
    [title addAttribute:NSFontAttributeName value:[UIFont fontWithName:@"HelveticaNeue-Light" size:30.0]
                   range:NSMakeRange(0, title.length)];
    self.titleLabel.attributedText = title;
    self.titleLabel.textColor = kLOGXColor;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    if (self.titleLabel.superview != self.contentView) {
        [self.titleLabel removeFromSuperview];
        [self.contentView addSubview:self.titleLabel];
    }

    _statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _statusLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    _statusLabel.textColor = UIColor.secondaryLabelColor;
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_statusLabel];

    _resumeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _resumeButton.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    [_resumeButton setTitle:@"恢复启用" forState:UIControlStateNormal];
    [_resumeButton setTitleColor:kLOGXColor forState:UIControlStateNormal];
    [_resumeButton addTarget:self action:@selector(resumeTapped) forControlEvents:UIControlEventTouchUpInside];
    _resumeButton.translatesAutoresizingMaskIntoConstraints = NO;
    _resumeButton.hidden = YES;
    [self.contentView addSubview:_resumeButton];

    [NSLayoutConstraint activateConstraints:@[
        [NSLayoutConstraint constraintWithItem:_iconView attribute:NSLayoutAttributeTop
                                     relatedBy:NSLayoutRelationEqual
                                        toItem:self.contentView attribute:NSLayoutAttributeTop
                                    multiplier:1.0 constant:14.0],
        [NSLayoutConstraint constraintWithItem:_iconView attribute:NSLayoutAttributeCenterX
                                     relatedBy:NSLayoutRelationEqual
                                        toItem:self.contentView attribute:NSLayoutAttributeCenterX
                                    multiplier:1.0 constant:0.0],
        [NSLayoutConstraint constraintWithItem:_iconView attribute:NSLayoutAttributeWidth
                                     relatedBy:NSLayoutRelationEqual
                                        toItem:nil attribute:NSLayoutAttributeNotAnAttribute
                                    multiplier:1.0 constant:64.0],
        [NSLayoutConstraint constraintWithItem:_iconView attribute:NSLayoutAttributeHeight
                                     relatedBy:NSLayoutRelationEqual
                                        toItem:_iconView attribute:NSLayoutAttributeWidth
                                    multiplier:1.0 constant:0.0],
        [NSLayoutConstraint constraintWithItem:self.titleLabel attribute:NSLayoutAttributeTop
                                     relatedBy:NSLayoutRelationEqual
                                        toItem:_iconView attribute:NSLayoutAttributeBottom
                                    multiplier:1.0 constant:10.0],
        [NSLayoutConstraint constraintWithItem:self.titleLabel attribute:NSLayoutAttributeLeading
                                     relatedBy:NSLayoutRelationEqual
                                        toItem:self.contentView attribute:NSLayoutAttributeLeading
                                    multiplier:1.0 constant:8.0],
        [NSLayoutConstraint constraintWithItem:self.titleLabel attribute:NSLayoutAttributeTrailing
                                     relatedBy:NSLayoutRelationEqual
                                        toItem:self.contentView attribute:NSLayoutAttributeTrailing
                                    multiplier:1.0 constant:-8.0],
        [NSLayoutConstraint constraintWithItem:_statusLabel attribute:NSLayoutAttributeTop
                                     relatedBy:NSLayoutRelationEqual
                                        toItem:self.titleLabel attribute:NSLayoutAttributeBottom
                                    multiplier:1.0 constant:6.0],
        [NSLayoutConstraint constraintWithItem:_statusLabel attribute:NSLayoutAttributeLeading
                                     relatedBy:NSLayoutRelationEqual
                                        toItem:self.contentView attribute:NSLayoutAttributeLeading
                                    multiplier:1.0 constant:8.0],
        [NSLayoutConstraint constraintWithItem:_statusLabel attribute:NSLayoutAttributeTrailing
                                     relatedBy:NSLayoutRelationEqual
                                        toItem:self.contentView attribute:NSLayoutAttributeTrailing
                                    multiplier:1.0 constant:-8.0],
        [NSLayoutConstraint constraintWithItem:_resumeButton attribute:NSLayoutAttributeTop
                                     relatedBy:NSLayoutRelationEqual
                                        toItem:_statusLabel attribute:NSLayoutAttributeBottom
                                    multiplier:1.0 constant:2.0],
        [NSLayoutConstraint constraintWithItem:_resumeButton attribute:NSLayoutAttributeCenterX
                                     relatedBy:NSLayoutRelationEqual
                                        toItem:self.contentView attribute:NSLayoutAttributeCenterX
                                    multiplier:1.0 constant:0.0],
        [NSLayoutConstraint constraintWithItem:_resumeButton attribute:NSLayoutAttributeBottom
                                     relatedBy:NSLayoutRelationEqual
                                        toItem:self.contentView attribute:NSLayoutAttributeBottom
                                    multiplier:1.0 constant:-10.0],
    ]];

    [self refreshStatus];
    // 引擎每次发布（5 秒）都会投递这条通知，头部状态随之保持最新
    notify_register_dispatch(LOGX_NOTIFY_RELOAD, &_reloadToken, dispatch_get_main_queue(), ^(__unused int token) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self refreshStatus]; });
    });
    return self;
}

- (CGFloat)preferredHeightForWidth:(CGFloat)width {
    return 168.0;
}

- (void)refreshStatus {
    NSDictionary *heartbeat = LOGXPrefsObject(LOGX_KEY_HEARTBEAT);
    NSArray *assets = LOGXPrefsObject(LOGX_KEY_ASSETS_VIDEOS);
    NSUInteger videoCount = [assets isKindOfClass:NSArray.class] ? ((NSArray *)assets).count : 0;

    if (![heartbeat isKindOfClass:NSDictionary.class]) {
        _statusLabel.text = @"未检测到引擎 · 请注销重启";
        _statusLabel.textColor = UIColor.systemRedColor;
        _resumeButton.hidden = YES;
        return;
    }
    if ([heartbeat[@"suspended"] boolValue]) {
        _statusLabel.text = @"引擎已因异常暂停 · 轻点下方恢复";
        _statusLabel.textColor = UIColor.systemOrangeColor;
        _resumeButton.hidden = NO;
        return;
    }
    _statusLabel.text = [NSString stringWithFormat:@"引擎在线 · v%@ · 视频 %lu 个",
                         heartbeat[@"version"] ?: @"?", (unsigned long)videoCount];
    _statusLabel.textColor = UIColor.secondaryLabelColor;
    _resumeButton.hidden = YES;
}

- (void)resumeTapped {
    LOGXPrefsSetObject(@YES, LOGX_KEY_RESUME_REQUEST);
    LOGXPrefsSynchronize();
    _statusLabel.text = @"已请求恢复，即将生效…";
    _resumeButton.hidden = YES;
}

- (void)dealloc {
    if (_reloadToken >= 0) notify_cancel(_reloadToken);
}

@end
