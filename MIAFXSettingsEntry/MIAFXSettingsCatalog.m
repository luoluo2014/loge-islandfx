//
//  MIAFXSettingsCatalog.m
//  MIAFXPrefs
//
//  设置分组总表。所有读写一律经由 [MIAFXConfig sharedConfig]，落盘使用
//  -[MIAFXConfig save:]，该函数会发布 live state 并 post reload notify（需求 8）。
//

#import "MIAFXSettingsCatalog.h"

#import "MIAFXConfig.h"
#import "MIAFXDefaults.h"

#include <string.h>

NSString *const MIAFXActionFilzaVideos = @"filza.videos";
NSString *const MIAFXActionFilzaMasks = @"filza.masks";
NSString *const MIAFXActionFilzaCustomOrbits = @"filza.customOrbits";
NSString *const MIAFXActionFilzaPresets = @"filza.presets";
NSString *const MIAFXActionFilzaLogs = @"filza.logs";
NSString *const MIAFXActionFilzaConfiguration = @"filza.configuration";
NSString *const MIAFXActionExportConfiguration = @"config.export";
NSString *const MIAFXActionImportConfiguration = @"config.import";
NSString *const MIAFXActionShareConfiguration = @"config.share";
NSString *const MIAFXActionRespring = @"system.respring";
NSString *const MIAFXActionResetProtection = @"diagnostics.resetProtection";
NSString *const MIAFXActionRescanAssets = @"assets.rescan";
NSString *const MIAFXActionDiagnostics = @"diagnostics.open";
NSString *const MIAFXActionOpenSystemSettings = @"system.openSettings";
NSString *const MIAFXActionShareDiagnostics = @"diagnostics.share";
NSString *const MIAFXActionViewDiagnostics = @"diagnostics.view";
NSString *const MIAFXActionClearDiagnostics = @"diagnostics.clear";

#pragma mark - 动作标识符前缀

static NSString *const kMIAFXPresetThemePrefix = @"preset.theme.";
static NSString *const kMIAFXPresetPerformancePrefix = @"preset.performance.";
static NSString *const kMIAFXResetPagePrefix = @"reset.page.";

/// 判断 NSNumber 的底层标量是否为布尔（@YES/@NO 生成的 objCType 为 c 或 B）
static BOOL MIAFXNumberIsBoolean(NSNumber *number) {
    const char *type = number.objCType;
    if (type == NULL) return NO;
    return strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(char)) == 0;
}

NSString *MIAFXPresetThemeIdentifier(NSString *slug) { return [kMIAFXPresetThemePrefix stringByAppendingString:slug]; }
NSString *MIAFXPresetPerformanceIdentifier(NSString *slug) { return [kMIAFXPresetPerformancePrefix stringByAppendingString:slug]; }
NSString *MIAFXResetPageIdentifier(NSString *pageIdentifier) { return [kMIAFXResetPagePrefix stringByAppendingString:pageIdentifier]; }

#pragma mark - 工厂函数

static MIAFXSettingOption *MIAOpt(NSString *title, NSString * _Nullable description, id value) {
    return [MIAFXSettingOption optionWithTitle:title description:description value:value];
}

static MIAFXSettingSpec *MIAActionSpec(NSString *identifier, NSString *title, NSString * _Nullable description) {
    MIAFXSettingSpec *spec = [MIAFXSettingSpec specWithKey:@"" title:title description:description kind:MIAFXSettingKindAction];
    spec.actionIdentifier = identifier;
    return spec;
}

static MIAFXSettingSpec *MIASwitchSpec(NSString *key, NSString *title, NSString * _Nullable description) {
    return [MIAFXSettingSpec specWithKey:key title:title description:description kind:MIAFXSettingKindSwitch];
}

static MIAFXSettingSpec *MIAFeatureSpec(uint32_t bit, NSString *title, NSString * _Nullable description) {
    MIAFXSettingSpec *spec = [MIAFXSettingSpec specWithKey:@"Global.FeatureMask" title:title description:description kind:MIAFXSettingKindFeatureFlag];
    spec.featureBit = bit;
    return spec;
}

static MIAFXSettingSpec *MIANumberSpec(NSString *key, NSString *title, NSString * _Nullable description,
                                       double minimum, double maximum, double step, NSUInteger digits,
                                       NSString * _Nullable unit) {
    MIAFXSettingSpec *spec = [MIAFXSettingSpec specWithKey:key title:title description:description kind:MIAFXSettingKindNumber];
    spec.numberMode = MIAFXNumberModeFloat;
    spec.minimum = minimum;
    spec.maximum = maximum;
    spec.step = step;
    spec.fractionDigits = digits;
    spec.unit = unit;
    return spec;
}

static MIAFXSettingSpec *MIAIntegerSpec(NSString *key, NSString *title, NSString * _Nullable description,
                                        NSInteger minimum, NSInteger maximum, NSInteger step,
                                        NSString * _Nullable unit) {
    MIAFXSettingSpec *spec = [MIAFXSettingSpec specWithKey:key title:title description:description kind:MIAFXSettingKindNumber];
    spec.numberMode = MIAFXNumberModeInteger;
    spec.minimum = (double)minimum;
    spec.maximum = (double)maximum;
    spec.step = (double)(step > 0 ? step : 1);
    spec.fractionDigits = 0;
    spec.unit = unit;
    return spec;
}

static MIAFXSettingSpec *MIAEnumSpec(NSString *key, NSString *title, NSString * _Nullable description,
                                     NSArray<MIAFXSettingOption *> *options) {
    MIAFXSettingSpec *spec = [MIAFXSettingSpec specWithKey:key title:title description:description kind:MIAFXSettingKindEnum];
    spec.options = options;
    spec.enumUsesSegmentedControl = (options.count <= 3);
    spec.enumUsesActionSheet = (options.count > 4);
    return spec;
}

static MIAFXSettingSpec *MIAPathSpec(NSString *key, NSString *title, NSString * _Nullable description) {
    MIAFXSettingSpec *spec = [MIAFXSettingSpec specWithKey:key title:title description:description kind:MIAFXSettingKindPath];
    spec.enumUsesActionSheet = NO;
    return spec;
}

static MIAFXSettingSpec *MIADependent(MIAFXSettingSpec *spec, NSString *key, NSArray<id> *values) {
    spec.visibleKey = key;
    spec.visibleValues = values;
    return spec;
}

static MIAFXSettingSection *MIASection(NSString *title, NSString * _Nullable footer, NSArray<MIAFXSettingSpec *> *items) {
    return [MIAFXSettingSection sectionWithTitle:title footer:footer items:items];
}

@implementation MIAFXSettingOption

+ (instancetype)optionWithTitle:(NSString *)title value:(id)value {
    return [self optionWithTitle:title description:nil value:value];
}

+ (instancetype)optionWithTitle:(NSString *)title description:(NSString *)description value:(id)value {
    MIAFXSettingOption *option = [[MIAFXSettingOption alloc] init];
    option.title = title;
    option.optionDescription = description;
    option.value = value;
    return option;
}

@end

@implementation MIAFXSettingSpec

+ (instancetype)specWithKey:(NSString *)key title:(NSString *)title description:(NSString *)description kind:(MIAFXSettingKind)kind {
    MIAFXSettingSpec *spec = [[MIAFXSettingSpec alloc] init];
    spec.key = key;
    spec.title = title;
    spec.specDescription = description;
    spec.kind = kind;
    spec.numberMode = MIAFXNumberModeFloat;
    spec.minimum = 0.0;
    spec.maximum = 1.0;
    spec.step = 0.01;
    spec.fractionDigits = 2;
    spec.featureBit = 0;
    spec.enumUsesActionSheet = NO;
    spec.enumUsesSegmentedControl = NO;
    spec.inlineToplist = NO;
    return spec;
}

#pragma mark 取值

- (id)currentValue {
    if (self.kind == MIAFXSettingKindFeatureFlag) {
        NSInteger mask = [[MIAFXConfig sharedConfig] integerForKey:@"Global.FeatureMask"];
        return @(((uint32_t)mask & self.featureBit) != 0);
    }
    if (self.key.length == 0) return nil;
    return [[MIAFXConfig sharedConfig] objectForKey:self.key];
}

- (double)currentDouble {
    return [[self currentValue] doubleValue];
}

- (NSInteger)currentInteger {
    return [[self currentValue] integerValue];
}

- (BOOL)currentBool {
    return [[self currentValue] boolValue];
}

- (id)defaultValue {
    if (self.kind == MIAFXSettingKindFeatureFlag) {
        NSInteger mask = [MIAFXDefaultValue(@"Global.FeatureMask") integerValue];
        return @(((uint32_t)mask & self.featureBit) != 0);
    }
    if (self.key.length == 0) return nil;
    return MIAFXDefaultValue(self.key);
}

- (BOOL)isDefaultValue {
    id current = [self currentValue];
    id fallback = [self defaultValue];
    if (current == nil || fallback == nil) return (current == fallback);
    if ([fallback isKindOfClass:NSNumber.class] && [current isKindOfClass:NSNumber.class]) {
        return [fallback isEqualToNumber:current];
    }
    if ([fallback isKindOfClass:NSString.class] && [current isKindOfClass:NSString.class]) {
        return [fallback isEqualToString:current];
    }
    return [fallback isEqual:current];
}

#pragma mark 数值处理

