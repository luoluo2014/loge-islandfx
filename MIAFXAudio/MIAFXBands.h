#ifndef MIAFX_BANDS_H
#define MIAFX_BANDS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define MIAFX_BAND_COUNT 16u
#define MIAFX_BAND_MIN_HZ 20.0f
#define MIAFX_BAND_MAX_HZ 16000.0f

/*
 * 16 logarithmically spaced bands between 20 Hz and min(16 kHz, Nyquist).
 * Per band the analyser mixes the peak bin (max) with the band average (mean)
 * so tonal content is not washed out by wide high-frequency bands, maps the
 * result to dB, then smooths it with separate attack/release coefficients.
 */
typedef struct {
    float edges[MIAFX_BAND_COUNT + 1u]; /* Hz, only used for diagnostics */
    uint16_t start[MIAFX_BAND_COUNT];   /* inclusive bin index */
    uint16_t end[MIAFX_BAND_COUNT];     /* exclusive bin index */
    float level[MIAFX_BAND_COUNT];      /* smoothed 0..1 */
    float peakLevel;                    /* smoothed 0..1 */
    float rmsLevel;                     /* smoothed 0..1 */
    float sampleRate;
    uint32_t binCount;
    bool configured;
} MIAFXBands;

void MIAFXBandsReset(MIAFXBands *bands);

/* sampleRate: unit sample rate in Hz.  binCount: available magnitude bins.
 * binHz: Hz per bin (sampleRate / fftSize).  Returns false for unusable input,
 * in which case the context stays unconfigured and MIAFXBandsAnalyze is a no-op
 * that emits silence. */
bool MIAFXBandsConfigure(MIAFXBands *bands, float sampleRate, uint32_t binCount, float binHz);

/* Fills out[0..15] with quantised 0..255 band levels. */
void MIAFXBandsAnalyze(MIAFXBands *bands, const float *magnitude, uint32_t binCount, uint8_t out[MIAFX_BAND_COUNT]);

/* Smooths and quantises the wideband peak / RMS levels of the same window. */
void MIAFXBandsAnalyzeLevels(MIAFXBands *bands, float peakLinear, float rmsLinear, uint8_t *outPeak, uint8_t *outRms);

/* Shared helpers, exposed so host-side tests can check the curve. */
float MIAFXBandsNormalizeMagnitude(float magnitude);
float MIAFXBandsNormalizeLevel(float linear);
uint8_t MIAFXBandsQuantize(float normalized);
float MIAFXBandsSmoothStep(float current, float target, float attack, float release);

#ifdef __cplusplus
}
#endif

#endif /* MIAFX_BANDS_H */
