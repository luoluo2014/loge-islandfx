#include "MIAFXUnitProbe.h"

#include <stddef.h>
#include <string.h>

/* Publisher side cadence.  All values are bounded: at most one
 * AudioUnitGetProperty call per publisher tick, and a descriptor that goes
 * quiet is dropped instead of being probed forever. */
#define MIAFX_UNIT_VERIFY_INTERVAL_MS 2000u
#define MIAFX_UNIT_IDLE_RETIRE_MS 5000u
#define MIAFX_UNIT_REJECT_TTL_MS 30000u

#define MIAFX_UNIT_MIN_CHANNELS 1u
#define MIAFX_UNIT_MAX_CHANNELS 8u
#define MIAFX_UNIT_MIN_RATE 1000.0
#define MIAFX_UNIT_MAX_RATE 384000.0

static MIAFXUnitTable gSharedTable;

MIAFXUnitTable *MIAFXUnitSharedTable(void) { return &gSharedTable; }

void MIAFXUnitTableInit(MIAFXUnitTable *table) {
    if (!table) return;
    for (uint32_t i = 0u; i < MIAFX_UNIT_TABLE_SIZE; i++) {
        MIAFXUnitSlot *slot = &table->slots[i];
        MIAFXRingInit(&slot->ring);
        AudioStreamBasicDescription empty = {0};
        slot->asbd = empty;
        MIAFXUnitView view = {0};
        slot->view = view;
        atomic_store_explicit(&slot->unitKey, (uintptr_t)0u, memory_order_relaxed);
        atomic_store_explicit(&slot->state, (uint32_t)MIAFXUnitSlotFree, memory_order_relaxed);
        atomic_store_explicit(&slot->generation, 0u, memory_order_relaxed);
        atomic_store_explicit(&slot->activity, (uint64_t)0u, memory_order_relaxed);
        atomic_store_explicit(&slot->lastStampMs, (uint64_t)0u, memory_order_relaxed);
        slot->installedMs = 0u;
        slot->verifiedMs = 0u;
    }
    for (uint32_t i = 0u; i < MIAFX_PROBE_SLOTS; i++) {
        atomic_store_explicit(&table->queue[i], (uintptr_t)0u, memory_order_relaxed);
    }
    atomic_store_explicit(&table->droppedProbes, (uint64_t)0u, memory_order_relaxed);
}

/* ---------------------------------------------------------------- render --- */

MIAFXUnitSlot *MIAFXUnitLookup(MIAFXUnitTable *table, uintptr_t key) {
    if (!table || key == 0u) return NULL;
    for (uint32_t i = 0u; i < MIAFX_UNIT_TABLE_SIZE; i++) {
        MIAFXUnitSlot *slot = &table->slots[i];
        if (atomic_load_explicit(&slot->unitKey, memory_order_acquire) != key) continue;
        uint32_t state = atomic_load_explicit(&slot->state, memory_order_acquire);
        if (state != (uint32_t)MIAFXUnitSlotReady) return NULL; /* pending/rejected: never re-probe */
        return slot;
    }
    return NULL;
}

void MIAFXUnitRequestProbe(MIAFXUnitTable *table, uintptr_t key) {
    if (!table || key == 0u) return;

    /* Already known under any state -> do not enqueue again. */
    for (uint32_t i = 0u; i < MIAFX_UNIT_TABLE_SIZE; i++) {
        if (atomic_load_explicit(&table->slots[i].unitKey, memory_order_acquire) == key) return;
    }

    /* Already waiting in the queue -> the render thread must not fill the
     * queue with copies of the same key while the publisher is busy. */
    for (uint32_t i = 0u; i < MIAFX_PROBE_SLOTS; i++) {
        if (atomic_load_explicit(&table->queue[i], memory_order_acquire) == key) return;
    }

    /* Single bounded pass over the queue: no retry loop, ever. */
    for (uint32_t i = 0u; i < MIAFX_PROBE_SLOTS; i++) {
        uintptr_t expected = (uintptr_t)0u;
        if (atomic_compare_exchange_strong_explicit(&table->queue[i], &expected, key,
                                                    memory_order_acq_rel, memory_order_relaxed)) {
            return;
        }
    }
    atomic_fetch_add_explicit(&table->droppedProbes, (uint64_t)1u, memory_order_relaxed);
}

