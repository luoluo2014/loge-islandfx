#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT BOOL MIAFXBeginBootGuard(void);
FOUNDATION_EXPORT void MIAFXMarkBootStable(void);
FOUNDATION_EXPORT void MIAFXResetBootGuard(void);
FOUNDATION_EXPORT BOOL MIAFXRecordModuleFailure(NSString *module);
FOUNDATION_EXPORT BOOL MIAFXIsModuleDisabled(NSString *module);

#define MIAFX_SAFE_BLOCK(moduleName, block) do { \
    @try { block; } \
    @catch (NSException *exception) { \
        MIAFXLogError((moduleName), exception, @"模块已捕获异常"); \
        MIAFXRecordModuleFailure((moduleName)); \
    } \
} while (0)

NS_ASSUME_NONNULL_END
