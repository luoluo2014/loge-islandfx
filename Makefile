export THEOS_PACKAGE_SCHEME = roothide
export ARCHS = arm64e
export TARGET = iphone:clang:latest:17.0

INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += LogeIslandFX
SUBPROJECTS += LogeIslandPrefs

include $(THEOS_MAKE_PATH)/aggregate.mk

# 暂存收尾：建好数据目录（Videos 是投递落地目录，Filza 手动转存也走这里；
# Logs 放诊断日志）。git 不跟踪空目录，只能在打包时生成。
after-stage::
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/var/mobile/Library/LogeIsland/Videos" \
		"$(THEOS_STAGING_DIR)/var/mobile/Library/LogeIsland/Logs"$(ECHO_END)