bool MIAFXUnitViewSnapshot(MIAFXUnitSlot *slot, MIAFXUnitView *out) {
    if (!slot || !out) return false;
    uint32_t first = atomic_load_explicit(&slot->generation, memory_order_acquire);
    if (first == 0u || (first & 1u)) return false; /* unpublished or mid-update */

    MIAFXUnitView view = slot->view;

    atomic_thread_fence(memory_order_acquire);
    uint32_t second = atomic_load_explicit(&slot->generation, memory_order_acquire);
    if (first != second) return false; /* publisher rewrote it: skip this callback */
    *out = view;
    return true;
}

void MIAFXUnitCaptureRendered(MIAFXUnitSlot *slot, const AudioBufferList *ioData, uint32_t frameCount, uint64_t nowMs) {
    if (!slot || !ioData) return;

    MIAFXUnitView view;
    if (!MIAFXUnitViewSnapshot(slot, &view)) return;
    if (view.channels == 0u || view.channels > MIAFX_UNIT_MAX_CHANNELS) return;
    if (view.bytesPerFrame == 0u || view.bytesPerSample == 0u) return;
    if (view.format != (uint32_t)MIAFXUnitFormatFloat32 &&
        view.format != (uint32_t)MIAFXUnitFormatInt16 &&
        view.format != (uint32_t)MIAFXUnitFormatInt32) return;

    uint32_t buffers = ioData->mNumberBuffers;
    if (buffers == 0u) return;

    uint32_t frames = frameCount;
    if (frames > MIAFX_UNIT_MAX_FRAMES) frames = MIAFX_UNIT_MAX_FRAMES;
    if (frames == 0u) return;

    uint32_t channels = view.channels;
    uint32_t usedBuffers = view.interleaved ? 1u : (buffers < channels ? buffers : channels);
    if (usedBuffers == 0u) return;

    /* Never read past the shortest buffer that was actually rendered. */
    for (uint32_t b = 0u; b < usedBuffers; b++) {
        const AudioBuffer *buffer = &ioData->mBuffers[b];
        if (!buffer->mData) return;
        uint32_t available = buffer->mDataByteSize / view.bytesPerFrame;
        if (available < frames) frames = available;
    }
    if (frames == 0u) return;

    float mono[MIAFX_UNIT_MAX_FRAMES];
    const uint32_t stride = view.bytesPerFrame;
    const uint32_t sampleSize = view.bytesPerSample;

    for (uint32_t f = 0u; f < frames; f++) {
        float sum = 0.0f;
        for (uint32_t c = 0u; c < channels; c++) {
            const uint8_t *base;
            uint32_t offset;
            if (view.interleaved) {
                base = (const uint8_t *)ioData->mBuffers[0].mData;
                offset = f * stride + c * sampleSize;
            } else {
                base = (const uint8_t *)ioData->mBuffers[c].mData;
                offset = f * stride;
            }
            const uint8_t *source = base + offset;
            switch (view.format) {
                case (uint32_t)MIAFXUnitFormatFloat32: {
                    float value;
                    memcpy(&value, source, sizeof(value));
                    sum += value;
                    break;
                }
                case (uint32_t)MIAFXUnitFormatInt16: {
                    int16_t raw;
                    memcpy(&raw, source, sizeof(raw));
                    sum += (float)raw * view.scale;
                    break;
                }
                case (uint32_t)MIAFXUnitFormatInt32: {
                    int32_t raw;
                    memcpy(&raw, source, sizeof(raw));
                    sum += (float)raw * view.scale;
                    break;
                }
                default:
                    return; /* unreachable, descriptor is validated before publication */
            }
        }
        mono[f] = sum / (float)channels;
    }

    float energy = 0.0f;
    for (uint32_t f = 0u; f < frames; f++) energy += mono[f] * mono[f];
    energy /= (float)frames;
    if (energy > 1.0e6f) energy = 1.0e6f; /* keep the fixed point conversion in range */

    atomic_store_explicit(&slot->activity, (uint64_t)(energy * 1.0e9f), memory_order_relaxed);
    atomic_store_explicit(&slot->lastStampMs, nowMs, memory_order_relaxed);
    MIAFXRingWrite(&slot->ring, mono, frames);
}

