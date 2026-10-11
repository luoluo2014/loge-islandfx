/*
 * MIAFXAudio - mediaserverd audio tap.
 *
 * Loads into mediaserverd only (see MIAFXAudio.plist).  Everything that can
 * block or allocate lives on the publisher thread; the AudioUnitRender hook
 * itself does nothing but a fixed table lookup, a bounded PCM downmix and a
 * lock-free ring write.  No Objective-C objects, no Foundation, no UIKit.
 */

#include <AudioToolbox/AudioUnit.h>
#include <CoreAudio/CoreAudioTypes.h>
#include <stdint.h>

#include "MIAFXPublisher.h"
#include "MIAFXUnitProbe.h"

/*
 * Real-time contract for everything below this hook:
 *   - the original function runs first and its status is returned untouched,
 *   - no malloc/free, no Objective-C, no logging, no notify, no file I/O,
 *   - no locks, semaphores or AudioUnitGetProperty,
 *   - at most MIAFX_UNIT_MAX_FRAMES (512) samples copied per call.
 */
/* Logos 的 %hookf 要求签名写在同一行内，参数含义见下方注释：
 *   inUnit            被渲染的 AudioUnit，用作固定表的键
 *   ioActionFlags     渲染动作标志（原样透传）
 *   inTimeStamp       时间戳（原样透传）
 *   inOutputBusNumber 输出总线号
 *   inNumberFrames    本次渲染帧数
 *   ioData            渲染出的 PCM 缓冲（只读拷贝，绝不改写）
 */
%hookf(OSStatus, AudioUnitRender, AudioUnit inUnit, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inOutputBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    OSStatus status = %orig(inUnit, ioActionFlags, inTimeStamp, inOutputBusNumber, inNumberFrames, ioData);
    if (status != noErr) return status;
    if (!inUnit || !ioData || inNumberFrames == 0u) return status;

    /* Disabled: pure pass-through, no probing and no copying. */
    if (!MIAFXPublisherIsEnabled()) return status;

    MIAFXUnitTable *table = MIAFXUnitSharedTable();
    uintptr_t key = (uintptr_t)inUnit;
    MIAFXUnitSlot *slot = MIAFXUnitLookup(table, key);
    if (!slot) {
        /* Unknown unit: hand it to the publisher thread once, then forget it
         * until the descriptor shows up.  Bounded, never retried in-loop. */
        MIAFXUnitRequestProbe(table, key);
        return status;
    }

    MIAFXUnitCaptureRendered(slot, ioData, inNumberFrames, MIAFXMonotonicMilliseconds());
    return status;
}

%ctor {
    MIAFXUnitTableInit(MIAFXUnitSharedTable());
    MIAFXPublisherStart(MIAFXUnitSharedTable());
}
