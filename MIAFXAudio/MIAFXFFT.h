#ifndef MIAFX_FFT_H
#define MIAFX_FFT_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define MIAFX_FFT_SIZE 1024u
#define MIAFX_FFT_BINS (MIAFX_FFT_SIZE / 2u)

/*
 * Iterative radix-2 in-place FFT.  Every table (Hann window, bit-reversal
 * permutation, twiddle factors) is precomputed by MIAFXFFTInit() so the hot
 * loop - which only ever runs on the publisher thread - is table lookups and
 * butterflies.  The context owns its scratch buffers, so MIAFXFFTForward never
 * allocates.
 */
typedef struct {
    float window[MIAFX_FFT_SIZE];
    float re[MIAFX_FFT_SIZE];
    float im[MIAFX_FFT_SIZE];
    float cosTable[MIAFX_FFT_SIZE / 2u];
    float sinTable[MIAFX_FFT_SIZE / 2u];
    uint16_t reverse[MIAFX_FFT_SIZE];
    bool initialized;
} MIAFXFFT;

void MIAFXFFTInit(MIAFXFFT *fft);

/* Windowed forward transform.  Writes MIAFX_FFT_BINS magnitudes scaled by
 * 2/N (single-sided amplitude).  Returns false when the context is unusable or
 * `magnitudeCapacity` is too small; nothing is written in that case. */
bool MIAFXFFTForward(MIAFXFFT *fft, const float *input, float *magnitude, uint32_t magnitudeCapacity);

/* Window value for external tests / analysis. */
float MIAFXFFTWindowValue(const MIAFXFFT *fft, uint32_t index);

#ifdef __cplusplus
}
#endif

#endif /* MIAFX_FFT_H */
