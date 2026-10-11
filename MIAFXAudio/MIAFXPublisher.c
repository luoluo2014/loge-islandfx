#include "MIAFXPublisher.h"

#include <math.h>
#include <notify.h>
#include <pthread.h>
#include <stdatomic.h>
#include <time.h>

#include "MIAFXBands.h"
#include "MIAFXConstants.h"
#include "MIAFXFFT.h"
#include "MIAFXIPC.h"

/* Cadence. */
#define MIAFX_PUBLISH_ACTIVE_MS 33u  /* ~30 Hz */
#define MIAFX_PUBLISH_REDUCED_MS 200u /* 5 Hz while the input is silent */
#define MIAFX_PUBLISH_IDLE_MS 500u    /* 2 Hz while stopped or disabled */

/* A unit counts as "live" if it rendered within this window. */
#define MIAFX_UNIT_STALE_MS 250u

/* Silence detection: mean square * 1e9 (see MIAFXUnitProbe activity) and the
 * matching linear RMS floor. */
#define MIAFX_ACTIVITY_FLOOR 40ull      /* ~= RMS 2.0e-4 */
#define MIAFX_SILENCE_RMS 2.0e-4f
#define MIAFX_SILENCE_REDUCE_CYCLES 3u
#define MIAFX_SILENCE_STOP_CYCLES 25u   /* ~5 s of silence at 5 Hz */

static float gSamples[MIAFX_FFT_SIZE];
static float gMagnitude[MIAFX_FFT_BINS];

static _Atomic uint32_t gEnabled;
static _Atomic uint32_t gStarted;

static int gTokenA = -1;
static int gTokenB = -1;
static int gTokenM = -1;
static int gTokenT = -1;
static int gEnabledToken = -1;

uint64_t MIAFXMonotonicMilliseconds(void) {
    uint64_t nanos = (uint64_t)clock_gettime_nsec_np(CLOCK_MONOTONIC);
    return nanos / 1000000ull;
}

bool MIAFXPublisherIsEnabled(void) {
    return atomic_load_explicit(&gEnabled, memory_order_relaxed) != 0u;
}

static void MIAFXSleepUntil(uint64_t deadlineMs) {
    for (uint32_t guard = 0u; guard < 8u; guard++) {
        uint64_t now = MIAFXMonotonicMilliseconds();
        if (now >= deadlineMs) return;
        uint64_t remaining = deadlineMs - now;
        struct timespec request;
        request.tv_sec = (time_t)(remaining / 1000ull);
        request.tv_nsec = (long)((remaining % 1000ull) * 1000000ull);
        if (nanosleep(&request, NULL) == 0) return;
    }
}

static void MIAFXRegisterToken(const char *name, int *token) {
    int local = -1;
    if (notify_register_check(name, &local) != NOTIFY_STATUS_OK) local = -1;
    *token = local;
}

static void MIAFXPollEnabled(void) {
    bool enabled = true;
    if (gEnabledToken >= 0) {
        int check = 0;
        notify_check(gEnabledToken, &check);
        uint64_t state = 0;
        if (notify_get_state(gEnabledToken, &state) != NOTIFY_STATUS_OK) state = 0;
        if (state & MIAFX_AUDIO_STATE_VALID) {
            enabled = (state & MIAFX_AUDIO_STATE_ENABLED) != 0ull;
        }
    }
    atomic_store_explicit(&gEnabled, enabled ? 1u : 0u, memory_order_release);
}

static void MIAFXLevels(const float *samples, uint32_t count, float *peak, float *rms) {
    float max = 0.0f;
    float sum = 0.0f;
    for (uint32_t i = 0u; i < count; i++) {
        float value = samples[i];
        if (value < 0.0f) value = -value;
        if (value > max) max = value;
        sum += samples[i] * samples[i];
    }
    *peak = max;
    *rms = (count > 0u) ? sqrtf(sum / (float)count) : 0.0f;
}

