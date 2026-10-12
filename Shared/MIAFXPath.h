#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *MIAFXRootPath(NSString *logicalPath);
FOUNDATION_EXPORT NSString *MIAFXDataDirectory(void);
FOUNDATION_EXPORT NSString *MIAFXPreferencesDirectory(void);
FOUNDATION_EXPORT NSString *MIAFXSettingsPath(void);
FOUNDATION_EXPORT NSString *MIAFXPanicPath(void);
FOUNDATION_EXPORT NSString *MIAFXDiagnosticsPath(void);
FOUNDATION_EXPORT NSString *MIAFXLogPath(void);
FOUNDATION_EXPORT NSString *MIAFXVideoDiagPath(void);
FOUNDATION_EXPORT NSString *MIAFXVideosDirectory(void);
/// 字面量真实路径（/var/jb 前缀，Filza / root 视角；设置 App 的 jbroot() 会被重定向进沙盒，不能用）
FOUNDATION_EXPORT NSString *MIAFXRealVideosDirectory(void);
/// 判断路径是否位于设置 App 的沙盒容器内（含 "/.jbroot-"）
FOUNDATION_EXPORT BOOL MIAFXIsSandboxContainerPath(NSString *path);
FOUNDATION_EXPORT BOOL MIAFXEnsureDirectory(NSString *path, NSError **error);
FOUNDATION_EXPORT BOOL MIAFXEnsureDataDirectories(NSError **error);

NS_ASSUME_NONNULL_END