- (double)snap:(double)value {
    double clamped = [self clamp:value];
    if (self.numberMode == MIAFXNumberModeInteger) return (double)llround(clamped);
    return clamped;
}

- (double)clamp:(double)value {
    double result = value;
    if (result < self.minimum) result = self.minimum;
    if (result > self.maximum) result = self.maximum;
    if (isnan(result) || isinf(result)) result = self.minimum;
    return result;
}

- (NSString *)formatDouble:(double)value {
    NSString *number;
    if (self.numberMode == MIAFXNumberModeInteger) {
        number = [NSString stringWithFormat:@"%ld", (long)llround(value)];
    } else {
        number = [NSString stringWithFormat:[NSString stringWithFormat:@"%%.%ldf", (long)self.fractionDigits], value];
    }
    if (self.unit.length > 0) return [NSString stringWithFormat:@"%@ %@", number, self.unit];
    return number;
}

- (NSString *)valueDisplayString {
    if (self.kind == MIAFXSettingKindEnum) {
        id value = [self currentValue];
        for (MIAFXSettingOption *option in self.options) {
            if ([option.value isEqual:value]) return option.title;
        }
        NSInteger index = [value integerValue];
        if (index >= 0 && (NSUInteger)index < self.options.count) return self.options[index].title;
        return [NSString stringWithFormat:@"未知 (%@)", value ?: @"空"];
    }
    if (self.kind == MIAFXSettingKindSwitch || self.kind == MIAFXSettingKindFeatureFlag) {
        return [self currentBool] ? @"开启" : @"关闭";
    }
    if (self.kind == MIAFXSettingKindText || self.kind == MIAFXSettingKindPath) {
        NSString *text = [[self currentValue] description];
        return text.length > 0 ? text : @"未设置";
    }
    if (self.numberMode == MIAFXNumberModeInteger) return [self formatDouble:[self currentDouble]];
    return [self formatDouble:[self currentDouble]];
}

- (NSString *)rangeDescriptionString {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (self.kind == MIAFXSettingKindNumber) {
        NSString *minText = self.numberMode == MIAFXNumberModeInteger
            ? [NSString stringWithFormat:@"%ld", (long)llround(self.minimum)]
            : [NSString stringWithFormat:[NSString stringWithFormat:@"%%.%ldf", (long)self.fractionDigits], self.minimum];
        NSString *maxText = self.numberMode == MIAFXNumberModeInteger
            ? [NSString stringWithFormat:@"%ld", (long)llround(self.maximum)]
            : [NSString stringWithFormat:[NSString stringWithFormat:@"%%.%ldf", (long)self.fractionDigits], self.maximum];
        NSString *stepText = self.numberMode == MIAFXNumberModeInteger
            ? [NSString stringWithFormat:@"%ld", (long)llround(self.step)]
            : [NSString stringWithFormat:@"%g", self.step];
        [parts addObject:[NSString stringWithFormat:@"范围 %@ ~ %@", minText, maxText]];
        [parts addObject:[NSString stringWithFormat:@"步进 %@", stepText]];
        id fallback = [self defaultValue];
        if ([fallback isKindOfClass:NSNumber.class]) {
            [parts addObject:[NSString stringWithFormat:@"默认 %@", [self formatDouble:[fallback doubleValue]]]];
        }
        if (self.unit.length > 0) [parts addObject:[NSString stringWithFormat:@"单位 %@", self.unit]];
    } else if (self.kind == MIAFXSettingKindEnum) {
        [parts addObject:[NSString stringWithFormat:@"共 %lu 个选项", (unsigned long)self.options.count]];
        id fallback = [self defaultValue];
        for (MIAFXSettingOption *option in self.options) {
            if ([option.value isEqual:fallback]) { [parts addObject:[NSString stringWithFormat:@"默认 %@", option.title]]; break; }
        }
    } else if (self.kind == MIAFXSettingKindSwitch || self.kind == MIAFXSettingKindFeatureFlag) {
        [parts addObject:[NSString stringWithFormat:@"默认 %@", [[self defaultValue] boolValue] ? @"开启" : @"关闭"]];
    } else if (self.kind == MIAFXSettingKindText || self.kind == MIAFXSettingKindPath) {
        NSString *fallback = [[self defaultValue] description];
        [parts addObject:[NSString stringWithFormat:@"默认 %@", fallback.length > 0 ? fallback : @"空"]];
    }
    return [parts componentsJoinedByString:@" · "];
}

- (BOOL)isVisibleNow {
    if (self.visibleKey.length == 0) return YES;
    id value = [[MIAFXConfig sharedConfig] objectForKey:self.visibleKey];
    if (self.visibleValues.count == 0) return [value boolValue];
    for (id candidate in self.visibleValues) {
        if ([candidate isKindOfClass:NSNumber.class] && [value isKindOfClass:NSNumber.class]) {
            if ([candidate isEqualToNumber:value]) return YES;
        } else if ([candidate isKindOfClass:NSString.class] && [value isKindOfClass:NSString.class]) {
            if ([candidate isEqualToString:value]) return YES;
        } else if ([candidate isEqual:value]) {
            return YES;
        }
    }
    return NO;
}

@end

@implementation MIAFXSettingSection

+ (instancetype)sectionWithTitle:(NSString *)title footer:(NSString *)footer items:(NSArray<MIAFXSettingSpec *> *)items {
    MIAFXSettingSection *section = [[MIAFXSettingSection alloc] init];
    section.title = title;
    section.footer = footer;
    section.items = items ?: @[];
    return section;
}

@end

@implementation MIAFXSettingPage

- (NSUInteger)itemCount {
    NSUInteger count = 0;
    for (MIAFXSettingSection *section in self.sections) count += section.items.count;
    return count;
}

@end

@implementation MIAFXSettingPreset
@end

#pragma mark - 目录本体

@interface MIAFXSettingsCatalog ()
@property (nonatomic, copy) NSArray<MIAFXSettingPage *> *pages;
@property (nonatomic, strong) NSMutableDictionary<NSString *, MIAFXSettingSpec *> *specsByKey;
@property (nonatomic, copy) NSArray<MIAFXSettingPreset *> *themePresets;
@property (nonatomic, copy) NSArray<MIAFXSettingPreset *> *performancePresets;
@end

@implementation MIAFXSettingsCatalog

+ (instancetype)sharedCatalog {
    static MIAFXSettingsCatalog *catalog;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        catalog = [[MIAFXSettingsCatalog alloc] init];
        [catalog buildPages];
        [catalog buildPresets];
    });
    return catalog;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _specsByKey = [NSMutableDictionary dictionary];
    return self;
}

#pragma mark 构建

- (void)registerPages:(NSArray<MIAFXSettingPage *> *)pages {
    for (MIAFXSettingPage *page in pages) {
        for (MIAFXSettingSection *section in page.sections) {
            for (MIAFXSettingSpec *spec in section.items) {
                spec.group = page.title;
                if (spec.key.length > 0 && self.specsByKey[spec.key] == nil) {
                    self.specsByKey[spec.key] = spec;
                }
            }
        }
    }
}

