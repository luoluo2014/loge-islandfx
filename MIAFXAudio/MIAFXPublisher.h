#ifndef MIAFX_PUBLISHER_H
#define MIAFX_PUBLISHER_H

#include <stdbool.h>
#include <stdint.h>

#include "MIAFXUnitProbe.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Spectrum frames are handed to SpringBoard through Darwin notification state:
 * the four 64 bit words of MIAFXIPCWords are stored on MIAFX_NOTIFY_FFT_A/B/M/T
 * with notify_set_state() and the consumer is woken by a single
 * notify_post(MIAFX_NOTIFY_FFT_TICK) once all four words are in place.
 *
 * The enable flag travels the same way: whoever owns the preference posts
 * MIAFX_NOTIFY_AUDIO_ENABLED with a state value.  Bit 0 marks "a controller has
 * published a value at all"; until that happens the pipeline defaults to
 * enabled so a fresh install works before the preferences bundle runs.
 */
#define MIAFX_AUDIO_STATE_VALID 0x1ull
#define MIAFX_AUDIO_STATE_ENABLED 0x2ull

/* MIAFXSpectrumFrame.flags */
#define MIAFX_SPECTRUM_FLAG_IDLE 0x01u    /* publisher is running below 30 Hz */
#define MIAFX_SPECTRUM_FLAG_DROPPED 0x02u /* previous ring snapshot was torn */
#define MIAFX_SPECTRUM_FLAG_SILENT 0x04u  /* input below the silence threshold */

/* MIAFXSpectrumFrame.tier */
#define MIAFX_SPECTRUM_TIER_ACTIVE 0u  /* 30 Hz */
#define MIAFX_SPECTRUM_TIER_REDUCED 1u /* 5 Hz, silence detected */
#define MIAFX_SPECTRUM_TIER_IDLE 2u    /* stopped, still watching for audio */

/* Monotonic clock in milliseconds (wraps after ~49 days, which is fine for a
 * uint32 timestamp).  Safe to call from any thread. */
uint64_t MIAFXMonotonicMilliseconds(void);

/* Starts the single publisher thread.  Idempotent. */
void MIAFXPublisherStart(MIAFXUnitTable *table);

/* Read by the render thread with a relaxed load: when false the hook is a pure
 * pass-through. */
bool MIAFXPublisherIsEnabled(void);

#ifdef __cplusplus
}
#endif

#endif /* MIAFX_PUBLISHER_H */
