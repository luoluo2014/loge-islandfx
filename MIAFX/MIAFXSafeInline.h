//
//  MIAFXSafeInline.h
//  MIAFX
//
//  为什么要有这个文件：
//  MIAFX_SAFE_BLOCK(moduleName, block) 是函数式宏，而 C 预处理器只把
//  圆括号 () 内的逗号视为“受保护”，方括号 [] 与花括号 {} 都不能保护逗号。
//  因此下面这种写法是非法的（块体里的顶层逗号会被当成第二个宏参数分隔符）：
//
//      MIAFX_SAFE_BLOCK(@"Demo", ^{
//          [[MIAFXProbe sharedProbe] recordRuntimeStatus:
//              [NSString stringWithFormat:@"state:%@",   // <-- 这个逗号在 [] 里
//                                         [Foo nameForState:next]]];
//      });
//
//  改成真正的函数之后，块体只是普通实参，逗号不再有歧义。
//

#import <Foundation/Foundation.h>

#import "MIAFXLog.h"
#import "MIAFXSafe.h"

NS_ASSUME_NONNULL_BEGIN

/// 在 @try/@catch 里执行一段逻辑；异常只影响 MIAFX 自身的后处理，绝不上抛。
NS_INLINE void MIAFXRunProtected(NSString *moduleName, void (^block)(void)) {
    if (block == nil) {
        return;
    }
    @try {
        block();
    } @catch (NSException *exception) {
        MIAFXLogError(moduleName, exception, @"模块已捕获异常");
        MIAFXRecordModuleFailure(moduleName);
    }
}

NS_ASSUME_NONNULL_END
