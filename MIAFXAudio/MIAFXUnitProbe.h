#ifndef MIAFX_UNIT_PROBE_H
#define MIAFX_UNIT_PROBE_H

#include <AudioUnit/AudioUnit.h>
#include <CoreAudio/CoreAudioTypes.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>

#include "MIAFXRing.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * The audio graph of mediaserverd contains several AudioUnits.  We keep a fixed
 * descriptor table (no allocation, no locks) and a fixed size lock-free probe
 * queue.  The real-time render thread only ever:
 *   - compares atomic keys in the table,
 *   - reads a descriptor snapshot guarded by a generation seqlock,
 *   - downmixes at most MIAFX_UNIT_MAX_FRAMES samples and pushes them into a
 *     preallocated ring,
 *   - stores two relaxed atomics (activity / timestamp).
 * Anything that can block (AudioUnitGetProperty) is deferred to the publisher
 * thread through the probe queue.
 */
#define MIAFX_UNIT_TABLE_SIZE 8u
#define MIAFX_PROBE_SLOTS 8u
#define MIAFX_UNIT_MAX_FRAMES 512u /* render thread copies at most this many */

typedef enum {
    MIAFXUnitFormatUnsupported = 0,
    MIAFXUnitFormatFloat32 = 1,
    MIAFXUnitFormatInt16 = 2,
    MIAFXUnitFormatInt32 = 3,
} MIAFXUnitFormat;

typedef enum {
    MIAFXUnitSlotFree = 0,     /* unused */
    MIAFXUnitSlotPending = 1,  /* publisher is filling the descriptor */
    MIAFXUnitSlotReady = 2,    /* descriptor valid, render may capture */
    MIAFXUnitSlotRejected = 3, /* known but unusable: never probe again */
} MIAFXUnitSlotState;

/* Immutable description of a unit, copied out under the generation seqlock. */
typedef struct {
    uint32_t channels;      /* channels per frame (1..8) */
    uint32_t bytesPerFrame; /* stride of one frame inside one AudioBuffer */
    uint32_t bytesPerSample;
    uint32_t format;      /* MIAFXUnitFormat */
    uint32_t interleaved; /* 0 = non-interleaved: one buffer per channel */
    float scale;          /* integer PCM -> float normalisation */
    double sampleRate;
} MIAFXUnitView;

typedef struct {
    MIAFXRing ring; /* render writes, publisher reads */

    /* --- descriptor block: written by the publisher only --- */
    AudioStreamBasicDescription asbd;
    MIAFXUnitView view;

    /* --- atomics shared with the render thread --- */
    _Atomic uintptr_t unitKey;    /* AudioUnit pointer */
    _Atomic uint32_t state;       /* MIAFXUnitSlotState */
    _Atomic uint32_t generation;  /* seqlock over asbd/view; odd = writing */
    _Atomic uint64_t activity;    /* mean square * 1e9, render thread */
    _Atomic uint64_t lastStampMs; /* last render timestamp, render thread */

    /* --- publisher owned bookkeeping --- */
    uint64_t installedMs;
    uint64_t verifiedMs;
} MIAFXUnitSlot;

typedef struct {
    MIAFXUnitSlot slots[MIAFX_UNIT_TABLE_SIZE];
    _Atomic uintptr_t queue[MIAFX_PROBE_SLOTS];
    _Atomic uint64_t droppedProbes; /* queue was full: no retry, ever */
} MIAFXUnitTable;

void MIAFXUnitTableInit(MIAFXUnitTable *table);
MIAFXUnitTable *MIAFXUnitSharedTable(void);

/* ---------------------------------------------------------------- render --- */

/* Finds a ready descriptor for `key`.  Returns NULL for unknown, pending or
 * rejected units; the caller then calls MIAFXUnitRequestProbe() exactly once. */
MIAFXUnitSlot *MIAFXUnitLookup(MIAFXUnitTable *table, uintptr_t key);

/* Bounded, all-or-nothing enqueue.  Drops silently when the queue is full. */
void MIAFXUnitRequestProbe(MIAFXUnitTable *table, uintptr_t key);

/* Seqlock read of the descriptor block.  false = publisher is rewriting it,
 * the caller must skip this callback instead of waiting. */
bool MIAFXUnitViewSnapshot(MIAFXUnitSlot *slot, MIAFXUnitView *out);

/* Downmixes the freshly rendered buffers into the slot ring.  Real-time safe:
 * stack buffer only, no allocation, no locks, no logging. */
void MIAFXUnitCaptureRendered(MIAFXUnitSlot *slot, const AudioBufferList *ioData, uint32_t frameCount, uint64_t nowMs);

/* ------------------------------------------------------------- publisher --- */

bool MIAFXUnitDrainProbe(MIAFXUnitTable *table, uintptr_t *outKey);

/* Pure classification of an output-scope ASBD.  false = unsupported format. */
bool MIAFXUnitDescribeFormat(const AudioStreamBasicDescription *asbd, MIAFXUnitView *out);

/* Calls AudioUnitGetProperty on the publisher thread and installs, updates or
 * rejects the descriptor.  Never retries. */
void MIAFXUnitResolve(MIAFXUnitTable *table, uintptr_t key, uint64_t nowMs);

/* Re-verifies one slot (round-robin) and retires descriptors whose unit went
 * away or went quiet.  Bounded: one AudioUnitGetProperty per call. */
void MIAFXUnitRefreshAt(MIAFXUnitTable *table, uint32_t index, uint64_t nowMs);

/* Most active unit that rendered within `staleMs`. */
MIAFXUnitSlot *MIAFXUnitSelectActive(MIAFXUnitTable *table, uint64_t nowMs, uint64_t staleMs);

#ifdef __cplusplus
}
#endif

#endif /* MIAFX_UNIT_PROBE_H */
