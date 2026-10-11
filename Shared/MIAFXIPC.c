#include "MIAFXIPC.h"
#include <string.h>

_Static_assert(sizeof(uint64_t) == 8, "MIAFX IPC requires 64-bit uint64_t");

static uint64_t pack8(const uint8_t *values) {
    uint64_t word = 0;
    for (unsigned i = 0; i < 8; i++) word |= ((uint64_t)values[i]) << (i * 8u);
    return word;
}

static void unpack8(uint64_t word, uint8_t *values) {
    for (unsigned i = 0; i < 8; i++) values[i] = (uint8_t)((word >> (i * 8u)) & 0xffu);
}

void MIAFXIPCPack(const MIAFXSpectrumFrame *frame, MIAFXIPCWords *words) {
    if (!frame || !words) return;
    words->a = pack8(frame->bands);
    words->b = pack8(frame->bands + 8);
    words->metadata = (uint64_t)MIAFX_IPC_MAGIC
        | ((uint64_t)MIAFX_IPC_VERSION << 8u)
        | ((uint64_t)frame->sequence << 16u)
        | ((uint64_t)frame->peak << 32u)
        | ((uint64_t)frame->rms << 40u)
        | ((uint64_t)frame->flags << 48u)
        | ((uint64_t)frame->tier << 56u);
    words->timing = (uint64_t)frame->timestamp32 | ((uint64_t)frame->sampleRate100 << 32u);
}

bool MIAFXIPCUnpack(const MIAFXIPCWords *words, MIAFXSpectrumFrame *frame) {
    if (!words || !frame) return false;
    uint8_t magic = (uint8_t)(words->metadata & 0xffu);
    uint8_t version = (uint8_t)((words->metadata >> 8u) & 0xffu);
    if (magic != MIAFX_IPC_MAGIC || version != MIAFX_IPC_VERSION) return false;
    memset(frame, 0, sizeof(*frame));
    unpack8(words->a, frame->bands);
    unpack8(words->b, frame->bands + 8);
    frame->sequence = (uint16_t)((words->metadata >> 16u) & 0xffffu);
    frame->peak = (uint8_t)((words->metadata >> 32u) & 0xffu);
    frame->rms = (uint8_t)((words->metadata >> 40u) & 0xffu);
    frame->flags = (uint8_t)((words->metadata >> 48u) & 0xffu);
    frame->tier = (uint8_t)((words->metadata >> 56u) & 0xffu);
    frame->timestamp32 = (uint32_t)(words->timing & 0xffffffffu);
    frame->sampleRate100 = (uint16_t)((words->timing >> 32u) & 0xffffu);
    return true;
}