- (void)buildPages {
    NSMutableArray<MIAFXSettingPage *> *pages = [NSMutableArray array];

    // 1) 全局与分阶段
    {
        MIAFXSettingPage *page = [[MIAFXSettingPage alloc] init];
        page.identifier = @"global";
        page.title = @"全局";
        page.pageDescription = @"总开关、分阶段功能位与基础渲染行为";
        page.sections = @[
            MIASection(@"总开关", @"关闭后 MIAFX 会停止一切绘制，并立即发布 live state 通知。", @[
                MIASwitchSpec(@"Global.Enabled", @"启用 MIAFX", @"主控开关。关闭后所有特效停止渲染，岛呦依旧保持原生外观。"),
            ]),
            MIASection(@"分阶段开关（FeatureMask）", @"每一项对应 FeatureMask 中的一个位，只影响所属的渲染阶段。", @[
                MIAFeatureSpec(MIAFXFeatureVideo, @"视频层", @"控制紧凑/展开两段自定义视频渲染。"),
                MIAFeatureSpec(MIAFXFeatureBreathing, @"呼吸动效", @"控制岛体整体的呼吸缩放/淡入淡出。"),
                MIAFeatureSpec(MIAFXFeatureNativeElements, @"原生元素变换", @"控制原生左/右/音轨/侧边元素的位移与缩放。"),
                MIAFeatureSpec(MIAFXFeatureMarquee, @"双层流光跑马灯", @"控制胶囊边缘的双层流动光带。"),
                MIAFeatureSpec(MIAFXFeatureOrbit, @"19 轨迹", @"控制沿 19 种轨迹运动的轨道粒子。"),
                MIAFeatureSpec(MIAFXFeatureMetaball, @"液滴融合球", @"控制 Metaball 液滴与融合效果。"),
                MIAFeatureSpec(MIAFXFeatureSpectrum, @"频谱可视化", @"控制实时频谱绘制（同时决定是否请求音频服务）。"),
                MIAFeatureSpec(MIAFXFeatureRhythm, @"节拍律动", @"控制跟随节奏的整体律动偏移与缩放。"),
                MIAFeatureSpec(MIAFXFeatureMask, @"遮罩层", @"控制自定义遮罩贴图与图层顺序。"),
            ]),
            MIASection(@"渲染层级", @"决定特效层插入的位置。", @[
                MIAEnumSpec(@"Global.LayerMode", @"图层模式", @"选择特效挂载的层级。", @[
                    MIAOpt(@"自适应", @"跟随系统岛图层，兼容性最好。", @0),
                    MIAOpt(@"独立顶层窗口", @"额外窗口，避免被其他界面遮挡。", @1),
                    MIAOpt(@"岛内合成层", @"直接合成到岛图层内部，延迟最低。", @2),
                ]),
                MIANumberSpec(@"Global.FadeIn", @"淡入时长", @"总开关或特效开启时的淡入时间。", 0.0, 2.0, 0.05, 2, @"秒"),
            ]),
            MIASection(@"几何与尺寸校准", @"当机型或系统版本导致对位偏差时可手动微调。", @[
                MIANumberSpec(@"Geometry.ManualOffsetX", @"整体水平偏移", @"整组特效相对岛中心的水平偏移。", -200.0, 200.0, 0.5, 1, @"pt"),
                MIANumberSpec(@"Geometry.ManualOffsetY", @"整体垂直偏移", @"整组特效相对岛中心的垂直偏移。", -200.0, 200.0, 0.5, 1, @"pt"),
                MIANumberSpec(@"Geometry.CompactWidth", @"紧凑岛宽度", @"紧凑状态下的胶囊宽度基准值。", 60.0, 260.0, 1.0, 0, @"pt"),
                MIANumberSpec(@"Geometry.CompactHeight", @"紧凑岛高度", @"紧凑状态下的胶囊高度基准值。", 20.0, 80.0, 1.0, 0, @"pt"),
                MIANumberSpec(@"Geometry.ExpandedHeight", @"展开岛高度", @"展开状态下的胶囊高度基准值。", 60.0, 400.0, 1.0, 0, @"pt"),
            ]),
            MIASection(@"快捷操作", @"", @[
                MIAActionSpec(MIAFXActionOpenSystemSettings, @"打开系统设置入口", @"跳转到「设置 → MIAFX」的 PreferenceLoader 入口页。"),
                MIAActionSpec(MIAFXActionRespring, @"重新载入主屏幕（Respring）", @"部分改动需要重载 SpringBoard 才能生效。"),
            ]),
            MIASection(@"本组默认值", @"", @[
                MIAActionSpec(MIAFXResetPageIdentifier(@"global"), @"恢复本组默认", @"把全局与几何相关参数恢复为出厂值。"),
            ]),
        ];
        [pages addObject:page];
    }

    // 2) 灵动岛背景（紧凑 + 展开）
    {
        MIAFXSettingPage *page = [[MIAFXSettingPage alloc] init];
        page.identifier = @"islandBackground";
        page.title = @"灵动岛背景";
        page.pageDescription = @"把原生灵动岛的胶囊底色替换为自定义视频，紧凑与展开两种状态分别配置。";
        page.sections = @[
            MIASection(@"紧凑", @"未展开状态下胶囊内播放的背景视频；素材放到 Videos 目录，建议 1~3 秒循环、带透明通道。", @[
                MIASwitchSpec(@"Compact.Video.Enabled", @"启用紧凑背景", @"单独控制紧凑状态视频层（同时需要全局「视频层」位开启）。"),
                MIAPathSpec(@"Compact.Video.Path", @"背景视频", @"点击选择来源：可从相册添加、从「文件」选取，或在 Filza 中查看素材目录。"),
                MIAEnumSpec(@"Compact.Video.FillMode", @"填充模式", @"决定视频如何适配胶囊区域。", @[
                    MIAOpt(@"拉伸填满", @"拉伸到完整胶囊，可能变形。", @0),
                    MIAOpt(@"等比裁切", @"等比放大填满并裁切多余部分。", @1),
                    MIAOpt(@"等比适应", @"等比缩放完整放入，可能留边。", @2),
                ]),
                MIANumberSpec(@"Compact.Video.Alpha", @"视频透明度", @"数值越低越透。", 0.0, 1.0, 0.01, 2, @""),
                MIANumberSpec(@"Compact.Video.Scale", @"视频缩放", @"相对胶囊基准尺寸的倍率。", 0.2, 4.0, 0.01, 2, @"×"),
                MIANumberSpec(@"Compact.Video.OffsetX", @"水平偏移", @"正值向右。", -80.0, 80.0, 0.5, 1, @"pt"),
                MIANumberSpec(@"Compact.Video.OffsetY", @"垂直偏移", @"正值向下。", -60.0, 60.0, 0.5, 1, @"pt"),
                MIAEnumSpec(@"Compact.Video.CornerMode", @"圆角模式", @"控制视频层的裁切圆角。", @[
                    MIAOpt(@"直角", @"不做圆角裁切。", @0),
                    MIAOpt(@"跟随胶囊", @"自动使用高度一半的圆角。", @1),
                    MIAOpt(@"自定义半径", @"使用下方手动圆角半径。", @2),
                ]),
                MIADependent(MIANumberSpec(@"Compact.Video.CornerRadius", @"自定义圆角半径", @"仅在圆角模式为「自定义半径」时生效。", 0.0, 60.0, 0.5, 1, @"pt"), @"Compact.Video.CornerMode", @[@2]),
            ]),
            MIASection(@"展开", @"长按展开状态下胶囊内播放的背景视频；展开区域更高，建议使用横向比例更大的素材。", @[
                MIASwitchSpec(@"Expanded.Video.Enabled", @"启用展开背景", @"单独控制展开状态视频层（同时需要全局「视频层」位开启）。"),
                MIAPathSpec(@"Expanded.Video.Path", @"背景视频", @"点击选择来源：可从相册添加、从「文件」选取，或在 Filza 中查看素材目录。"),
                MIAEnumSpec(@"Expanded.Video.FillMode", @"填充模式", @"决定视频如何适配展开区域。", @[
                    MIAOpt(@"拉伸填满", @"拉伸到完整区域，可能变形。", @0),
                    MIAOpt(@"等比裁切", @"等比放大填满并裁切多余部分。", @1),
                    MIAOpt(@"等比适应", @"等比缩放完整放入，可能留边。", @2),
                ]),
                MIANumberSpec(@"Expanded.Video.Alpha", @"视频透明度", @"数值越低越透。", 0.0, 1.0, 0.01, 2, @""),
                MIANumberSpec(@"Expanded.Video.Scale", @"视频缩放", @"相对展开区域基准尺寸的倍率。", 0.2, 4.0, 0.01, 2, @"×"),
                MIANumberSpec(@"Expanded.Video.OffsetX", @"水平偏移", @"正值向右。", -120.0, 120.0, 0.5, 1, @"pt"),
                MIANumberSpec(@"Expanded.Video.OffsetY", @"垂直偏移", @"正值向下。", -120.0, 120.0, 0.5, 1, @"pt"),
                MIAEnumSpec(@"Expanded.Video.CornerMode", @"圆角模式", @"控制视频层的裁切圆角。", @[
                    MIAOpt(@"直角", @"不做圆角裁切。", @0),
                    MIAOpt(@"跟随胶囊", @"自动使用高度一半的圆角。", @1),
                    MIAOpt(@"自定义半径", @"使用下方手动圆角半径。", @2),
                ]),
                MIADependent(MIANumberSpec(@"Expanded.Video.CornerRadius", @"自定义圆角半径", @"仅在圆角模式为「自定义半径」时生效。", 0.0, 80.0, 0.5, 1, @"pt"), @"Expanded.Video.CornerMode", @[@2]),
            ]),
            MIASection(@"素材位置", @"", @[
                MIAActionSpec(MIAFXActionFilzaVideos, @"在 Filza 中打开视频目录", @"跳转到 Videos 文件夹查看/管理已导入的素材。"),
                MIAActionSpec(MIAFXActionFilzaLogs, @"打开诊断日志目录", @"视频背景不生效时，进入 Logs 目录把 video-diag.log 发给作者定位问题。"),
            ]),
            MIASection(@"诊断反馈", @"视频背景异常时，一键生成诊断文件直接发给作者。", @[
                MIAActionSpec(MIAFXActionShareDiagnostics, @"分享诊断日志", @"汇总运行日志、配置与素材清单为一个文件，通过微信/QQ/邮件直接发给作者。"),
                MIAActionSpec(MIAFXActionViewDiagnostics, @"查看诊断日志", @"在应用内直接查看最近的诊断记录，可截图反馈。"),
                MIAActionSpec(MIAFXActionClearDiagnostics, @"清空诊断日志", @"删除已有日志，重新开始记录。"),
            ]),
            MIASection(@"本组默认值", @"", @[
                MIAActionSpec(MIAFXResetPageIdentifier(@"islandBackground"), @"恢复本组默认", @"把紧凑与展开视频相关参数恢复为出厂值。"),
            ]),
        ];
        [pages addObject:page];
    }

    // 4) 呼吸
    {
        MIAFXSettingPage *page = [[MIAFXSettingPage alloc] init];
        page.identifier = @"breathing";
        page.title = @"呼吸";
        page.pageDescription = @"胶囊整体的周期性呼吸动效";
        page.sections = @[
            MIASection(@"呼吸动效", @"让整颗岛缓慢起伏，数值越大越明显。", @[
                MIASwitchSpec(@"Breathing.Enabled", @"启用呼吸", @"需要全局「呼吸动效」位开启。"),
                MIAEnumSpec(@"Breathing.Type", @"呼吸类型", @"选择呼吸的表现方式。", @[
                    MIAOpt(@"缩放呼吸", @"仅改变整体缩放。", @0),
                    MIAOpt(@"缩放 + 淡入淡出", @"缩放同时改变不透明度。", @1),
                    MIAOpt(@"位移浮动", @"整体上下轻微浮动。", @2),
                    MIAOpt(@"缩放 + 呼吸发光", @"缩放并叠加发光强度变化。", @3),
                ]),
                MIANumberSpec(@"Breathing.Amplitude", @"呼吸幅度", @"相对基准尺寸的变化比例。", 0.0, 0.5, 0.005, 3, @"×"),
                MIANumberSpec(@"Breathing.Period", @"呼吸周期", @"一次完整呼吸所需时间。", 0.2, 10.0, 0.05, 2, @"秒"),
                MIANumberSpec(@"Breathing.Phase", @"起始相位", @"0~1 个周期，用于错开多个动效。", 0.0, 1.0, 0.01, 2, @"周期"),
                MIANumberSpec(@"Breathing.Rate", @"速率倍率", @"在周期基础上的整体加速/减速。", 0.1, 5.0, 0.05, 2, @"×"),
                MIASwitchSpec(@"Breathing.Muted", @"静音模式", @"开启后在来电或媒体会话期间暂停呼吸。"),
                MIANumberSpec(@"Breathing.FadeIn", @"淡入时长", @"呼吸进入时的渐变时间。", 0.0, 2.0, 0.05, 2, @"秒"),
            ]),
            MIASection(@"本组默认值", @"", @[
                MIAActionSpec(MIAFXResetPageIdentifier(@"breathing"), @"恢复本组默认", @"把呼吸相关参数恢复为出厂值。"),
            ]),
        ];
        [pages addObject:page];
    }

    // 5) 紧凑左/右原生元素 + 6) 展开音轨/侧边元素
    NSArray<NSArray<NSString *> *> *nativeGroups = @[
        @[@"Native.CompactLeft", @"紧凑左侧元素", @"nativeCompactLeft"],
        @[@"Native.CompactRight", @"紧凑右侧元素", @"nativeCompactRight"],
        @[@"Native.ExpandedTrack", @"展开音轨元素", @"nativeExpandedTrack"],
        @[@"Native.ExpandedSide", @"展开侧边元素", @"nativeExpandedSide"],
    ];
    NSArray<NSString *> *nativeDescriptions = @[
        @"例如灵动岛左边的图标/计时控件。",
        @"例如灵动岛右边的电量或图标控件。",
        @"展开后中间的音轨/波形区域。",
        @"展开后左右两侧的辅助信息区域。",
    ];
    NSUInteger nativeIndex = 0;
    for (NSArray<NSString *> *tuple in nativeGroups) {
        NSString *prefix = tuple[0];
        NSString *groupTitle = tuple[1];
        NSString *identifier = tuple[2];
        MIAFXSettingPage *page = [[MIAFXSettingPage alloc] init];
        page.identifier = identifier;
        page.title = groupTitle;
        page.pageDescription = nativeDescriptions[nativeIndex];
        NSString * (^makeKey)(NSString *) = ^NSString *(NSString *suffix) {
            return [NSString stringWithFormat:@"%@.%@", prefix, suffix];
        };
        page.sections = @[
            MIASection(groupTitle, @"原生元素的变换只作用于系统自身的控件，需要全局「原生元素变换」位开启。", @[
                MIASwitchSpec(makeKey(@"Enabled"), [NSString stringWithFormat:@"启用%@", groupTitle], @"单独开关，便于逐项调试。"),
                MIAEnumSpec(makeKey(@"Direction"), @"运动方向", @"决定元素的进出方向。", @[
                    MIAOpt(@"常态", @"保持系统默认位置与朝向。", @0),
                    MIAOpt(@"展开外扩", @"向外展开，让元素远离岛中心。", @1),
                ]),
                MIANumberSpec(makeKey(@"Speed"), @"运动速度", @"越大越快。", 0.05, 5.0, 0.05, 2, @"×"),
                MIANumberSpec(makeKey(@"Scale"), @"元素缩放", @"相对系统原始尺寸。", 0.2, 4.0, 0.05, 2, @"×"),
                MIAIntegerSpec(makeKey(@"FPS"), @"渲染帧率", @"该元素专属的绘制帧率上限。", 1, 120, 1, @"fps"),
                MIANumberSpec(makeKey(@"OffsetX"), @"水平偏移", @"正值向右。", -80.0, 80.0, 0.5, 1, @"pt"),
                MIANumberSpec(makeKey(@"OffsetY"), @"垂直偏移", @"正值向下。", -80.0, 80.0, 0.5, 1, @"pt"),
            ]),
            MIASection(@"本组默认值", @"", @[
                MIAActionSpec(MIAFXResetPageIdentifier(identifier), @"恢复本组默认", [NSString stringWithFormat:@"把%@相关参数恢复为出厂值。", groupTitle]),
            ]),
        ];
        [pages addObject:page];
        nativeIndex += 1;
    }

    // 7) 遮罩与层级
    {
        MIAFXSettingPage *page = [[MIAFXSettingPage alloc] init];
        page.identifier = @"mask";
        page.title = @"遮罩";
        page.pageDescription = @"自定义遮罩贴图与图层顺序";
        page.sections = @[
            MIASection(@"遮罩层", @"遮罩可以裁切或柔化整组特效的边缘，需要全局「遮罩层」位开启。", @[
                MIASwitchSpec(@"Mask.Enabled", @"启用遮罩", @"关闭后完全不加载遮罩贴图。"),
                MIAPathSpec(@"Mask.Path", @"遮罩图片路径", @"建议使用带 alpha 通道的 PNG，放到 Masks 目录。"),
                MIANumberSpec(@"Mask.Alpha", @"遮罩强度", @"越低越接近原样。", 0.0, 1.0, 0.01, 2, @""),
                MIASwitchSpec(@"Mask.Invert", @"反转遮罩", @"把保留区域与裁切区域互换。"),
                MIAIntegerSpec(@"Mask.ZIndex", @"图层顺序", @"数值越大越靠上层。", -10, 10, 1, @"层"),
            ]),
            MIASection(@"素材位置", @"", @[
                MIAActionSpec(MIAFXActionFilzaMasks, @"在 Filza 中打开遮罩目录", @"跳转到数据目录下的 Masks 文件夹。"),
            ]),
            MIASection(@"本组默认值", @"", @[
                MIAActionSpec(MIAFXResetPageIdentifier(@"mask"), @"恢复本组默认", @"把遮罩相关参数恢复为出厂值。"),
            ]),
        ];
        [pages addObject:page];
    }

    // 8) 双层流光跑马灯
    {
        MIAFXSettingPage *page = [[MIAFXSettingPage alloc] init];
        page.identifier = @"marquee";
        page.title = @"流光";
        page.pageDescription = @"胶囊边缘双层跑马灯光带";
        page.sections = @[
            MIASection(@"跑马灯", @"需要全局「双层流光跑马灯」位开启。", @[
                MIASwitchSpec(@"Marquee.Enabled", @"启用跑马灯", @"主光带开关。"),
                MIAEnumSpec(@"Marquee.Palette", @"配色方案", @"决定两层光带的颜色循环。", @[
                    MIAOpt(@"冰蓝极地", @"冷色，偏低调。", @0),
                    MIAOpt(@"霓虹粉紫", @"洋红到紫色渐变。", @1),
                    MIAOpt(@"熔岩橙红", @"暖色高对比。", @2),
                    MIAOpt(@"极光青绿", @"青绿渐变，通透。", @3),
                    MIAOpt(@"彩虹渐变", @"全色相循环。", @4),
                ]),
                MIAEnumSpec(@"Marquee.BlendMode", @"混合模式", @"决定光带与背景的叠加方式。", @[
                    MIAOpt(@"正常", @"直接覆盖绘制。", @0),
                    MIAOpt(@"叠加", @"保留底层明暗。", @1),
                    MIAOpt(@"滤色", @"提亮底层亮部。", @2),
                    MIAOpt(@"加色", @"线性增加亮度，最亮。", @3),
                ]),
                MIANumberSpec(@"Marquee.Angle", @"流光角度", @"光带的流动方向。", 0.0, 360.0, 1.0, 0, @"°"),
                MIANumberSpec(@"Marquee.Strength", @"流光强度", @"亮度倍数。", 0.0, 2.0, 0.01, 2, @"×"),
                MIANumberSpec(@"Marquee.ShiftSpeed", @"流动速度", @"每秒流动多少个循环。", 0.0, 5.0, 0.05, 2, @"×"),
                MIANumberSpec(@"Marquee.ShiftAmplitude", @"位移幅度", @"光带沿边缘的最大偏移量。", 0.0, 40.0, 0.5, 1, @"pt"),
                MIANumberSpec(@"Marquee.LineWidth", @"线宽", @"光带的宽度。", 0.2, 12.0, 0.1, 1, @"pt"),
            ]),
            MIASection(@"第二层流光", @"双层構成可以让边缘更有层次。", @[
                MIASwitchSpec(@"Marquee.SecondaryEnabled", @"启用第二层", @"关闭后只绘制单层光带。"),
                MIANumberSpec(@"Marquee.SecondaryPhase", @"第二层相位", @"两层之间的错开比例。", 0.0, 1.0, 0.01, 2, @"周期"),
            ]),
            MIASection(@"边缘圆角", @"", @[
                MIAEnumSpec(@"Marquee.CornerMode", @"圆角模式", @"决定光带路径的形状。", @[
                    MIAOpt(@"直角", @"矩形路径。", @0),
                    MIAOpt(@"跟随胶囊", @"自动使用胶囊圆角。", @1),
                    MIAOpt(@"自定义半径", @"使用手动圆角半径。", @2),
                ]),
                MIADependent(MIANumberSpec(@"Marquee.CornerRadius", @"自定义圆角半径", @"仅在圆角模式为「自定义半径」时生效。", 0.0, 60.0, 0.5, 1, @"pt"), @"Marquee.CornerMode", @[@2]),
            ]),
            MIASection(@"本组默认值", @"", @[
                MIAActionSpec(MIAFXResetPageIdentifier(@"marquee"), @"恢复本组默认", @"把跑马灯相关参数恢复为出厂值。"),
            ]),
        ];
        [pages addObject:page];
    }

    // 9) 19 轨迹
    {
        MIAFXSettingPage *page = [[MIAFXSettingPage alloc] init];
        page.identifier = @"orbit";
        page.title = @"轨迹";
        page.pageDescription = @"19 种内置轨道轨迹 + 自定义轨迹";
        page.sections = @[
            MIASection(@"轨道", @"需要全局「19 轨迹」位开启。选择「自定义轨迹」后请填入 CustomOrbits 目录内的资源路径。", @[
                MIASwitchSpec(@"Orbit.Enabled", @"启用轨迹运动", @"沿轨迹运动的粒子群开关。"),
                MIAEnumSpec(@"Orbit.Asset", @"轨迹样式", @"内置 19 种轨迹，或自定义资源。", @[
                    MIAOpt(@"双子星", @"两点对称环绕。", @0),
                    MIAOpt(@"三叶草", @"三点交错。", @1),
                    MIAOpt(@"螺旋", @"向内收拢的螺旋。", @2),
                    MIAOpt(@"心跳", @"带停顿的脉冲式轨迹。", @3),
                    MIAOpt(@"涟漪", @"由内向外扩散。", @4),
                    MIAOpt(@"彗星", @"带尾迹的单点轨迹。", @5),
                    MIAOpt(@"蜂巢", @"六边形蜂窝分布。", @6),
                    MIAOpt(@"流星", @"快速掠过的一次性轨迹。", @7),
                    MIAOpt(@"环轨", @"沿胶囊边环围绕。", @8),
                    MIAOpt(@"蝴蝶", @"双翼对称轨迹。", @9),
                    MIAOpt(@"潮汐", @"缓慢的长周期往复。", @10),
                    MIAOpt(@"花瓣", @"五瓣对称。", @11),
                    MIAOpt(@"陨石雨", @"多点随机坠落。", @12),
                    MIAOpt(@"天线波", @"类信号波纹。", @13),
                    MIAOpt(@"棋盘", @"交错网格分布。", @14),
                    MIAOpt(@"双螺旋", @"两组反向螺旋。", @15),
                    MIAOpt(@"脉冲环", @"周期性扩张的同心环。", @16),
                    MIAOpt(@"编织", @"交叉往复。", @17),
                    MIAOpt(@"星尘", @"随机微粒子云。", @18),
                    MIAOpt(@"自定义轨迹", @"使用下方 CustomPath 指定的资源。", @19),
                ]),
                MIADependent(MIAPathSpec(@"Orbit.CustomPath", @"自定义轨迹资源", @"仅当轨迹样式为「自定义轨迹」时生效。"), @"Orbit.Asset", @[@19]),
                MIAIntegerSpec(@"Orbit.Count", @"粒子数量", @"同时存在的粒子个数，越多越耗电。", 1, 64, 1, @"个"),
                MIAEnumSpec(@"Orbit.Shape", @"粒子形状", @"单个粒子的外观。", @[
                    MIAOpt(@"圆形", @"默认圆点。", @0),
                    MIAOpt(@"胶囊", @"横向胶囊形。", @1),
                    MIAOpt(@"菱形", @"菱形颗粒。", @2),
                    MIAOpt(@"方块", @"方形颗粒。", @3),
                ]),
                MIASwitchSpec(@"Orbit.Reverse", @"反向运动", @"沿轨迹倒着走。"),
                MIANumberSpec(@"Orbit.Speed", @"运动速度", @"每秒完成的圈数。", 0.02, 5.0, 0.01, 2, @"×"),
                MIANumberSpec(@"Orbit.RadiusX", @"横向半径", @"相对胶囊宽度的倍率。", 0.0, 2.0, 0.01, 2, @"×"),
                MIANumberSpec(@"Orbit.RadiusY", @"纵向半径", @"相对胶囊高度的倍率。", 0.0, 2.0, 0.01, 2, @"×"),
                MIANumberSpec(@"Orbit.ExpandRatio", @"展开扩张比", @"展开状态额外扩张的比例。", 0.0, 1.0, 0.01, 2, @""),
                MIANumberSpec(@"Orbit.Glow", @"发光强度", @"粒子的光晕亮度。", 0.0, 1.0, 0.01, 2, @""),
                MIANumberSpec(@"Orbit.Swing", @"摆动幅度", @"粒子沿法线方向的抖动量。", 0.0, 1.0, 0.01, 2, @""),
                MIANumberSpec(@"Orbit.Scale", @"粒子缩放", @"相对默认粒子尺寸。", 0.2, 4.0, 0.05, 2, @"×"),
                MIANumberSpec(@"Orbit.Alpha", @"不透明度", @"越低越透。", 0.0, 1.0, 0.01, 2, @""),
            ]),
            MIASection(@"素材位置", @"", @[
                MIAActionSpec(MIAFXActionFilzaCustomOrbits, @"在 Filza 中打开自定义轨迹目录", @"跳转到数据目录下的 CustomOrbits 文件夹。"),
            ]),
            MIASection(@"本组默认值", @"", @[
                MIAActionSpec(MIAFXResetPageIdentifier(@"orbit"), @"恢复本组默认", @"把轨迹相关参数恢复为出厂值。"),
            ]),
        ];
        [pages addObject:page];
    }

    // 10) 液滴
    {
        MIAFXSettingPage *page = [[MIAFXSettingPage alloc] init];
        page.identifier = @"metaball";
        page.title = @"液滴";
        page.pageDescription = @"Metaball 融合液滴";
        page.sections = @[
            MIASection(@"液滴", @"需要全局「液滴融合球」位开启。数量与尺寸越大越耗 GPU。", @[
                MIASwitchSpec(@"Metaball.Enabled", @"启用液滴", @"液滴图层开关。"),
                MIAIntegerSpec(@"Metaball.Count", @"液滴数量", @"同时模拟的球体个数。", 1, 16, 1, @"个"),
                MIANumberSpec(@"Metaball.Speed", @"流动速度", @"越大运动越快。", 0.0, 5.0, 0.05, 2, @"×"),
                MIANumberSpec(@"Metaball.Size", @"基准尺寸", @"单个液滴的直径。", 1.0, 60.0, 0.5, 1, @"pt"),
                MIANumberSpec(@"Metaball.Deformation", @"形变强度", @"液滴被拉扯变形的程度。", 0.0, 1.0, 0.01, 2, @""),
                MIANumberSpec(@"Metaball.Fusion", @"融合阈值", @"越大越容易黏连成一团。", 0.0, 1.0, 0.01, 2, @""),
                MIASwitchSpec(@"Metaball.Rainbow", @"彩虹着色", @"按位置着色，关闭则跟随当前配色。"),
                MIANumberSpec(@"Metaball.Highlight", @"高光强度", @"顶部高光的亮度。", 0.0, 1.0, 0.01, 2, @""),
            ]),
            MIASection(@"本组默认值", @"", @[
                MIAActionSpec(MIAFXResetPageIdentifier(@"metaball"), @"恢复本组默认", @"把液滴相关参数恢复为出厂值。"),
            ]),
        ];
        [pages addObject:page];
    }

    // 11) 频谱
    {
        MIAFXSettingPage *page = [[MIAFXSettingPage alloc] init];
        page.identifier = @"spectrum";
        page.title = @"频谱";
        page.pageDescription = @"实时音频频谱可视化";
        page.sections = @[
            MIASection(@"频谱", @"需要全局「频谱可视化」位开启，此时才会向音频服务请求数据。", @[
                MIASwitchSpec(@"Spectrum.Enabled", @"启用频谱", @"关闭后完全不请求音频数据。"),
                MIAEnumSpec(@"Spectrum.Form", @"频谱形态", @"决定条带的排布方式。", @[
                    MIAOpt(@"环形放射", @"围绕胶囊一圈放射。", @0),
                    MIAOpt(@"底部条形", @"沿底边横向排列。", @1),
                    MIAOpt(@"镜像双向", @"中部对称向两侧。", @2),
                    MIAOpt(@"折线波形", @"连接成折线。", @3),
                ]),
                MIAIntegerSpec(@"Spectrum.Bars", @"条带数量", @"越多细节越丰富，开销也越大。", 8, 256, 1, @"条"),
                MIANumberSpec(@"Spectrum.Scale", @"整体缩放", @"相对默认排布半径。", 0.2, 4.0, 0.05, 2, @"×"),
                MIANumberSpec(@"Spectrum.Radius", @"基准半径", @"环形形态下的内半径。", 0.0, 120.0, 1.0, 0, @"pt"),
                MIANumberSpec(@"Spectrum.Length", @"条纹长度", @"低频到高频的最大长度。", 2.0, 120.0, 1.0, 0, @"pt"),
                MIANumberSpec(@"Spectrum.Thickness", @"条纹粗细", @"单根条纹的线宽。", 0.5, 12.0, 0.1, 1, @"pt"),
                MIANumberSpec(@"Spectrum.Sensitivity", @"灵敏度", @"输入增益倍数。", 0.1, 5.0, 0.05, 2, @"×"),
                MIANumberSpec(@"Spectrum.Smoothing", @"平滑系数", @"越大越顺滑但响应越慢，建议 <0.95。", 0.0, 0.98, 0.01, 2, @""),
                MIANumberSpec(@"Spectrum.BPMLink", @"节拍联动强度", @"把条带长度跟随节拍进行缩放的程度。", 0.0, 1.0, 0.01, 2, @""),
                MIANumberSpec(@"Spectrum.Rotation", @"整体旋转", @"绕中心旋转的角度。", 0.0, 360.0, 1.0, 0, @"°"),
                MIASwitchSpec(@"Spectrum.Rainbow", @"彩虹着色", @"按频段着色，关闭则使用配色方案。"),
                MIANumberSpec(@"Spectrum.Bloom", @"泛光强度", @"条带周围的光晕。", 0.0, 1.0, 0.01, 2, @""),
            ]),
            MIASection(@"本组默认值", @"", @[
                MIAActionSpec(MIAFXResetPageIdentifier(@"spectrum"), @"恢复本组默认", @"把频谱相关参数恢复为出厂值。"),
            ]),
        ];
        [pages addObject:page];
    }

    // 12) 律动
    {
        MIAFXSettingPage *page = [[MIAFXSettingPage alloc] init];
        page.identifier = @"rhythm";
        page.title = @"律动";
        page.pageDescription = @"跟随节奏的整体律动位移与缩放（受全局「节拍律动」位控制）";
        page.sections = @[
            MIASection(@"节拍律动", @"这组没有独立的 Enabled 开关，由总开关与 FeatureMask 的「节拍律动」位统一控制。", @[
                MIANumberSpec(@"MIAFXRhythmOffsetX", @"律动水平偏移", @"节拍命中时整体左右位移的最大值。", -120.0, 120.0, 0.5, 1, @"pt"),
                MIANumberSpec(@"MIAFXRhythmOffsetY", @"律动垂直偏移", @"节拍命中时整体上下位移的最大值。", -120.0, 120.0, 0.5, 1, @"pt"),
                MIANumberSpec(@"MIAFXRhythmScale", @"律动缩放幅度", @"节拍命中时额外放大的比例。", 0.0, 0.5, 0.005, 3, @"×"),
            ]),
            MIASection(@"本组默认值", @"", @[
                MIAActionSpec(MIAFXResetPageIdentifier(@"rhythm"), @"恢复本组默认", @"把律动相关参数恢复为出厂值。"),
            ]),
        ];
        [pages addObject:page];
    }

    // 13) 性能与休眠
    {
        MIAFXSettingPage *page = [[MIAFXSettingPage alloc] init];
        page.identifier = @"performance";
        page.title = @"性能";
        page.pageDescription = @"帧率、休眠策略与调试日志";
        page.sections = @[
            MIASection(@"性能档位", @"也可以在「预设」页使用一键性能预设。", @[
                MIAEnumSpec(@"Global.PerformanceTier", @"性能档位", @"整体渲染预算，影响内部降级策略。", @[
                    MIAOpt(@"节能", @"优先省电，牺牲复杂度。", @0),
                    MIAOpt(@"均衡", @"默认推荐。", @1),
                    MIAOpt(@"华丽", @"允许更激进的效果组合。", @2),
                ]),
                MIAIntegerSpec(@"Global.MaxFPS", @"最高帧率", @"全局帧率上限，受最高120fps机型限制。", 10, 120, 1, @"fps"),
            ]),
            MIASection(@"休眠策略", @"屏幕熄灭后是否继续渲染，直接影响耗电。", @[
                MIAEnumSpec(@"Global.SleepPolicy", @"息屏策略", @"息屏时的渲染行为。", @[
                    MIAOpt(@"智能暂停", @"息屏后完全停止渲染。", @0),
                    MIAOpt(@"降帧运行", @"息屏后降低到最低帧率继续运行。", @1),
                    MIAOpt(@"常驻渲染", @"息屏仍然按最高帧率渲染，耗电较高。", @2),
                ]),
            ]),
            MIASection(@"诊断开关", @"", @[
                MIASwitchSpec(@"Global.DebugLog", @"调试日志", @"开启后把运行日志写入 Logs/miafx.log。"),
                MIAActionSpec(MIAFXActionFilzaLogs, @"在 Filza 中打开日志目录", @"跳转到数据目录下的 Logs 文件夹。"),
            ]),
            MIASection(@"本组默认值", @"", @[
                MIAActionSpec(MIAFXResetPageIdentifier(@"performance"), @"恢复本组默认", @"把性能与休眠相关参数恢复为出厂值。"),
            ]),
        ];
        [pages addObject:page];
    }

    // 14) 预设
    {
        MIAFXSettingPage *page = [[MIAFXSettingPage alloc] init];
        page.identifier = @"presets";
        page.title = @"预设";
        page.pageDescription = @"一键调色、一键性能与全局恢复";
        page.sections = @[
            MIASection(@"调色预设", @"只覆盖外观相关参数（配色方案、彩虹、泛光、发光等），不改变开关状态。", @[
                MIAActionSpec(MIAFXPresetThemeIdentifier(@"neon"), @"霓虹", @"洋红到紫的高对比城市夜色。"),
                MIAActionSpec(MIAFXPresetThemeIdentifier(@"aurora"), @"极光", @"青绿通透，柔和飘动。"),
                MIAActionSpec(MIAFXPresetThemeIdentifier(@"lava"), @"熔岩", @"橙红暖色，强调炽热与绽放。"),
                MIAActionSpec(MIAFXPresetThemeIdentifier(@"ice"), @"冰晶", @"冰蓝冷调，锐利清透。"),
                MIAActionSpec(MIAFXPresetThemeIdentifier(@"candy"), @"糖果", @"粉蓝糖果色，明亮轻盈。"),
            ]),
            MIASection(@"性能预设", @"会同时调整性能档位、帧率与部分特效的规模档位。", @[
                MIAActionSpec(MIAFXPresetPerformanceIdentifier(@"eco"), @"节能", @"最低帧率 + 简化规模，续航优先。"),
                MIAActionSpec(MIAFXPresetPerformanceIdentifier(@"balanced"), @"均衡", @"默认值组合，平衡观感与耗电。"),
                MIAActionSpec(MIAFXPresetPerformanceIdentifier(@"gorgeous"), @"华丽", @"更高帧率与更密的粒子/条带。"),
            ]),
            MIASection(@"配置迁移", @"", @[
                MIAActionSpec(MIAFXActionExportConfiguration, @"导出配置 plist", @"把当前全部参数导出为 settings.plist。"),
                MIAActionSpec(MIAFXActionImportConfiguration, @"导入配置 plist", @"从 plist 恢复配置，仅写入已知参数。"),
                MIAActionSpec(MIAFXActionShareConfiguration, @"分享配置文件", @"通过系统分享面板发送当前配置。"),
                MIAActionSpec(MIAFXActionFilzaPresets, @"在 Filza 中打开预设目录", @"跳转到数据目录下的 Presets 文件夹。"),
            ]),
            MIASection(@"全部重置", @"", @[
                MIAActionSpec(@"reset.all", @"恢复全部默认", @"清空所有自定义参数，恢复到出厂状态。"),
            ]),
        ];
        [pages addObject:page];
    }

    // 15) 素材与诊断
    {
        MIAFXSettingPage *page = [[MIAFXSettingPage alloc] init];
        page.identifier = @"assets";
        page.title = @"素材";
        page.pageDescription = @"素材目录、配置文件与故障诊断";
        page.sections = @[
            MIASection(@"素材目录", @"在 Filza 中打开对应目录，直接丢入文件即可被识别。", @[
                MIAActionSpec(MIAFXActionFilzaVideos, @"视频素材目录", @"Videos：紧凑/展开视频。"),
                MIAActionSpec(MIAFXActionFilzaMasks, @"遮罩素材目录", @"Masks：遮罩贴图。"),
                MIAActionSpec(MIAFXActionFilzaCustomOrbits, @"自定义轨迹目录", @"CustomOrbits：自定义轨道资源。"),
                MIAActionSpec(MIAFXActionFilzaPresets, @"预设目录", @"Presets：导入导出的配置文件。"),
                MIAActionSpec(MIAFXActionFilzaLogs, @"日志目录", @"Logs：运行日志。"),
                MIAActionSpec(MIAFXActionFilzaConfiguration, @"配置文件", @"Preferences/settings.plist，当前生效的配置。"),
            ]),
            MIASection(@"诊断", @"读取 diagnostics.plist 与 panic.plist，排查崩溃与启动保护。", @[
                MIAActionSpec(MIAFXActionDiagnostics, @"打开诊断页", @"显示运行时状态、panic 计数与路径信息。"),
                MIAActionSpec(MIAFXActionShareDiagnostics, @"分享诊断日志", @"汇总运行日志、配置与素材清单为一个文件，通过微信/QQ/邮件直接发给作者。"),
                MIAActionSpec(MIAFXActionResetProtection, @"重置启动保护计数", @"清除 panic.plist 中的连续启动计数。"),
                MIAActionSpec(MIAFXActionRescanAssets, @"重新扫描素材", @"通知后台重新扫描素材目录。"),
                MIAActionSpec(MIAFXActionRespring, @"Respring", @"重载 SpringBoard 使部分改动生效。"),
            ]),
        ];
        [pages addObject:page];
    }

    self.pages = pages;
    [self registerPages:pages];
}

