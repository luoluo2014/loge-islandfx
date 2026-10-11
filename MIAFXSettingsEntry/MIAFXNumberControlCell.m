//
//  MIAFXNumberControlCell.m
//  MIAFXPrefs
//

#import "MIAFXNumberControlCell.h"
#import "MIAFXSettingsCatalog.h"

#import <QuartzCore/QuartzCore.h>

static const NSTimeInterval kMIAFXDebounceInterval = 0.06;   // 需求：60ms debounce
static const NSTimeInterval kMIAFXRepeatDelay = 0.40;        // 长按多久后开始连续微调
static const NSTimeInterval kMIAFXRepeatSlow = 0.11;         // 连续微调初始间隔
static const NSTimeInterval kMIAFXRepeatFast = 0.045;        // 加速后的间隔
static const NSInteger kMIAFXRepeatAccelerateAt = 12;        // 重复多少次后加速

@interface MIAFXNumberControlCell () <UITextFieldDelegate>
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *valueBadgeLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UILabel *rangeLabel;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UITextField *numberField;
@property (nonatomic, strong) UIButton *minusButton;
@property (nonatomic, strong) UIButton *plusButton;

@property (nonatomic, strong, nullable) NSTimer *debounceTimer;
@property (nonatomic, strong, nullable) NSTimer *repeatTimer;
@property (nonatomic) NSInteger repeatCount;
@property (nonatomic) double repeatDelta;
@property (nonatomic, getter=isHolding) BOOL holding;
@property (nonatomic) BOOL didFireRepeat;
@property (nonatomic) BOOL textIsEditing;
@property (nonatomic) BOOL needsCommit;
@property (nonatomic, strong, nullable) UISelectionFeedbackGenerator *feedbackGenerator;
@end

@implementation MIAFXNumberControlCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    [self buildSubviews];
    return self;
}

- (void)dealloc {
    [self.debounceTimer invalidate];
    [self.repeatTimer invalidate];
}

#pragma mark 构建界面

