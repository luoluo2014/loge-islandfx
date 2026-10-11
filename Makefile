export THEOS_PACKAGE_SCHEME = roothide
export ARCHS = arm64e
export TARGET = iphone:clang:latest:17.0

INSTALL_TARGET_PROCESSES = SpringBoard mediaserverd Preferences

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += MIAFX
SUBPROJECTS += MIAFXAudio
SUBPROJECTS += MIAFXSettingsEntry

include $(THEOS_MAKE_PATH)/aggregate.mk