- (void)buildPresets {
    NSMutableArray<MIAFXSettingPreset *> *themes = [NSMutableArray array];
    [themes addObject:[self themePresetWithIdentifier:@"neon"
                                                title:@"霓虹"
                                          description:@"洋红到紫色渐变，城市夜色风格"
                                            palette:@1
                                       secondaryPhase:0.42
                                            strength:1.25
                                           lineWidth:2.4
                                             orbitGlow:0.85
                                             metaballHighlight:0.62
                                              spectrumBloom:0.78
                                              fusion:0.72]];
    [themes addObject:[self themePresetWithIdentifier:@"aurora"
                                                title:@"极光"
                                          description:@"青绿通透，柔和飘动"
                                            palette:@3
                                       secondaryPhase:0.5
                                            strength:1.0
                                           lineWidth:2.0
                                             orbitGlow:0.7
                                             metaballHighlight:0.5
                                              spectrumBloom:0.62
                                              fusion:0.66]];
    [themes addObject:[self themePresetWithIdentifier:@"lava"
                                                title:@"熔岩"
                                          description:@"橙红暖色，炽热绽放"
                                            palette:@2
                                       secondaryPhase:0.35
                                            strength:1.4
                                           lineWidth:3.0
                                             orbitGlow:0.92
                                             metaballHighlight:0.7
                                              spectrumBloom:0.85
                                              fusion:0.78]];
    [themes addObject:[self themePresetWithIdentifier:@"ice"
                                                title:@"冰晶"
                                          description:@"冰蓝冷调，锐利清透"
                                            palette:@0
                                       secondaryPhase:0.55
                                            strength:0.95
                                           lineWidth:1.6
                                             orbitGlow:0.55
                                             metaballHighlight:0.4
                                              spectrumBloom:0.5
                                              fusion:0.58]];
    [themes addObject:[self themePresetWithIdentifier:@"candy"
                                                title:@"糖果"
                                          description:@"粉蓝糖果色，明亮轻盈"
                                            palette:@4
                                       secondaryPhase:0.6
                                            strength:1.1
                                           lineWidth:2.2
                                             orbitGlow:0.75
                                             metaballHighlight:0.58
                                              spectrumBloom:0.7
                                              fusion:0.7]];
    self.themePresets = themes;

    NSMutableArray<MIAFXSettingPreset *> *performance = [NSMutableArray array];
    MIAFXSettingPreset *eco = [[MIAFXSettingPreset alloc] init];
    eco.identifier = @"eco";
    eco.title = @"节能";
    eco.presetDescription = @"最低帧率与最小规模，续航优先";
    eco.values = @{
        @"Global.PerformanceTier": @0,
        @"Global.MaxFPS": @24,
        @"Global.SleepPolicy": @0,
        @"Orbit.Count": @2,
        @"Metaball.Count": @3,
        @"Spectrum.Bars": @16,
        @"Spectrum.Bloom": @0.35,
        @"Marquee.SecondaryEnabled": @NO,
        @"Marquee.Strength": @0.7,
        @"Breathing.Amplitude": @0.05,
    };
    [performance addObject:eco];

    MIAFXSettingPreset *balanced = [[MIAFXSettingPreset alloc] init];
    balanced.identifier = @"balanced";
    balanced.title = @"均衡";
    balanced.presetDescription = @"默认推荐组合";
    balanced.values = @{
        @"Global.PerformanceTier": @1,
        @"Global.MaxFPS": @30,
        @"Global.SleepPolicy": @0,
        @"Orbit.Count": @3,
        @"Metaball.Count": @4,
        @"Spectrum.Bars": @32,
        @"Spectrum.Bloom": @0.6,
        @"Marquee.SecondaryEnabled": @YES,
        @"Marquee.Strength": @0.8,
        @"Breathing.Amplitude": @0.08,
    };
    [performance addObject:balanced];

    MIAFXSettingPreset *gorgeous = [[MIAFXSettingPreset alloc] init];
    gorgeous.identifier = @"gorgeous";
    gorgeous.title = @"华丽";
    gorgeous.presetDescription = @"更高帧率与更密的粒子/条带";
    gorgeous.values = @{
        @"Global.PerformanceTier": @2,
        @"Global.MaxFPS": @60,
        @"Global.SleepPolicy": @0,
        @"Orbit.Count": @8,
        @"Metaball.Count": @8,
        @"Spectrum.Bars": @64,
        @"Spectrum.Bloom": @0.8,
        @"Marquee.SecondaryEnabled": @YES,
        @"Marquee.Strength": @1.1,
        @"Breathing.Amplitude": @0.12,
    };
    [performance addObject:gorgeous];
    self.performancePresets = performance;
}