/* ------------------------------------------------------------- publisher --- */

bool MIAFXUnitDrainProbe(MIAFXUnitTable *table, uintptr_t *outKey) {
    if (!table || !outKey) return false;
    for (uint32_t i = 0u; i < MIAFX_PROBE_SLOTS; i++) {
        uintptr_t key = atomic_exchange_explicit(&table->queue[i], (uintptr_t)0u, memory_order_acq_rel);
        if (key != 0u) {
            *outKey = key;
            return true;
        }
    }
    return false;
}

bool MIAFXUnitDescribeFormat(const AudioStreamBasicDescription *asbd, MIAFXUnitView *out) {
    if (!asbd || !out) return false;

    MIAFXUnitView view = {0};
    if (asbd->mFormatID != kAudioFormatLinearPCM) return false;

    UInt32 flags = asbd->mFormatFlags;
    if (flags & kAudioFormatFlagIsBigEndian) return false; /* native endianness only */

    uint32_t channels = asbd->mChannelsPerFrame;
    if (channels < MIAFX_UNIT_MIN_CHANNELS || channels > MIAFX_UNIT_MAX_CHANNELS) return false;

    double sampleRate = asbd->mSampleRate;
    if (!(sampleRate >= MIAFX_UNIT_MIN_RATE && sampleRate <= MIAFX_UNIT_MAX_RATE)) return false;

    uint32_t bits = asbd->mBitsPerChannel;
    if (flags & kAudioFormatFlagIsFloat) {
        if (bits != 32u) return false;
        view.format = (uint32_t)MIAFXUnitFormatFloat32;
        view.bytesPerSample = 4u;
        view.scale = 1.0f;
    } else if (flags & kAudioFormatFlagIsSignedInteger) {
        if (bits == 16u) {
            view.format = (uint32_t)MIAFXUnitFormatInt16;
            view.bytesPerSample = 2u;
            view.scale = 1.0f / 32768.0f;
        } else if (bits == 32u) {
            view.format = (uint32_t)MIAFXUnitFormatInt32;
            view.bytesPerSample = 4u;
            view.scale = 1.0f / 2147483648.0f;
        } else {
            return false; /* 8/24 bit and unsigned PCM are not supported */
        }
    } else {
        return false;
    }

    /* Non-packed samples live in a wider container; only 32-bit containers are
     * unambiguous enough for a lock-free reader. */
    if (!(flags & kAudioFormatFlagIsPacked) && bits != 32u) return false;

    view.interleaved = (flags & kAudioFormatFlagIsNonInterleaved) ? 0u : 1u;
    view.channels = channels;
    view.sampleRate = sampleRate;

    uint32_t stride = asbd->mBytesPerFrame;
    if (stride == 0u) {
        stride = view.interleaved ? channels * view.bytesPerSample : view.bytesPerSample;
    }
    if (view.interleaved && stride < channels * view.bytesPerSample) return false;
    if (!view.interleaved && stride < view.bytesPerSample) return false;
    view.bytesPerFrame = stride;

    *out = view;
    return true;
}

static void MIAFXUnitInstall(MIAFXUnitSlot *slot, uintptr_t key,
                             const AudioStreamBasicDescription *asbd,
                             const MIAFXUnitView *view, uint64_t nowMs, bool resetRing) {
    uint32_t generation = atomic_load_explicit(&slot->generation, memory_order_relaxed);

    atomic_store_explicit(&slot->state, (uint32_t)MIAFXUnitSlotPending, memory_order_relaxed);
    atomic_store_explicit(&slot->generation, generation + 1u, memory_order_relaxed); /* odd */
    atomic_thread_fence(memory_order_release);

    slot->asbd = *asbd;
    slot->view = *view;
    if (resetRing) MIAFXRingInit(&slot->ring);

    atomic_thread_fence(memory_order_release);
    atomic_store_explicit(&slot->generation, generation + 2u, memory_order_release); /* even */
    atomic_store_explicit(&slot->unitKey, key, memory_order_release);
    atomic_store_explicit(&slot->state, (uint32_t)MIAFXUnitSlotReady, memory_order_release);

    atomic_store_explicit(&slot->activity, (uint64_t)0u, memory_order_relaxed);
    atomic_store_explicit(&slot->lastStampMs, nowMs, memory_order_relaxed);
    slot->installedMs = nowMs;
    slot->verifiedMs = nowMs;
}

