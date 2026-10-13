//
//  LOGXSliderCell.m
//  带数值显示的滑杆 cell。左侧标签、中间滑杆、右侧实时数值（百分比/整数）。
//  拖动时只更新本地数值显示，松手才写 CFPreferences 并通知插件——避免
//  拖动过程中每秒几十次跨进程写入。
//

#import "LOGXBrand.h"
#import "LOGXStage.h"

@interface LOGXSliderCell : PSTableCell
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, copy) NSString *configKey;
@property (nonatomic, copy) NSString *format;
@property (nonatomic) double minValue;
@property (nonatomic) double maxValue;
@end

@implementation LOGXSliderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
             reuseIdentifier:(NSString *)reuseIdentifier
                  specifier:(PSSpecifier *)specifier {
    LOGXStage("cell-slider-init-enter");
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier specifier:specifier];
    if (!self) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.textLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular];
    self.textLabel.text = specifier.name;

    _configKey = [specifier propertyForKey:LOGX_PS_KEY_KEY];
    _format = [specifier propertyForKey:@"format"] ?: @"integer";
    _minValue = [[specifier propertyForKey:LOGX_PS_MIN_KEY] doubleValue];
    _maxValue = [[specifier propertyForKey:LOGX_PS_MAX_KEY] doubleValue];
    if (_maxValue <= _minValue) _maxValue = _minValue + 1.0;

    _slider = [[UISlider alloc] initWithFrame:CGRectZero];
    _slider.minimumValue = (float)_minValue;
    _slider.maximumValue = (float)_maxValue;
    _slider.tintColor = kLOGXColor;
    _slider.translatesAutoresizingMaskIntoConstraints = NO;
    [_slider setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [_slider addTarget:self action:@selector(sliderDragged:) forControlEvents:UIControlEventValueChanged];
    [_slider addTarget:self action:@selector(sliderReleased:) forControlEvents:UIControlEventTouchUpInside];
    [_slider addTarget:self action:@selector(sliderReleased:) forControlEvents:UIControlEventTouchUpOutside];
    [_slider addTarget:self action:@selector(sliderReleased:) forControlEvents:UIControlEventTouchCancel];
    [self.contentView addSubview:_slider];

    _valueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightRegular];
    _valueLabel.textColor = UIColor.secondaryLabelColor;
    _valueLabel.textAlignment = NSTextAlignmentRight;
    _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_valueLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.contentView addSubview:_valueLabel];

    CGFloat gap = 12.0;
    [NSLayoutConstraint activateConstraints:@[
        [NSLayoutConstraint constraintWithItem:_valueLabel attribute:NSLayoutAttributeTrailing
                                     relatedBy:NSLayoutRelationEqual
                                        toItem:self.contentView attribute:NSLayoutAttributeTrailing
                                    multiplier:1.0 constant:-16.0],
        [NSLayoutConstraint constraintWithItem:_valueLabel attribute:NSLayoutAttributeCenterY
                                     relatedBy:NSLayoutRelationEqual
                                        toItem:self.contentView attribute:NSLayoutAttributeCenterY
                                    multiplier:1.0 constant:0.0],
        [NSLayoutConstraint constraintWithItem:_valueLabel attribute:NSLayoutAttributeWidth
                                     relatedBy:NSLayoutRelationGreaterThanOrEqual
                                        toItem:nil attribute:NSLayoutAttributeNotAnAttribute
                                    multiplier:1.0 constant:52.0],
        [NSLayoutConstraint constraintWithItem:_slider attribute:NSLayoutAttributeLeading
                                     relatedBy:NSLayoutRelationEqual
                                        toItem:self.textLabel attribute:NSLayoutAttributeTrailing
                                    multiplier:1.0 constant:gap],
        [NSLayoutConstraint constraintWithItem:_slider attribute:NSLayoutAttributeTrailing
                                     relatedBy:NSLayoutRelationEqual
                                        toItem:_valueLabel attribute:NSLayoutAttributeLeading
                                    multiplier:1.0 constant:-gap],
        [NSLayoutConstraint constraintWithItem:_slider attribute:NSLayoutAttributeCenterY
                                     relatedBy:NSLayoutRelationEqual
                                        toItem:self.contentView attribute:NSLayoutAttributeCenterY
                                    multiplier:1.0 constant:0.0],
    ]];

    [self refreshCellContentsWithSpecifier:specifier];
    LOGXStage("cell-slider-init-done");
    return self;
}

- (NSString *)displayTextForValue:(double)value {
    if ([_format isEqualToString:@"percent"]) {
        return [NSString stringWithFormat:@"%d%%", (int)lround(value * 100.0)];
    }
    return [NSString stringWithFormat:@"%d", (int)lround(value)];
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    double value = [[specifier performGetter] doubleValue];
    if (value < _minValue) value = _minValue;
    if (value > _maxValue) value = _maxValue;
    _slider.value = (float)value;
    _valueLabel.text = [self displayTextForValue:value];
}

- (void)sliderDragged:(UISlider *)sender {
    _valueLabel.text = [self displayTextForValue:sender.value];
}

- (void)sliderReleased:(UISlider *)sender {
    [self.specifier performSetterWithValue:@(sender.value)];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.specifier = nil;
    _configKey = nil;
}

@end