- (MIAFXSettingPreset *)themePresetWithIdentifier:(NSString *)identifier
                                            title:(NSString *)title
                                      description:(NSString *)description
                                          palette:(NSNumber *)palette
                                  secondaryPhase:(double)secondaryPhase
                                        strength:(double)strength
                                       lineWidth:(double)lineWidth
                                       orbitGlow:(double)orbitGlow
                                metaballHighlight:(double)metaballHighlight
                                   spectrumBloom:(double)spectrumBloom
                                          fusion:(double)fusion {
    MIAFXSettingPreset *preset = [[MIAFXSettingPreset alloc] init];
    preset.identifier = identifier;
    preset.title = title;
    preset.presetDescription = description;
    preset.values = @{
        @"Marquee.Palette": palette,
        @"Marquee.SecondaryPhase": @(secondaryPhase),
        @"Marquee.Strength": @(strength),
        @"Marquee.LineWidth": @(lineWidth),
        @"Orbit.Glow": @(orbitGlow),
        @"Metaball.Highlight": @(metaballHighlight),
        @"Metaball.Rainbow": @YES,
        @"Metaball.Fusion": @(fusion),
        @"Spectrum.Rainbow": @YES,
        @"Spectrum.Bloom": @(spectrumBloom),
    };
    return preset;
}

