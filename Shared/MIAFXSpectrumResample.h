#ifndef MIAFX_SPECTRUM_RESAMPLE_H
#define MIAFX_SPECTRUM_RESAMPLE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void MIAFXSpectrumResample(const uint8_t input[16], float *output, size_t count, float sensitivity, float smoothing, float *history);

#ifdef __cplusplus
}
#endif

#endif
