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
FOUNDATION_EXPORT BOOL MIAFXEnsureDirectory(NSString *path, NSError **error);
FOUNDATION_EXPORT BOOL MIAFXEnsureDataDirectories(NSError **error);

NS_ASSUME_NONNULL_END
