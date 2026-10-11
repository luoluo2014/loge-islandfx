#ifndef MIAFX_CONSTANTS_H
#define MIAFX_CONSTANTS_H

#include <stdint.h>

#define MIAFX_PACKAGE_ID "com.loge.islandfx"
#define MIAFX_NOTIFY_RELOAD "com.loge.islandfx.reload"
#define MIAFX_NOTIFY_FEATURE_STATE "com.loge.islandfx.feature-state"
#define MIAFX_NOTIFY_RESCAN "com.loge.islandfx.rescan"
#define MIAFX_NOTIFY_DIAGNOSTICS "com.loge.islandfx.diagnostics"
#define MIAFX_NOTIFY_FFT_A "com.loge.islandfx.fft.a"
#define MIAFX_NOTIFY_FFT_B "com.loge.islandfx.fft.b"
#define MIAFX_NOTIFY_FFT_M "com.loge.islandfx.fft.m"
#define MIAFX_NOTIFY_FFT_T "com.loge.islandfx.fft.t"
#define MIAFX_NOTIFY_FFT_TICK "com.loge.islandfx.fft.tick"
#define MIAFX_NOTIFY_AUDIO_ENABLED "com.loge.islandfx.audio-enabled"

#define MIAFX_IPC_MAGIC 0xAFu
#define MIAFX_IPC_VERSION 1u
#define MIAFX_FEATURE_VALID_BIT (1ULL << 63)
#define MIAFX_FEATURE_MASTER_BIT (1ULL << 62)

typedef enum : uint32_t {
    MIAFXFeatureVideo = 1u << 0,
    MIAFXFeatureBreathing = 1u << 1,
    MIAFXFeatureNativeElements = 1u << 2,
    MIAFXFeatureMarquee = 1u << 3,
    MIAFXFeatureOrbit = 1u << 4,
    MIAFXFeatureMetaball = 1u << 5,
    MIAFXFeatureSpectrum = 1u << 6,
    MIAFXFeatureRhythm = 1u << 7,
    MIAFXFeatureMask = 1u << 8,
} MIAFXFeature;

typedef enum : uint8_t {
    MIAFXRuntimeBoot = 0,
    MIAFXRuntimeActive,
    MIAFXRuntimeDimmed,
    MIAFXRuntimeScreenOff,
    MIAFXRuntimeIslandHidden,
    MIAFXRuntimeSuspended,
} MIAFXRuntimeState;

#endif