static void MIAFXUnitReject(MIAFXUnitSlot *slot, uintptr_t key, uint64_t nowMs) {
    uint32_t generation = atomic_load_explicit(&slot->generation, memory_order_relaxed);

    atomic_store_explicit(&slot->state, (uint32_t)MIAFXUnitSlotPending, memory_order_relaxed);
    atomic_store_explicit(&slot->generation, generation + 1u, memory_order_relaxed);
    atomic_thread_fence(memory_order_release);

    MIAFXUnitView empty = {0};
    slot->view = empty;
    MIAFXRingInit(&slot->ring);

    atomic_thread_fence(memory_order_release);
    atomic_store_explicit(&slot->generation, generation + 2u, memory_order_release);
    atomic_store_explicit(&slot->unitKey, key, memory_order_release);
    atomic_store_explicit(&slot->state, (uint32_t)MIAFXUnitSlotRejected, memory_order_release);

    atomic_store_explicit(&slot->activity, (uint64_t)0u, memory_order_relaxed);
    atomic_store_explicit(&slot->lastStampMs, nowMs, memory_order_relaxed);
    slot->installedMs = nowMs;
    slot->verifiedMs = nowMs;
}

static void MIAFXUnitRetire(MIAFXUnitSlot *slot) {
    uint32_t generation = atomic_load_explicit(&slot->generation, memory_order_relaxed);

    atomic_store_explicit(&slot->generation, generation + 1u, memory_order_relaxed);
    atomic_thread_fence(memory_order_release);

    MIAFXUnitView empty = {0};
    slot->view = empty;
    atomic_store_explicit(&slot->unitKey, (uintptr_t)0u, memory_order_relaxed);
    atomic_store_explicit(&slot->state, (uint32_t)MIAFXUnitSlotFree, memory_order_release);
    MIAFXRingInit(&slot->ring);

    atomic_thread_fence(memory_order_release);
    atomic_store_explicit(&slot->generation, generation + 2u, memory_order_release);

    atomic_store_explicit(&slot->activity, (uint64_t)0u, memory_order_relaxed);
    atomic_store_explicit(&slot->lastStampMs, (uint64_t)0u, memory_order_relaxed);
    slot->installedMs = 0u;
    slot->verifiedMs = 0u;
}

static MIAFXUnitSlot *MIAFXUnitAcquireSlot(MIAFXUnitTable *table, uintptr_t key) {
    /* Reuse the descriptor of this exact unit if it still exists. */
    for (uint32_t i = 0u; i < MIAFX_UNIT_TABLE_SIZE; i++) {
        if (atomic_load_explicit(&table->slots[i].unitKey, memory_order_acquire) == key) {
            return &table->slots[i];
        }
    }
    /* Then a free slot. */
    for (uint32_t i = 0u; i < MIAFX_UNIT_TABLE_SIZE; i++) {
        MIAFXUnitSlot *slot = &table->slots[i];
        if (atomic_load_explicit(&slot->state, memory_order_acquire) == (uint32_t)MIAFXUnitSlotFree) {
            return slot;
        }
    }
    /* Otherwise evict the least recently heard slot.  Bounded scan, no retry. */
    MIAFXUnitSlot *victim = &table->slots[0];
    uint64_t oldest = atomic_load_explicit(&victim->lastStampMs, memory_order_acquire);
    for (uint32_t i = 1u; i < MIAFX_UNIT_TABLE_SIZE; i++) {
        MIAFXUnitSlot *slot = &table->slots[i];
        uint64_t stamp = atomic_load_explicit(&slot->lastStampMs, memory_order_acquire);
        if (stamp < oldest) {
            victim = slot;
            oldest = stamp;
        }
    }
    return victim;
}

