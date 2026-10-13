include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LogeIslandFX
LogeIslandFX_FILES = LogeIslandFX.xm LOGXVideoBackground.m \
	../Shared/LOGXConfig.m ../Shared/LOGXPath.m ../Shared/LOGXLog.m
# -fno-ptrauth-objc-class-ro：关闭 class_ro_t 指针签名，与设备上能正常工作的
# 插件保持一致（2.0.11 修复，详见 LogeIslandPrefs/Makefile 注释）。
# -undefined dynamic_lookup 已移除：它会触发 ld64 禁用 chained fixups
#（rdar://102088753），导致 arm64e 类指针的 PAC 签名重定位被丢弃——类指针带着
# 认证位但 dyld 永远不处理，运行时 readClass 读到垃圾指针即崩。
# _SPIslandRenderSurface 等私有类已全部改为运行时 objc_getClass 查找，无需动态查找。
LogeIslandFX_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations -fno-ptrauth-objc-class-ro -I../Shared
LogeIslandFX_FRAMEWORKS = UIKit Foundation QuartzCore AVFoundation CoreMedia CoreGraphics
LogeIslandFX_LIBRARIES = substrate roothide
LogeIslandFX_LDFLAGS =

include $(THEOS_MAKE_PATH)/tweak.mk
