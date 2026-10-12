export THEOS_PACKAGE_SCHEME = roothide
export ARCHS = arm64e
export TARGET = iphone:clang:latest:17.0

INSTALL_TARGET_PROCESSES = SpringBoard mediaserverd Preferences

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += MIAFX
SUBPROJECTS += MIAFXAudio
SUBPROJECTS += MIAFXSettingsEntry

include $(THEOS_MAKE_PATH)/aggregate.mk

# 暂存收尾：建好素材目录（Videos 是投递落地目录，Filza 手动转存也走这里；
# 其余为轨道/遮罩/预设/日志目录，插件运行时会自动创建，打包带上省得用户手建）。
# git 不跟踪空目录，因此不能放进 layout/，只能在打包时生成。
after-stage::
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/var/mobile/Library/LogeIsland/Videos" \
		"$(THEOS_STAGING_DIR)/var/mobile/Library/LogeIsland/Masks" \
		"$(THEOS_STAGING_DIR)/var/mobile/Library/LogeIsland/CustomOrbits" \
		"$(THEOS_STAGING_DIR)/var/mobile/Library/LogeIsland/Presets" \
		"$(THEOS_STAGING_DIR)/var/mobile/Library/LogeIsland/Logs"$(ECHO_END)
