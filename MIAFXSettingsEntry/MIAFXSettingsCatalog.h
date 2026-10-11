//
//  MIAFXSettingsCatalog.h
//  MIAFXPrefs
//
//  设置项元数据总表：把 Shared/MIAFXDefaults.m 中的全部用户可调 key 组织为
//  分组分页模型（spec -> section -> page），UI 层只负责渲染。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "MIAFXConstants.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, MIAFXSettingKind) {
    MIAFXSettingKindAction = 0,   // 纯动作行（跳转、导入导出、重置 ...）
    MIAFXSettingKindSwitch,       // 布尔开关，直接对应一个 Bool key
    MIAFXSettingKindFeatureFlag,  // FeatureMask 位开关（同一 Mask key 的多个位）
    MIAFXSettingKindNumber,       // 数值（整数或浮点），使用 MIAFXNumberControlCell
    MIAFXSettingKindEnum,         // 枚举（分段控件 / push 列表 / action sheet）
    MIAFXSettingKindText,         // 纯文本
    MIAFXSettingKindPath          // 文件路径（文本 + Filza + 文件选择器）
};

typedef NS_ENUM(NSUInteger, MIAFXNumberMode) {
    MIAFXNumberModeFloat = 0,
    MIAFXNumberModeInteger
};

/// 枚举候选值
@interface MIAFXSettingOption : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *optionDescription;
@property (nonatomic, strong) id value;
+ (instancetype)optionWithTitle:(NSString *)title value:(id)value;
+ (instancetype)optionWithTitle:(NSString *)title description:(nullable NSString *)description value:(id)value;
@end

/// 一条设置项
@interface MIAFXSettingSpec : NSObject
@property (nonatomic, copy) NSString *key;                        // 绑定的 defaults key（动作行为 nil）
@property (nonatomic, copy) NSString *title;                     // 中文标题
@property (nonatomic, copy, nullable) NSString *specDescription; // 中文说明
@property (nonatomic, copy, nullable) NSString *group;           // 所属页名（展示/搜索用）
@property (nonatomic) MIAFXSettingKind kind;
@property (nonatomic) MIAFXNumberMode numberMode;
@property (nonatomic) double minimum;
@property (nonatomic) double maximum;
@property (nonatomic) double step;
@property (nonatomic) NSUInteger fractionDigits;                 // 浮点显示精度
@property (nonatomic, copy, nullable) NSString *unit;
@property (nonatomic, copy, nullable) NSArray<MIAFXSettingOption *> *options;
@property (nonatomic) BOOL enumUsesActionSheet;                  // 选项多时用 action sheet
@property (nonatomic) BOOL enumUsesSegmentedControl;             // 选项少且短时用行内分段控件
@property (nonatomic) uint32_t featureBit;                       // MIAFXSettingKindFeatureFlag 使用的位
@property (nonatomic, copy, nullable) NSString *actionIdentifier; // 动作标识符
@property (nonatomic, copy, nullable) NSString *visibleKey;       // 依赖的开关 key
@property (nonatomic, copy, nullable) NSArray<id> *visibleValues; // 依赖值为其中之一时可见
@property (nonatomic) BOOL inlineToplist;                         // 固定在小节顶部（审阅便利）

+ (instancetype)specWithKey:(NSString *)key title:(NSString *)title description:(nullable NSString *)description kind:(MIAFXSettingKind)kind;

/// 当前值（从 MIAFXConfig 读取；FeatureFlag 返回该位的布尔值）
- (nullable id)currentValue;
- (double)currentDouble;
- (NSInteger)currentInteger;
- (BOOL)currentBool;
/// 默认出厂值
- (nullable id)defaultValue;
- (BOOL)isDefaultValue;
/// 数值夹取到 [minimum, maximum] 并按 step 取整（需求 3：输入 clamp）
- (double)clamp:(double)value;
- (double)snap:(double)value;
/// 数值按整数/浮点格式化（含单位）
- (NSString *)formatDouble:(double)value;
/// 当前值的可读字符串（enum 返回选项标题）
- (NSString *)valueDisplayString;
/// "范围 0.00 ~ 1.00 · 步进 0.01 · 默认 0.80 · 单位 ×"
- (NSString *)rangeDescriptionString;
/// 依赖开关是否满足
- (BOOL)isVisibleNow;
@end

@interface MIAFXSettingSection : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *footer;
@property (nonatomic, copy) NSArray<MIAFXSettingSpec *> *items;
+ (instancetype)sectionWithTitle:(NSString *)title footer:(nullable NSString *)footer items:(NSArray<MIAFXSettingSpec *> *)items;
@end

@interface MIAFXSettingPage : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *pageDescription;
@property (nonatomic, copy) NSArray<MIAFXSettingSection *> *sections;
- (NSUInteger)itemCount;
@end