static bool MIAFXUnitQueryFormat(uintptr_t key, AudioStreamBasicDescription *outAsbd) {
    if (key == 0u || !outAsbd) return false;
    AudioStreamBasicDescription asbd = {0};
    UInt32 size = (UInt32)sizeof(asbd);
    OSStatus status = AudioUnitGetProperty((AudioUnit)key, kAudioUnitProperty_StreamFormat,
                                           kAudioUnitScope_Output, 0, &asbd, &size);
    if (status != noErr) return false;
    if (size != (UInt32)sizeof(asbd)) return false;
    *outAsbd = asbd;
    return true;
}

void MIAFXUnitResolve(MIAFXUnitTable *table, uintptr_t key, uint64_t nowMs) {
    if (!table || key == 0u) return;

    AudioStreamBasicDescription asbd = {0};
    MIAFXUnitView view = {0};
    bool supported = MIAFXUnitQueryFormat(key, &asbd) && MIAFXUnitDescribeFormat(&asbd, &view);

    MIAFXUnitSlot *slot = MIAFXUnitAcquireSlot(table, key);
    if (!slot) return;
    if (supported) {
        bool sameUnit = atomic_load_explicit(&slot->unitKey, memory_order_acquire) == key;
        MIAFXUnitInstall(slot, key, &asbd, &view, nowMs, !sameUnit);
    } else {
        MIAFXUnitReject(slot, key, nowMs);
    }
}

void MIAFXUnitRefreshAt(MIAFXUnitTable *table, uint32_t index, uint64_t nowMs) {
    if (!table || index >= MIAFX_UNIT_TABLE_SIZE) return; /* bound check */
    MIAFXUnitSlot *slot = &table->slots[index];

    uint32_t state = atomic_load_explicit(&slot->state, memory_order_acquire);
    if (state == (uint32_t)MIAFXUnitSlotFree || state == (uint32_t)MIAFXUnitSlotPending) return;

    uint64_t stamp = atomic_load_explicit(&slot->lastStampMs, memory_order_acquire);

    if (state == (uint32_t)MIAFXUnitSlotRejected) {
        /* Give the slot back eventually so the table never fills up with
         * permanently dead entries; a live unit re-probes on the next render. */
        if (slot->installedMs + MIAFX_UNIT_REJECT_TTL_MS < nowMs) MIAFXUnitRetire(slot);
        return;
    }

    if (stamp == 0u || stamp + MIAFX_UNIT_IDLE_RETIRE_MS < nowMs) {
        MIAFXUnitRetire(slot); /* unit stopped rendering (or was destroyed) */
        return;
    }
    if (slot->verifiedMs + MIAFX_UNIT_VERIFY_INTERVAL_MS > nowMs) return;
    slot->verifiedMs = nowMs;

    uintptr_t key = atomic_load_explicit(&slot->unitKey, memory_order_acquire);
    AudioStreamBasicDescription asbd = {0};
    MIAFXUnitView view = {0};
    if (!MIAFXUnitQueryFormat(key, &asbd) || !MIAFXUnitDescribeFormat(&asbd, &view)) {
        MIAFXUnitReject(slot, key, nowMs);
        return;
    }
    /* Same slot: keep the accumulated ring so the next frame is not starved. */
    MIAFXUnitInstall(slot, key, &asbd, &view, nowMs, false);
}

MIAFXUnitSlot *MIAFXUnitSelectActive(MIAFXUnitTable *table, uint64_t nowMs, uint64_t staleMs) {
    if (!table) return NULL;
    MIAFXUnitSlot *best = NULL;
    uint64_t bestActivity = 0u;
    for (uint32_t i = 0u; i < MIAFX_UNIT_TABLE_SIZE; i++) {
        MIAFXUnitSlot *slot = &table->slots[i];
        if (atomic_load_explicit(&slot->state, memory_order_acquire) != (uint32_t)MIAFXUnitSlotReady) continue;
        uint64_t stamp = atomic_load_explicit(&slot->lastStampMs, memory_order_acquire);
        if (stamp == 0u || stamp + staleMs < nowMs) continue;
        uint64_t activity = atomic_load_explicit(&slot->activity, memory_order_acquire);
        if (!best || activity > bestActivity) {
            best = slot;
            bestActivity = activity;
        }
    }
    return best;
}
