include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LogeIslandFX
LogeIslandFX_FILES = LogeIslandFX.xm LOGXVideoBackground.m \
	../Shared/LOGXConfig.m ../Shared/LOGXPath.m ../Shared/LOGXLog.m
LogeIslandFX_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations -I../Shared
LogeIslandFX_FRAMEWORKS = UIKit Foundation QuartzCore AVFoundation CoreMedia CoreGraphics
LogeIslandFX_LIBRARIES = substrate roothide
# _SPIslandRenderSurface 等 SpringBoard 私有类不在任何 SDK 里，运行时动态解析
LogeIslandFX_LDFLAGS = -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk
