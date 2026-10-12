include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MIAFX
MIAFX_FILES = MIAFXMain.xm MIAFXVideoBackground.xm \
	MIAFXClock.m MIAFXPassthroughView.m MIAFXStateCoordinator.m \
	MIAFXIslandHostBridge.m MIAFXNativeElementBridge.m MIAFXRootRenderer.m \
	MIAFXVideoLayer.m MIAFXBreathing.m MIAFXMarqueeFX.m MIAFXOrbitFX.m \
	MIAFXMetaballFX.m MIAFXSpectrumView.m MIAFXProbe.m \
	../Shared/MIAFXPath.m ../Shared/MIAFXDefaults.m ../Shared/MIAFXConfig.m \
	../Shared/MIAFXLog.m ../Shared/MIAFXSafe.m ../Shared/MIAFXIPC.c \
	../Shared/MIAFXSpectrumResample.c
MIAFX_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations -I../Shared
MIAFX_CCFLAGS = $(MIAFX_CFLAGS)
MIAFX_FRAMEWORKS = UIKit Foundation QuartzCore AVFoundation CoreMedia CoreGraphics
MIAFX_LIBRARIES = substrate roothide

MIAFX_PTRAUTH_CFLAGS := $(shell $(TARGET_CC) -x objective-c -fsyntax-only -fno-ptrauth-objc-class-ro /dev/null >/dev/null 2>&1 && echo -fno-ptrauth-objc-class-ro)
MIAFX_CFLAGS += $(MIAFX_PTRAUTH_CFLAGS)
MIAFX_CCFLAGS += $(MIAFX_PTRAUTH_CFLAGS)

include $(THEOS_MAKE_PATH)/tweak.mk