static void MIAFXPublish(uint16_t sequence, const uint8_t bands[MIAFX_BAND_COUNT], uint8_t peak,
                         uint8_t rms, uint8_t flags, uint8_t tier, uint16_t rate100, uint32_t timestamp) {
    MIAFXSpectrumFrame frame;
    for (uint32_t i = 0u; i < MIAFX_BAND_COUNT; i++) frame.bands[i] = bands[i];
    frame.peak = peak;
    frame.rms = rms;
    frame.flags = flags;
    frame.tier = tier;
    frame.sequence = sequence;
    frame.sampleRate100 = rate100;
    frame.timestamp32 = timestamp;

    MIAFXIPCWords words;
    MIAFXIPCPack(&frame, &words);

    /* All four words land before the tick is posted. */
    if (gTokenA >= 0) notify_set_state(gTokenA, words.a);
    if (gTokenB >= 0) notify_set_state(gTokenB, words.b);
    if (gTokenM >= 0) notify_set_state(gTokenM, words.metadata);
    if (gTokenT >= 0) notify_set_state(gTokenT, words.timing);
    notify_post(MIAFX_NOTIFY_FFT_TICK);
}

static void *MIAFXPublisherMain(void *context) {
    MIAFXUnitTable *table = (MIAFXUnitTable *)context;
    if (!table) return NULL;

    MIAFXFFT fft;
    MIAFXFFTInit(&fft);
    MIAFXBands bands;
    MIAFXBandsReset(&bands);

    float configuredRate = 0.0f;
    uint16_t sequence = 0u;
    uint32_t refreshIndex = 0u;
    uint64_t silenceCycles = 0u;
    uint8_t pendingFlags = 0u;
    uint64_t deadline = MIAFXMonotonicMilliseconds();

    for (;;) {
        uint64_t now = MIAFXMonotonicMilliseconds();
        MIAFXPollEnabled();

        if (!MIAFXPublisherIsEnabled()) {
            /* Disabled: the render hook is pass-through, so there is nothing to
             * analyse.  Keep polling at 2 Hz and stay off the CPU. */
            silenceCycles = MIAFX_SILENCE_STOP_CYCLES;
            MIAFXSleepUntil(now + MIAFX_PUBLISH_IDLE_MS);
            deadline = MIAFXMonotonicMilliseconds();
            continue;
        }

        /* Drain the probe queue.  Bounded by the queue size, no retry. */
        for (uint32_t i = 0u; i < MIAFX_PROBE_SLOTS; i++) {
            uintptr_t key = 0u;
            if (!MIAFXUnitDrainProbe(table, &key)) break;
            MIAFXUnitResolve(table, key, now);
        }

        /* One re-verification per tick, round-robin over the fixed table. */
        MIAFXUnitRefreshAt(table, refreshIndex, now);
        refreshIndex = (refreshIndex + 1u) % MIAFX_UNIT_TABLE_SIZE;

        MIAFXUnitSlot *slot = MIAFXUnitSelectActive(table, now, MIAFX_UNIT_STALE_MS);

        uint64_t activity = 0u;
        if (slot) activity = atomic_load_explicit(&slot->activity, memory_order_acquire);
        if (activity > MIAFX_ACTIVITY_FLOOR) silenceCycles = 0u;
        else if (silenceCycles < 0xffffffffull) silenceCycles++;

        uint8_t tier = MIAFX_SPECTRUM_TIER_ACTIVE;
        uint64_t period = MIAFX_PUBLISH_ACTIVE_MS;
        uint8_t flags = pendingFlags;
        if (silenceCycles >= MIAFX_SILENCE_STOP_CYCLES) {
            tier = MIAFX_SPECTRUM_TIER_IDLE;
            flags |= MIAFX_SPECTRUM_FLAG_SILENT | MIAFX_SPECTRUM_FLAG_IDLE;
            period = MIAFX_PUBLISH_IDLE_MS;
        } else if (silenceCycles >= MIAFX_SILENCE_REDUCE_CYCLES) {
            tier = MIAFX_SPECTRUM_TIER_REDUCED;
            flags |= MIAFX_SPECTRUM_FLAG_SILENT | MIAFX_SPECTRUM_FLAG_IDLE;
            period = MIAFX_PUBLISH_REDUCED_MS;
        }

        if (slot && tier != MIAFX_SPECTRUM_TIER_IDLE) {
            MIAFXUnitView view;
            if (MIAFXUnitViewSnapshot(slot, &view)) {
                if ((float)view.sampleRate != configuredRate) {
                    float binHz = (float)(view.sampleRate / (double)MIAFX_FFT_SIZE);
                    if (MIAFXBandsConfigure(&bands, (float)view.sampleRate, MIAFX_FFT_BINS, binHz)) {
                        configuredRate = (float)view.sampleRate;
                    }
                }
                if (MIAFXRingWritten(&slot->ring) >= MIAFX_FFT_SIZE &&
                    MIAFXRingReadLatest(&slot->ring, gSamples, MIAFX_FFT_SIZE) == MIAFX_FFT_SIZE) {
                    float peak = 0.0f;
                    float rms = 0.0f;
                    MIAFXLevels(gSamples, MIAFX_FFT_SIZE, &peak, &rms);
                    if (rms < MIAFX_SILENCE_RMS) flags |= MIAFX_SPECTRUM_FLAG_SILENT;

                    if (MIAFXFFTForward(&fft, gSamples, gMagnitude, MIAFX_FFT_BINS)) {
                        uint8_t bandValues[MIAFX_BAND_COUNT];
                        MIAFXBandsAnalyze(&bands, gMagnitude, MIAFX_FFT_BINS, bandValues);
                        uint8_t peakByte = 0u;
                        uint8_t rmsByte = 0u;
                        MIAFXBandsAnalyzeLevels(&bands, peak, rms, &peakByte, &rmsByte);

                        double rate = view.sampleRate;
                        uint32_t rate100 = 0u;
                        if (rate > 0.0) {
                            uint64_t scaled = (uint64_t)((rate + 50.0) / 100.0);
                            rate100 = scaled > 0xffffull ? 0xffffu : (uint16_t)scaled;
                        }
                        MIAFXPublish(sequence++, bandValues, peakByte, rmsByte, flags, tier,
                                     (uint16_t)rate100, (uint32_t)now);
                        pendingFlags = 0u;
                    }
                } else {
                    pendingFlags = MIAFX_SPECTRUM_FLAG_DROPPED;
                }
            }
        }

        /* A skipped publish means the frame was dropped (torn ring snapshot or
         * a descriptor being rewritten); pendingFlags carries that fact into
         * the next frame that does get published. */
        uint64_t next = deadline + period;
        uint64_t current = MIAFXMonotonicMilliseconds();
        if (next <= current || next > current + 2000ull) next = current + period;
        deadline = next;
        MIAFXSleepUntil(deadline);
    }
}

