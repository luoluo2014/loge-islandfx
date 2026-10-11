//
//  MIAFXProbe.h
//  MIAFX
//
//  诊断探针：把类存在性、方法列表、宿主模式、几何、原生元素匹配、
//  运行状态写到 MIAFXDiagnosticsPath 指向的 plist。
//  只有在 Global.DebugLog 打开时才真正落盘。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MIAFXProbe : NSObject

+ (instancetype)sharedProbe;

@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;

/// 重新读取 Global.DebugLog
- (void)refreshEnabled;

/// 类是否加载
- (void)recordClassPresence:(NSString *)className exists:(BOOL)exists;

/// 某个类上探测到的方法列表
- (void)recordMethodList:(NSArray<NSString *> *)methods forClass:(NSString *)className;

/// 宿主类型 / 是否展开 / bounds / activeLayoutMode
- (void)recordHostKind:(NSString *)kind
              expanded:(BOOL)expanded
                bounds:(CGRect)bounds
            layoutMode:(NSInteger)layoutMode
         mountStrategy:(NSString *)strategy;

/// 原生元素匹配结果
- (void)recordNativeMatchForSlot:(NSString *)slot
                       className:(NSString * _Nullable)className
                         matched:(BOOL)matched;

/// 运行状态
- (void)recordRuntimeStatus:(NSString *)status;

/// 通用键值
- (void)setValue:(id _Nullable)value forDiagnosticKey:(NSString *)key;

/// 立即写盘（节流 1 秒）
- (void)flush;
/// 强制写盘
- (void)flushImmediately;

/// 清空当前收集的诊断（保留 plist 文件）
- (void)reset;

@end

NS_ASSUME_NONNULL_END
