include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MIAFXAudio
MIAFXAudio_FILES = MIAFXAudioMain.xm MIAFXFFT.c MIAFXBands.c MIAFXRing.c MIAFXUnitProbe.c MIAFXPublisher.c ../Shared/MIAFXIPC.c
# No -std=gnu11 here: Logos compiles MIAFXAudioMain.xm as Objective-C++, where clang
# rejects C language modes.  The toolchain default (gnu17) already provides the C11
# atomics used by MIAFXRing/MIAFXUnitProbe.
MIAFXAudio_CFLAGS = -Os -Wall -Wextra -Wno-unused-parameter -I../Shared -DMIAFX_AUDIO_PROCESS=1
MIAFXAudio_CCFLAGS = $(MIAFXAudio_CFLAGS) -fno-objc-arc
MIAFXAudio_FRAMEWORKS = AudioToolbox CoreAudio
MIAFXAudio_LIBRARIES = substrate
MIAFXAudio_LDFLAGS = -Wl,-dead_strip

include $(THEOS_MAKE_PATH)/tweak.mk
