include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = LogeIslandPrefs
# 关键：theos 默认把 .bundle 链接成 MH_DYLIB（-dynamiclib），但系统设置加载
# PreferenceBundle 需要 MH_BUNDLE（filetype=8，即 -bundle）。MH_DYLIB 会导致
# dlopen 静默失败（不崩溃、无崩溃日志，表现为点入口闪退）。关闭 DYNAMIC_LIBRARY
# 并显式加 -bundle，产出 MH_BUNDLE。
LogeIslandPrefs_DYNAMIC_LIBRARY = 0
LogeIslandPrefs_FILES = $(wildcard *.m CustomCells/*.m) \
	../Shared/LOGXConfig.m ../Shared/LOGXPath.m ../Shared/LOGXLog.m
LogeIslandPrefs_INSTALL_PATH = /Library/PreferenceBundles
LogeIslandPrefs_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore PhotosUI
LogeIslandPrefs_PRIVATE_FRAMEWORKS = Preferences
LogeIslandPrefs_CFLAGS = -fobjc-arc -Wall -I../Shared -I../LogeIslandFX -I. -I./CustomCells
# 注意：绝不能加 -undefined dynamic_lookup！它会触发 Apple ld64 禁用 chained fixups
#（rdar://102088753），导致 clang 生成的 arm64e 类指针 PAC 签名被降级丢失，运行时
# readClass 认证 superclass 失败而闪退。bundle 的所有符号都能在 Preferences/Foundation
# 等框架里解析（私有 ivar 符号已在 2.0.6 移除），无需 dynamic_lookup。
LogeIslandPrefs_LDFLAGS = -bundle -F$(THEOS)/sdks/iPhoneOS16.5.sdk/System/Library/PrivateFrameworks

include $(THEOS_MAKE_PATH)/bundle.mk

# PreferenceLoader 入口（git 不跟踪空目录之外的安装动作，这里在打包时落地）
internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/LogeIsland.plist$(ECHO_END)
