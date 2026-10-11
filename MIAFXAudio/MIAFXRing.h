#ifndef MIAFX_RING_H
#define MIAFX_RING_H

#include <stdatomic.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Single-producer / single-consumer seqlock ring for the mediaserverd render
 * thread.  The writer (real-time AudioUnitRender thread) only touches the
 * buffer through MIAFXRingWrite* which never allocates, never blocks and never
 * calls into libSystem.  The reader (publisher thread) uses MIAFXRingReadLatest
 * which is a seqlock snapshot: if the writer was in the middle of a commit the
 * read fails immediately and the caller drops the frame.
 *
 * Capacity is a power of two so wrapping is a mask, never a division.
 */
#define MIAFX_RING_CAPACITY 4096u /* >= 2048 required by contract */
#define MIAFX_RING_MASK (MIAFX_RING_CAPACITY - 1u)
#define MIAFX_RING_MAX_WRITE 512u /* render thread never copies more per call */

typedef struct {
    _Atomic uint32_t sequence; /* seqlock: odd while a commit is in flight */
    _Atomic uint32_t head;     /* index of the next slot to be written */
    _Atomic uint32_t written;  /* total samples committed, saturating */
    float samples[MIAFX_RING_CAPACITY];
} MIAFXRing;

/* Clears the bookkeeping.  samples[] is intentionally not scrubbed: the caller
 * only ever reads what MIAFXRingWritten() says was committed. */
void MIAFXRingInit(MIAFXRing *ring);

/* Writer side - real-time safe.  Counts above MIAFX_RING_MAX_WRITE are clamped
 * so a single render callback can never monopolise the buffer.  Returns the
 * number of samples actually committed. */
uint32_t MIAFXRingWrite(MIAFXRing *ring, const float *samples, uint32_t count);
void MIAFXRingWriteOne(MIAFXRing *ring, float sample);

/* Reader side - returns `count` on a clean snapshot, 0 if the writer raced us
 * (caller must drop the frame, never retry in a loop). */
uint32_t MIAFXRingReadLatest(MIAFXRing *ring, float *out, uint32_t count);

/* Number of samples committed since init (saturating). */
uint32_t MIAFXRingWritten(MIAFXRing *ring);

#ifdef __cplusplus
}
#endif

#endif /* MIAFX_RING_H */