#pragma mark 查询

- (MIAFXSettingPage *)pageWithIdentifier:(NSString *)identifier {
    for (MIAFXSettingPage *page in self.pages) {
        if ([page.identifier isEqualToString:identifier]) return page;
    }
    return nil;
}

- (NSArray<MIAFXSettingPage *> *)filteredPagesForQuery:(NSString *)query {
    NSString *trimmed = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return @[];
    NSString *lowered = trimmed.lowercaseString;
    NSMutableArray<MIAFXSettingPage *> *results = [NSMutableArray array];
    for (MIAFXSettingPage *page in self.pages) {
        NSMutableArray<MIAFXSettingSection *> *sections = [NSMutableArray array];
        for (MIAFXSettingSection *section in page.sections) {
            NSMutableArray<MIAFXSettingSpec *> *items = [NSMutableArray array];
            for (MIAFXSettingSpec *spec in section.items) {
                BOOL matched = NO;
                matched = matched || ([spec.title rangeOfString:lowered options:NSCaseInsensitiveSearch].location != NSNotFound);
                matched = matched || ([spec.specDescription rangeOfString:lowered options:NSCaseInsensitiveSearch].location != NSNotFound);
                matched = matched || ([spec.key rangeOfString:lowered options:NSCaseInsensitiveSearch].location != NSNotFound);
                matched = matched || ([page.title rangeOfString:lowered options:NSCaseInsensitiveSearch].location != NSNotFound);
                if (!matched) {
                    for (MIAFXSettingOption *option in spec.options) {
                        if ([option.title rangeOfString:lowered options:NSCaseInsensitiveSearch].location != NSNotFound) { matched = YES; break; }
                    }
                }
                if (matched) [items addObject:spec];
            }
            if (items.count > 0) {
                MIAFXSettingSection *clone = [MIAFXSettingSection sectionWithTitle:section.title footer:section.footer items:items];
                [sections addObject:clone];
            }
        }
        if (sections.count > 0) {
            MIAFXSettingPage *clone = [[MIAFXSettingPage alloc] init];
            clone.identifier = page.identifier;
            clone.title = page.title;
            clone.pageDescription = page.pageDescription;
            clone.sections = sections;
            [results addObject:clone];
        }
    }
    return results;
}

