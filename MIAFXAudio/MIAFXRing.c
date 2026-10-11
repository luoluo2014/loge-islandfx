#include "MIAFXRing.h"

_Static_assert((MIAFX_RING_CAPACITY & (MIAFX_RING_CAPACITY - 1u)) == 0u,
               "MIAFX ring capacity must be a power of two");

void MIAFXRingInit(MIAFXRing *ring) {
    if (!ring) return;
    atomic_store_explicit(&ring->sequence, 0u, memory_order_relaxed);
    atomic_store_explicit(&ring->head, 0u, memory_order_relaxed);
    atomic_store_explicit(&ring->written, 0u, memory_order_relaxed);
}

uint32_t MIAFXRingWrite(MIAFXRing *ring, const float *samples, uint32_t count) {
    if (!ring || !samples || count == 0u) return 0u;
    if (count > MIAFX_RING_MAX_WRITE) count = MIAFX_RING_MAX_WRITE;

    uint32_t head = atomic_load_explicit(&ring->head, memory_order_relaxed);
    uint32_t sequence = atomic_load_explicit(&ring->sequence, memory_order_relaxed);

    /* Odd sequence == "writer inside the buffer". */
    atomic_store_explicit(&ring->sequence, sequence + 1u, memory_order_relaxed);
    atomic_thread_fence(memory_order_release);

    for (uint32_t i = 0u; i < count; i++) {
        ring->samples[(head + i) & MIAFX_RING_MASK] = samples[i];
    }

    uint32_t next = (head + count) & MIAFX_RING_MASK;
    uint32_t written = atomic_load_explicit(&ring->written, memory_order_relaxed);
    if (written < 0xffffffffu - count) written += count;
    else written = 0xffffffffu;

    atomic_store_explicit(&ring->written, written, memory_order_relaxed);
    atomic_store_explicit(&ring->head, next, memory_order_relaxed);

    atomic_thread_fence(memory_order_release);
    atomic_store_explicit(&ring->sequence, sequence + 2u, memory_order_release);
    return count;
}

void MIAFXRingWriteOne(MIAFXRing *ring, float sample) {
    MIAFXRingWrite(ring, &sample, 1u);
}

uint32_t MIAFXRingReadLatest(MIAFXRing *ring, float *out, uint32_t count) {
    if (!ring || !out || count == 0u || count > MIAFX_RING_CAPACITY) return 0u;

    uint32_t first = atomic_load_explicit(&ring->sequence, memory_order_acquire);
    if (first & 1u) return 0u; /* writer in flight: drop the frame */

    uint32_t head = atomic_load_explicit(&ring->head, memory_order_acquire);
    uint32_t start = (head + MIAFX_RING_CAPACITY - count) & MIAFX_RING_MASK;
    for (uint32_t i = 0u; i < count; i++) {
        out[i] = ring->samples[(start + i) & MIAFX_RING_MASK];
    }

    atomic_thread_fence(memory_order_acquire);
    uint32_t second = atomic_load_explicit(&ring->sequence, memory_order_acquire);
    if (first != second) return 0u; /* torn: drop the frame */
    return count;
}

uint32_t MIAFXRingWritten(MIAFXRing *ring) {
    if (!ring) return 0u;
    return atomic_load_explicit(&ring->written, memory_order_acquire);
}
