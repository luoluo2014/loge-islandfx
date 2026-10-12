#import "LOGXPath.h"
#import <roothide.h>

NSString *LOGXDataDirectory(void) {
    return jbroot(@"/var/mobile/Library/LogeIsland");
}

NSString *LOGXVideosDirectory(void) {
    return [LOGXDataDirectory() stringByAppendingPathComponent:@"Videos"];
}

NSString *LOGXLogPath(void) {
    return [LOGXDataDirectory() stringByAppendingPathComponent:@"Logs/video-diag.log"];
}

NSString *LOGXBootStatePath(void) {
    return [LOGXDataDirectory() stringByAppendingPathComponent:@"boot-state.plist"];
}

NSString *LOGXRealVideosDirectory(void) {
    return @"/var/jb/var/mobile/Library/LogeIsland/Videos";
}

BOOL LOGXEnsureDataDirectories(NSError **error) {
    NSFileManager *manager = NSFileManager.defaultManager;
    for (NSString *path in @[LOGXDataDirectory(), LOGXVideosDirectory(),
                             [LOGXDataDirectory() stringByAppendingPathComponent:@"Logs"]]) {
        if (![manager createDirectoryAtPath:path withIntermediateDirectories:YES
                                 attributes:@{NSFilePosixPermissions:@0755} error:error]) {
            return NO;
        }
    }
    return YES;
}
