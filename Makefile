export THEOS_PACKAGE_SCHEME = roothide
# 胖二进制 arm64+arm64e：与设备上所有能正常加载的插件一致（2.0.11 修复）。
# 薄 arm64e 在这台 RootHide 环境的加载路径上有问题。
export ARCHS = arm64 arm64e
# minos 14.0：与能正常工作的插件一致。>=15 时 ld64 会生成
# DYLD_CHAINED_PTR_ARM64E_USERLAND24(12) 而不是传统的 ARM64E(1) 格式。
export TARGET = iphone:clang:latest:14.0

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