- (NSUInteger)settingCount {
    NSMutableSet<NSString *> *keys = [NSMutableSet set];
    for (MIAFXSettingPage *page in self.pages) {
        for (MIAFXSettingSection *section in page.sections) {
            for (MIAFXSettingSpec *spec in section.items) {
                if (spec.key.length > 0) [keys addObject:spec.key];
            }
        }
    }
    return keys.count;
}

- (NSArray<NSString *> *)uncoveredKeys {
    NSMutableSet<NSString *> *covered = [NSMutableSet set];
    for (MIAFXSettingPage *page in self.pages) {
        for (MIAFXSettingSection *section in page.sections) {
            for (MIAFXSettingSpec *spec in section.items) {
                if (spec.key.length > 0) [covered addObject:spec.key];
            }
        }
    }
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    for (NSString *key in MIAFXDefaultSettings()) {
        if ([key isEqualToString:@"SchemaVersion"]) continue; // 内部版本号，非用户可调
        if (![covered containsObject:key]) [missing addObject:key];
    }
    return [missing sortedArrayUsingSelector:@selector(compare:)];
}

- (NSArray<NSString *> *)unknownKeys {
    NSMutableArray<NSString *> *unknown = [NSMutableArray array];
    NSDictionary<NSString *, id> *defaults = MIAFXDefaultSettings();
    for (NSString *key in self.specsByKey) {
        if (defaults[key] == nil) [unknown addObject:key];
    }
    return [unknown sortedArrayUsingSelector:@selector(compare:)];
}

