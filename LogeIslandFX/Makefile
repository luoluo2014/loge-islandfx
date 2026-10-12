include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LogeIslandFX
LogeIslandFX_FILES = LogeIslandFX.xm LOGXVideoBackground.m \
	../Shared/LOGXConfig.m ../Shared/LOGXPath.m ../Shared/LOGXLog.m
LogeIslandFX_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations -I../Shared
LogeIslandFX_FRAMEWORKS = UIKit Foundation QuartzCore AVFoundation CoreMedia CoreGraphics
LogeIslandFX_LIBRARIES = substrate roothide

include $(THEOS_MAKE_PATH)/tweak.mk
