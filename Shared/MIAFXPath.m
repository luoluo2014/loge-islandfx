#import "MIAFXPath.h"
#import <roothide.h>

NSString *MIAFXRootPath(NSString *logicalPath) {
    if (logicalPath.length == 0) return jbroot(@"/var/mobile/Library/LogeIsland");
    NSString *normalized = [logicalPath hasPrefix:@"/"] ? logicalPath : [@"/" stringByAppendingString:logicalPath];
    return jbroot(normalized);
}

NSString *MIAFXDataDirectory(void) { return MIAFXRootPath(@"/var/mobile/Library/LogeIsland"); }
NSString *MIAFXPreferencesDirectory(void) { return [MIAFXDataDirectory() stringByAppendingPathComponent:@"Preferences"]; }
NSString *MIAFXSettingsPath(void) { return [MIAFXPreferencesDirectory() stringByAppendingPathComponent:@"settings.plist"]; }
NSString *MIAFXPanicPath(void) { return [MIAFXPreferencesDirectory() stringByAppendingPathComponent:@"panic.plist"]; }
NSString *MIAFXDiagnosticsPath(void) { return [MIAFXPreferencesDirectory() stringByAppendingPathComponent:@"diagnostics.plist"]; }
NSString *MIAFXLogPath(void) { return [MIAFXDataDirectory() stringByAppendingPathComponent:@"Logs/miafx.log"]; }
NSString *MIAFXVideoDiagPath(void) { return [MIAFXDataDirectory() stringByAppendingPathComponent:@"Logs/video-diag.log"]; }

BOOL MIAFXEnsureDirectory(NSString *path, NSError **error) {
    if (path.length == 0) return NO;
    return [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:error];
}

BOOL MIAFXEnsureDataDirectories(NSError **error) {
    NSArray<NSString *> *directories = @[
        MIAFXDataDirectory(), MIAFXPreferencesDirectory(),
        [MIAFXDataDirectory() stringByAppendingPathComponent:@"Videos"],
        [MIAFXDataDirectory() stringByAppendingPathComponent:@"Masks"],
        [MIAFXDataDirectory() stringByAppendingPathComponent:@"CustomOrbits"],
        [MIAFXDataDirectory() stringByAppendingPathComponent:@"Logs"],
        [MIAFXDataDirectory() stringByAppendingPathComponent:@"Presets"]
    ];
    for (NSString *path in directories) {
        if (!MIAFXEnsureDirectory(path, error)) return NO;
    }
    return YES;
}