#pragma mark 读写

- (id)valueForSpec:(MIAFXSettingSpec *)spec {
    return [spec currentValue];
}

- (void)stageDouble:(double)value forSpec:(MIAFXSettingSpec *)spec {
    double snapped = [spec snap:value];
    if (spec.numberMode == MIAFXNumberModeInteger) {
        [[MIAFXConfig sharedConfig] setObject:@((NSInteger)llround(snapped)) forKey:spec.key];
    } else {
        [[MIAFXConfig sharedConfig] setObject:@(snapped) forKey:spec.key];
    }
}

- (void)stageInteger:(NSInteger)value forSpec:(MIAFXSettingSpec *)spec {
    [[MIAFXConfig sharedConfig] setObject:@((NSInteger)llround([spec snap:(double)value])) forKey:spec.key];
}

- (void)stageBool:(BOOL)value forSpec:(MIAFXSettingSpec *)spec {
    [[MIAFXConfig sharedConfig] setObject:@(value) forKey:spec.key];
}

- (void)stageObject:(id)value forSpec:(MIAFXSettingSpec *)spec {
    if (spec.key.length == 0) return;
    [[MIAFXConfig sharedConfig] setObject:value forKey:spec.key];
}

- (void)stageFeatureBit:(uint32_t)bit enabled:(BOOL)enabled {
    NSUInteger mask = (NSUInteger)[[MIAFXConfig sharedConfig] integerForKey:@"Global.FeatureMask"];
    if (enabled) mask |= (NSUInteger)bit;
    else mask &= ~(NSUInteger)bit;
    [[MIAFXConfig sharedConfig] setObject:@(mask) forKey:@"Global.FeatureMask"];
}

- (BOOL)commitWithError:(NSError **)error {
    return [[MIAFXConfig sharedConfig] save:error];
}

#pragma mark 重置

- (void)writeDefaultsForItems:(NSArray<MIAFXSettingSpec *> *)items {
    NSMutableSet<NSString *> *maskTouched = [NSMutableSet set];
    for (MIAFXSettingSpec *spec in items) {
        if (spec.kind == MIAFXSettingKindFeatureFlag) {
            if ([maskTouched containsObject:spec.key]) continue;
            NSInteger defaultMask = [MIAFXDefaultValue(spec.key) integerValue];
            [[MIAFXConfig sharedConfig] setObject:@(defaultMask) forKey:spec.key];
            [maskTouched addObject:spec.key];
            continue;
        }
        if (spec.key.length == 0 || spec.kind == MIAFXSettingKindAction) continue;
        id fallback = MIAFXDefaultValue(spec.key);
        [[MIAFXConfig sharedConfig] setObject:fallback forKey:spec.key];
    }
}

- (void)resetSpec:(MIAFXSettingSpec *)spec {
    [self writeDefaultsForItems:@[spec]];
}

- (void)resetSection:(MIAFXSettingSection *)section {
    [self writeDefaultsForItems:section.items];
}

- (void)resetPage:(MIAFXSettingPage *)page {
    for (MIAFXSettingSection *section in page.sections) {
        for (MIAFXSettingSpec *spec in section.items) {
            if (spec.kind == MIAFXSettingKindAction) continue;
            if (spec.key.length == 0) continue;
            if (spec.kind == MIAFXSettingKindFeatureFlag) {
                NSInteger defaultMask = [MIAFXDefaultValue(spec.key) integerValue];
                [[MIAFXConfig sharedConfig] setObject:@(defaultMask) forKey:spec.key];
                continue;
            }
            id fallback = MIAFXDefaultValue(spec.key);
            [[MIAFXConfig sharedConfig] setObject:fallback forKey:spec.key];
        }
    }
}

- (void)resetAll {
    NSDictionary<NSString *, id> *defaults = MIAFXDefaultSettings();
    [defaults enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        [[MIAFXConfig sharedConfig] setObject:value forKey:key];
    }];
}

#pragma mark 预设

- (nullable MIAFXSettingPreset *)presetForActionIdentifier:(NSString *)identifier {
    if ([identifier hasPrefix:kMIAFXPresetThemePrefix]) {
        NSString *slug = [identifier substringFromIndex:kMIAFXPresetThemePrefix.length];
        for (MIAFXSettingPreset *preset in self.themePresets) {
            if ([preset.identifier isEqualToString:slug]) return preset;
        }
        return nil;
    }
    if ([identifier hasPrefix:kMIAFXPresetPerformancePrefix]) {
        NSString *slug = [identifier substringFromIndex:kMIAFXPresetPerformancePrefix.length];
        for (MIAFXSettingPreset *preset in self.performancePresets) {
            if ([preset.identifier isEqualToString:slug]) return preset;
        }
        return nil;
    }
    return nil;
}

- (BOOL)applyPreset:(MIAFXSettingPreset *)preset error:(NSError **)error {
    [preset.values enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        [[MIAFXConfig sharedConfig] setObject:value forKey:key];
    }];
    return [[MIAFXConfig sharedConfig] save:error];
}

#pragma mark 导入导出

- (NSData *)exportConfigurationData {
    NSDictionary<NSString *, id> *snapshot = [[MIAFXConfig sharedConfig] snapshot];
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:snapshot
                                                              format:NSPropertyListXMLFormat_v1_0
                                                             options:0
                                                               error:&error];
    if (error) return nil;
    return data;
}

- (NSInteger)importConfigurationFromDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:NSDictionary.class]) return -1;
    NSDictionary<NSString *, id> *defaults = MIAFXDefaultSettings();
    __block NSInteger count = 0;
    [dictionary enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        id fallback = defaults[key];
        if (fallback == nil) return;                       // 只接受已知 key
        if ([key isEqualToString:@"SchemaVersion"]) return; // 内部字段不接受外部写入
        id coerced = value;
        if ([fallback isKindOfClass:NSNumber.class]) {
            if ([value isKindOfClass:NSString.class]) {
                NSString *text = (NSString *)value;
                if (text.length == 0) return;
                if (MIAFXNumberIsBoolean(fallback)) coerced = @([text boolValue]);
                else coerced = @([text doubleValue]);
            } else if (![value isKindOfClass:NSNumber.class]) {
                return;
            }
            MIAFXSettingSpec *spec = self.specsByKey[key];
            if (spec && spec.kind == MIAFXSettingKindNumber) {
                double clamped = [spec clamp:[coerced doubleValue]];
                double snapped = [spec snap:clamped];
                if (spec.numberMode == MIAFXNumberModeInteger) coerced = @((NSInteger)llround(snapped));
                else coerced = @(snapped);
            }
        } else if ([fallback isKindOfClass:NSString.class]) {
            if (![value isKindOfClass:NSString.class]) return;
        }
        [[MIAFXConfig sharedConfig] setObject:coerced forKey:key];
        count += 1;
    }];
    return count;
}

- (NSInteger)importConfigurationFromURL:(NSURL *)url error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!data) return -1;
    NSError *parseError = nil;
    id plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&parseError];
    if (parseError || ![plist isKindOfClass:NSDictionary.class]) {
        if (error) *error = parseError ?: [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:@{NSLocalizedDescriptionKey: @"文件不是有效的 plist 字典"}];
        return -1;
    }
    return [self importConfigurationFromDictionary:plist];
}

#pragma mark 状态摘要

- (NSArray<NSString *> *)featureTitlesForMask:(uint32_t)maskValue {
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    struct { uint32_t bit; NSString *title; } table[] = {
        { MIAFXFeatureVideo, @"视频" },
        { MIAFXFeatureBreathing, @"呼吸" },
        { MIAFXFeatureNativeElements, @"原生元素" },
        { MIAFXFeatureMarquee, @"流光" },
        { MIAFXFeatureOrbit, @"轨迹" },
        { MIAFXFeatureMetaball, @"液滴" },
        { MIAFXFeatureSpectrum, @"频谱" },
        { MIAFXFeatureRhythm, @"律动" },
        { MIAFXFeatureMask, @"遮罩" },
    };
    for (NSUInteger i = 0; i < sizeof(table) / sizeof(table[0]); i += 1) {
        if ((maskValue & table[i].bit) != 0) [titles addObject:table[i].title];
    }
    return titles;
}

- (BOOL)isMasterEnabled {
    return [[MIAFXConfig sharedConfig] boolForKey:@"Global.Enabled"];
}

- (NSArray<NSString *> *)activeFeatureTitles {
    if (![self isMasterEnabled]) return @[];
    uint32_t mask = (uint32_t)[[MIAFXConfig sharedConfig] integerForKey:@"Global.FeatureMask"];
    return [self featureTitlesForMask:mask];
}

@end