/// 一键预设（调色 / 性能）
@interface MIAFXSettingPreset : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *presetDescription;
@property (nonatomic, copy) NSDictionary<NSString *, id> *values;
@end

FOUNDATION_EXPORT NSString *const MIAFXActionFilzaVideos;
FOUNDATION_EXPORT NSString *const MIAFXActionFilzaMasks;
FOUNDATION_EXPORT NSString *const MIAFXActionFilzaCustomOrbits;
FOUNDATION_EXPORT NSString *const MIAFXActionFilzaPresets;
FOUNDATION_EXPORT NSString *const MIAFXActionFilzaLogs;
FOUNDATION_EXPORT NSString *const MIAFXActionFilzaConfiguration;
FOUNDATION_EXPORT NSString *const MIAFXActionExportConfiguration;
FOUNDATION_EXPORT NSString *const MIAFXActionImportConfiguration;
FOUNDATION_EXPORT NSString *const MIAFXActionShareConfiguration;
FOUNDATION_EXPORT NSString *const MIAFXActionRespring;
FOUNDATION_EXPORT NSString *const MIAFXActionResetProtection;
FOUNDATION_EXPORT NSString *const MIAFXActionRescanAssets;
FOUNDATION_EXPORT NSString *const MIAFXActionDiagnostics;
FOUNDATION_EXPORT NSString *const MIAFXActionOpenSystemSettings;

/// 动作标识符构造辅助
FOUNDATION_EXPORT NSString *MIAFXPresetThemeIdentifier(NSString *slug);
FOUNDATION_EXPORT NSString *MIAFXPresetPerformanceIdentifier(NSString *slug);
FOUNDATION_EXPORT NSString *MIAFXResetPageIdentifier(NSString *pageIdentifier);

@interface MIAFXSettingsCatalog : NSObject
+ (instancetype)sharedCatalog;

/// 全部分页（顺序即 UI 分段顺序）
@property (nonatomic, copy, readonly) NSArray<MIAFXSettingPage *> *pages;
- (nullable MIAFXSettingPage *)pageWithIdentifier:(NSString *)identifier;
/// 搜索：返回只包含命中项的分页（缺失则为空）
- (NSArray<MIAFXSettingPage *> *)filteredPagesForQuery:(NSString *)query;
/// 绑定到 key 的设置项数量（不含纯动作行）
- (NSUInteger)settingCount;
/// defaults 中未被 catalog 覆盖的 key（自检用）
- (NSArray<NSString *> *)uncoveredKeys;
/// catalog 中出现但 defaults 中不存在的 key（自检用，应为空）
- (NSArray<NSString *> *)unknownKeys;

#pragma mark - 读写（统一走 MIAFXConfig, save: 保证 live state / reload notify）

- (nullable id)valueForSpec:(MIAFXSettingSpec *)spec;
/// 暂存数值（不落盘）：滑杆拖动过程中让预览实时生效
- (void)stageDouble:(double)value forSpec:(MIAFXSettingSpec *)spec;
- (void)stageInteger:(NSInteger)value forSpec:(MIAFXSettingSpec *)spec;
- (void)stageBool:(BOOL)value forSpec:(MIAFXSettingSpec *)spec;
- (void)stageObject:(id)value forSpec:(MIAFXSettingSpec *)spec;
- (void)stageFeatureBit:(uint32_t)bit enabled:(BOOL)enabled;
/// 落盘并触发 live state + reload notify
- (BOOL)commitWithError:(NSError **)error;

#pragma mark - 恢复默认

- (void)resetSpec:(MIAFXSettingSpec *)spec;
- (void)resetSection:(MIAFXSettingSection *)section;
- (void)resetPage:(MIAFXSettingPage *)page;
- (void)resetAll;
/// 预设
- (NSArray<MIAFXSettingPreset *> *)themePresets;
- (NSArray<MIAFXSettingPreset *> *)performancePresets;
/// 反查动作标识符对应的预设（nil 表示不是预设动作）
- (nullable MIAFXSettingPreset *)presetForActionIdentifier:(NSString *)identifier;
- (BOOL)applyPreset:(MIAFXSettingPreset *)preset error:(NSError **)error;
/// 导入：只接受已知的 key
- (NSInteger)importConfigurationFromDictionary:(NSDictionary *)dictionary;
/// 导出：当前快照 plist 数据
- (nullable NSData *)exportConfigurationData;
/// 从外部 URL 载入 plist（UIDocumentPicker 结果），返回导入条目数，失败返回 -1
- (NSInteger)importConfigurationFromURL:(NSURL *)url error:(NSError **)error;

#pragma mark - 诊断辅助

/// 已启用的特效中文名列表
- (NSArray<NSString *> *)activeFeatureTitles;
- (BOOL)isMasterEnabled;
@end

NS_ASSUME_NONNULL_END