- (void)buildSubviews {
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = nil;

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _titleLabel.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightSemibold];
    _titleLabel.textColor = UIColor.labelColor;
    _titleLabel.numberOfLines = 2;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_titleLabel];

    _valueBadgeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _valueBadgeLabel.font = [UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightSemibold];
    _valueBadgeLabel.textColor = UIColor.secondaryLabelColor;
    _valueBadgeLabel.textAlignment = NSTextAlignmentRight;
    _valueBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_valueBadgeLabel];

    _detailLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _detailLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightRegular];
    _detailLabel.textColor = UIColor.secondaryLabelColor;
    _detailLabel.numberOfLines = 3;
    _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_detailLabel];

    _minusButton = [self stepButtonWithTitle:@"－" action:@selector(stepTouchDown:)];
    _plusButton = [self stepButtonWithTitle:@"＋" action:@selector(stepTouchDown:)];
    [self.contentView addSubview:_minusButton];
    [self.contentView addSubview:_plusButton];

    _numberField = [[UITextField alloc] initWithFrame:CGRectZero];
    _numberField.borderStyle = UITextBorderStyleRoundedRect;
    _numberField.keyboardType = UIKeyboardTypeDecimalPad;
    _numberField.returnKeyType = UIReturnKeyDone;
    _numberField.textAlignment = NSTextAlignmentCenter;
    _numberField.font = [UIFont monospacedDigitSystemFontOfSize:16.0 weight:UIFontWeightSemibold];
    _numberField.textColor = UIColor.labelColor;
    _numberField.autocorrectionType = UITextAutocorrectionTypeNo;
    _numberField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _numberField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _numberField.delegate = self;
    _numberField.translatesAutoresizingMaskIntoConstraints = NO;
    [_numberField addTarget:self action:@selector(fieldEditingChanged:) forControlEvents:UIControlEventEditingChanged];
    [self.contentView addSubview:_numberField];

    _slider = [[UISlider alloc] initWithFrame:CGRectZero];
    _slider.translatesAutoresizingMaskIntoConstraints = NO;
    _slider.minimumTrackTintColor = UIColor.systemBlueColor;
    [_slider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
    [_slider addTarget:self action:@selector(sliderTouchEnd:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self.contentView addSubview:_slider];

    _rangeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _rangeLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
    _rangeLabel.textColor = UIColor.tertiaryLabelColor;
    _rangeLabel.numberOfLines = 2;
    _rangeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_rangeLabel];

    UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
    CGFloat fieldWidth = 132.0;
    [NSLayoutConstraint activateConstraints:@[
        [_titleLabel.topAnchor constraintEqualToAnchor:margins.topAnchor constant:6.0],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_valueBadgeLabel.leadingAnchor constant:-8.0],

        [_valueBadgeLabel.topAnchor constraintEqualToAnchor:margins.topAnchor constant:8.0],
        [_valueBadgeLabel.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],

        [_detailLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:3.0],
        [_detailLabel.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [_detailLabel.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],

        [_minusButton.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [_minusButton.topAnchor constraintEqualToAnchor:_detailLabel.bottomAnchor constant:8.0],
        [_minusButton.widthAnchor constraintEqualToConstant:44.0],
        [_minusButton.heightAnchor constraintEqualToConstant:34.0],

        [_numberField.leadingAnchor constraintEqualToAnchor:_minusButton.trailingAnchor constant:8.0],
        [_numberField.centerYAnchor constraintEqualToAnchor:_minusButton.centerYAnchor],
        [_numberField.heightAnchor constraintEqualToConstant:34.0],

        [_plusButton.leadingAnchor constraintEqualToAnchor:_numberField.trailingAnchor constant:8.0],
        [_plusButton.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [_plusButton.centerYAnchor constraintEqualToAnchor:_minusButton.centerYAnchor],
        [_plusButton.widthAnchor constraintEqualToConstant:44.0],
        [_plusButton.heightAnchor constraintEqualToConstant:34.0],

        [_slider.topAnchor constraintEqualToAnchor:_minusButton.bottomAnchor constant:6.0],
        [_slider.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [_slider.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],

        [_rangeLabel.topAnchor constraintEqualToAnchor:_slider.bottomAnchor constant:2.0],
        [_rangeLabel.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [_rangeLabel.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [_rangeLabel.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor constant:-6.0],
    ]];

    NSLayoutConstraint *minFieldWidth = [_numberField.widthAnchor constraintGreaterThanOrEqualToConstant:fieldWidth];
    minFieldWidth.priority = 900.0;
    minFieldWidth.active = YES;
}

- (UIButton *)stepButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:19.0 weight:UIFontWeightSemibold];
    button.backgroundColor = UIColor.secondarySystemFillColor;
    button.layer.cornerRadius = 8.0;
    button.layer.masksToBounds = YES;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(stepTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [button addTarget:self action:@selector(stepTouchCancel:) forControlEvents:UIControlEventTouchCancel];
    return button;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self.debounceTimer invalidate];
    self.debounceTimer = nil;
    [self stopRepeating];
    self.controlDelegate = nil;
    self.spec = nil;
    self.textIsEditing = NO;
    self.needsCommit = NO;
}

#pragma mark 配置

- (void)configureWithSpec:(MIAFXSettingSpec *)spec {
    self.spec = spec;
    self.titleLabel.text = spec.title;
    self.detailLabel.text = spec.specDescription.length > 0 ? spec.specDescription : spec.key;
    self.rangeLabel.text = [spec rangeDescriptionString];
    self.slider.minimumValue = (float)spec.minimum;
    self.slider.maximumValue = (float)spec.maximum;
    NSString *placeholder = spec.numberMode == MIAFXNumberModeInteger ? @"整数" : @"数值";
    self.numberField.placeholder = placeholder;
    self.numberField.keyboardType = spec.numberMode == MIAFXNumberModeInteger ? UIKeyboardTypeNumberPad : UIKeyboardTypeDecimalPad;
    self.minusButton.tag = -1;
    self.plusButton.tag = 1;
    [self refreshCurrentValue];
}

- (void)refreshCurrentValue {
    if (!self.spec) return;
    double value = [self.spec snap:[self.spec currentDouble]];
    self.slider.value = (float)value;
    if (!self.textIsEditing) {
        self.numberField.text = [self.spec formatDouble:value];
    }
    self.valueBadgeLabel.text = [self.spec formatDouble:value];
}

#pragma mark 数值操作

- (double)currentResolvedValue {
    double value = [self.spec currentDouble];
    return [self.spec snap:value];
}

- (void)applyValue:(double)rawValue continuous:(BOOL)continuous {
    if (!self.spec) return;
    double value = [self.spec snap:rawValue];
    self.slider.value = (float)value;
    self.valueBadgeLabel.text = [self.spec formatDouble:value];
    if (!self.textIsEditing) {
        self.numberField.text = [self.spec formatDouble:value];
    }
    self.needsCommit = YES;
    if ([self.controlDelegate respondsToSelector:@selector(numberCell:didChangeValue:continuous:)]) {
        [self.controlDelegate numberCell:self didChangeValue:value continuous:continuous];
    }
    [self scheduleDebounce];
}

- (void)scheduleDebounce {
    [self.debounceTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.debounceTimer = [NSTimer scheduledTimerWithTimeInterval:kMIAFXDebounceInterval repeats:NO block:^(NSTimer *timer) {
        (void)timer;
        [weakSelf fireDebounce];
    }];
}

- (void)fireDebounce {
    [self.debounceTimer invalidate];
    self.debounceTimer = nil;
    if (!self.needsCommit) return;
    if (self.textIsEditing) return;   // 仍在输入时不打断用户
    self.needsCommit = NO;
    double value = [self currentResolvedValue];
    if ([self.controlDelegate respondsToSelector:@selector(numberCell:didCommitValue:)]) {
        [self.controlDelegate numberCell:self didCommitValue:value];
    }
}

- (void)flushPendingCommit {
    [self.debounceTimer invalidate];
    self.debounceTimer = nil;
    [self.numberField resignFirstResponder];
    if (self.needsCommit) {
        self.needsCommit = NO;
        double value = [self currentResolvedValue];
        if ([self.controlDelegate respondsToSelector:@selector(numberCell:didCommitValue:)]) {
            [self.controlDelegate numberCell:self didCommitValue:value];
        }
    }
}

#pragma mark 滑杆

- (void)sliderValueChanged:(UISlider *)sender {
    double value = (double)sender.value;
    [self applyValue:value continuous:YES];
}

- (void)sliderTouchEnd:(UISlider *)sender {
    (void)sender;
    // 松手后立即提交（debounce 回调也会兜底）
    if (self.needsCommit && !self.textIsEditing) {
        [self.debounceTimer invalidate];
        self.debounceTimer = nil;
        self.needsCommit = NO;
        double value = [self currentResolvedValue];
        if ([self.controlDelegate respondsToSelector:@selector(numberCell:didCommitValue:)]) {
            [self.controlDelegate numberCell:self didCommitValue:value];
        }
    }
}

#pragma mark 步进按钮（支持长按连续微调）

- (void)stepTouchDown:(UIButton *)sender {
    double delta = (sender.tag < 0 ? -1.0 : 1.0) * self.spec.step;
    self.repeatDelta = delta;
    self.repeatCount = 0;
    self.didFireRepeat = NO;
    self.holding = YES;
    [self startRepeatingWithInterval:kMIAFXRepeatDelay];
    [self playTickFeedback];
}

- (void)stepTouchUp:(UIButton *)sender {
    (void)sender;
    BOOL fired = self.didFireRepeat;
    [self stopRepeating];
    if (!fired) {
        [self stepOnce:self.repeatDelta];
    } else {
        [self commitIfNeeded];
    }
}

- (void)stepTouchCancel:(UIButton *)sender {
    (void)sender;
    [self stopRepeating];
    [self commitIfNeeded];
}

- (void)startRepeatingWithInterval:(NSTimeInterval)interval {
    [self.repeatTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.repeatTimer = [NSTimer scheduledTimerWithTimeInterval:interval repeats:NO block:^(NSTimer *timer) {
        (void)timer;
        [weakSelf handleRepeatTick];
    }];
}

- (void)handleRepeatTick {
    if (!self.isHolding) return;
    self.didFireRepeat = YES;
    self.repeatCount += 1;
    [self stepOnce:self.repeatDelta];
    NSTimeInterval interval = self.repeatCount >= kMIAFXRepeatAccelerateAt ? kMIAFXRepeatFast : kMIAFXRepeatSlow;
    [self startRepeatingWithInterval:interval];
}

- (void)stopRepeating {
    self.holding = NO;
    [self.repeatTimer invalidate];
    self.repeatTimer = nil;
}

- (void)stepOnce:(double)delta {
    if (!self.spec) return;
    double value = [self currentResolvedValue] + delta;
    double snapped = [self.spec snap:value];
    [self applyValue:snapped continuous:self.isHolding];
    [self playTickFeedback];
}

- (void)commitIfNeeded {
    if (self.needsCommit && !self.textIsEditing) [self fireDebounce];
}

- (void)playTickFeedback {
    if (self.feedbackGenerator == nil) {
        self.feedbackGenerator = [[UISelectionFeedbackGenerator alloc] init];
    }
    [self.feedbackGenerator prepare];
    [self.feedbackGenerator selectionChanged];
}

#pragma mark 文本输入

- (void)fieldEditingChanged:(UITextField *)sender {
    NSString *text = sender.text ?: @"";
    NSNumber *parsed = [self parseNumberText:text];
    if (parsed) {
        double clamped = [self.spec clamp:[parsed doubleValue]];
        if (clamped != [parsed doubleValue]) {
            self.slider.value = (float)[self.spec snap:clamped];
        } else {
            self.slider.value = (float)clamped;
        }
        self.valueBadgeLabel.text = [self.spec formatDouble:[self.spec snap:clamped]];
    }
    [self scheduleDebounce];
}

/// 手动输入解析：只接受数字与常见分隔符，失败返回 nil
- (nullable NSNumber *)parseNumberText:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return nil;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789.-+"];
    NSRange illegalRange = [trimmed rangeOfCharacterFromSet:[allowed invertedSet]];
    if (illegalRange.length > 0) return nil;
    return @(trimmed.doubleValue);
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    (void)textField;
    self.textIsEditing = YES;
    if ([self.controlDelegate respondsToSelector:@selector(numberCellDidBeginEditing:)]) {
        [self.controlDelegate numberCellDidBeginEditing:self];
    }
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    self.textIsEditing = NO;
    NSNumber *parsed = [self parseNumberText:textField.text ?: @""];
    if (parsed) {
        double snapped = [self.spec snap:[parsed doubleValue]];
        [self applyValue:snapped continuous:NO];
    } else {
        [self refreshCurrentValue];   // 非法输入：回到原值
    }
    if ([self.controlDelegate respondsToSelector:@selector(numberCellDidEndEditing:)]) {
        [self.controlDelegate numberCellDidEndEditing:self];
    }
    textField.text = [self.spec formatDouble:[self currentResolvedValue]];
    if (self.needsCommit) [self fireDebounce];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    (void)textField;
    (void)range;
    if (string.length == 0) return YES;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789.,-+ "];
    NSString *trimmed = [string stringByTrimmingCharactersInSet:allowed];
    return trimmed.length == 0;
}

@end
