#ifndef MIAFX_IPC_H
#define MIAFX_IPC_H

#include <stdbool.h>
#include <stdint.h>
#include "MIAFXConstants.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint8_t bands[16];
    uint8_t peak;
    uint8_t rms;
    uint8_t flags;
    uint8_t tier;
    uint16_t sequence;
    uint16_t sampleRate100;
    uint32_t timestamp32;
} MIAFXSpectrumFrame;

typedef struct {
    uint64_t a;
    uint64_t b;
    uint64_t metadata;
    uint64_t timing;
} MIAFXIPCWords;

void MIAFXIPCPack(const MIAFXSpectrumFrame *frame, MIAFXIPCWords *words);
bool MIAFXIPCUnpack(const MIAFXIPCWords *words, MIAFXSpectrumFrame *frame);

#ifdef __cplusplus
}
#endif

#endif
