include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = LogeIslandPrefs
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
LogeIslandPrefs_LDFLAGS = -F$(THEOS)/sdks/iPhoneOS16.5.sdk/System/Library/PrivateFrameworks

include $(THEOS_MAKE_PATH)/bundle.mk

# PreferenceLoader 入口（git 不跟踪空目录之外的安装动作，这里在打包时落地）
internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/LogeIsland.plist$(ECHO_END)