void MIAFXPublisherStart(MIAFXUnitTable *table) {
    if (!table) return;
    if (atomic_exchange_explicit(&gStarted, 1u, memory_order_acq_rel) != 0u) return;

    atomic_store_explicit(&gEnabled, 0u, memory_order_release);

    MIAFXRegisterToken(MIAFX_NOTIFY_FFT_A, &gTokenA);
    MIAFXRegisterToken(MIAFX_NOTIFY_FFT_B, &gTokenB);
    MIAFXRegisterToken(MIAFX_NOTIFY_FFT_M, &gTokenM);
    MIAFXRegisterToken(MIAFX_NOTIFY_FFT_T, &gTokenT);
    MIAFXRegisterToken(MIAFX_NOTIFY_AUDIO_ENABLED, &gEnabledToken);

    pthread_attr_t attributes;
    if (pthread_attr_init(&attributes) != 0) return;
    pthread_attr_setdetachstate(&attributes, PTHREAD_CREATE_DETACHED);
    pthread_attr_setstacksize(&attributes, 512u * 1024u);

    pthread_t thread;
    if (pthread_create(&thread, &attributes, MIAFXPublisherMain, table) != 0) {
        atomic_store_explicit(&gStarted, 0u, memory_order_release);
    }
    pthread_attr_destroy(&attributes);
}
