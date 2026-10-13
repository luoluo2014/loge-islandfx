include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = LogeIslandPrefs
LogeIslandPrefs_FILES = $(wildcard *.m CustomCells/*.m) \
	../Shared/LOGXConfig.m ../Shared/LOGXPath.m ../Shared/LOGXLog.m
LogeIslandPrefs_INSTALL_PATH = /Library/PreferenceBundles
LogeIslandPrefs_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore PhotosUI
LogeIslandPrefs_PRIVATE_FRAMEWORKS = Preferences
LogeIslandPrefs_CFLAGS = -fobjc-arc -Wall -I../Shared -I../LogeIslandFX -I. -I./CustomCells
LogeIslandPrefs_LDFLAGS = -undefined dynamic_lookup -F$(SYSROOT)/System/Library/PrivateFrameworks

include $(THEOS_MAKE_PATH)/bundle.mk

# PreferenceLoader 入口（git 不跟踪空目录之外的安装动作，这里在打包时落地）
internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/LogeIsland.plist$(ECHO_END)
