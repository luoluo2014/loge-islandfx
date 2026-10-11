#include "MIAFXBands.h"

#include <math.h>

/* Smoothing coefficients (0 = frozen, 1 = instant). */
#define MIAFX_BAND_ATTACK 0.55f
#define MIAFX_BAND_RELEASE 0.12f
#define MIAFX_PEAK_ATTACK 0.85f
#define MIAFX_PEAK_RELEASE 0.06f
#define MIAFX_RMS_ATTACK 0.45f
#define MIAFX_RMS_RELEASE 0.10f

/* Dynamic range mapped onto 0..1. */
#define MIAFX_BAND_FLOOR_DB -90.0f
#define MIAFX_LEVEL_FLOOR_DB -60.0f

/* max/mean mix inside a band: keeps tonal peaks visible in wide bands. */
#define MIAFX_BAND_PEAK_WEIGHT 0.65f
#define MIAFX_BAND_MEAN_WEIGHT 0.35f

static float clamp01(float value) {
    if (value < 0.0f) return 0.0f;
    if (value > 1.0f) return 1.0f;
    return value;
}

static float toDecibels(float linear) {
    if (!(linear > 1.0e-9f)) return -200.0f; /* also catches NaN */
    return 20.0f * log10f(linear);
}

float MIAFXBandsNormalizeMagnitude(float magnitude) {
    if (!(magnitude > 0.0f)) return 0.0f;
    float db = toDecibels(magnitude);
    return clamp01((db - MIAFX_BAND_FLOOR_DB) / -MIAFX_BAND_FLOOR_DB);
}

float MIAFXBandsNormalizeLevel(float linear) {
    if (!(linear > 0.0f)) return 0.0f;
    float db = toDecibels(linear);
    return clamp01((db - MIAFX_LEVEL_FLOOR_DB) / -MIAFX_LEVEL_FLOOR_DB);
}

uint8_t MIAFXBandsQuantize(float normalized) {
    float value = clamp01(normalized) * 255.0f + 0.5f;
    if (value > 255.0f) value = 255.0f;
    return (uint8_t)value;
}

float MIAFXBandsSmoothStep(float current, float target, float attack, float release) {
    float coefficient = target > current ? attack : release;
    return current + (target - current) * coefficient;
}

void MIAFXBandsReset(MIAFXBands *bands) {
    if (!bands) return;
    for (uint32_t i = 0u; i <= MIAFX_BAND_COUNT; i++) bands->edges[i] = 0.0f;
    for (uint32_t i = 0u; i < MIAFX_BAND_COUNT; i++) {
        bands->start[i] = 0u;
        bands->end[i] = 0u;
        bands->level[i] = 0.0f;
    }
    bands->peakLevel = 0.0f;
    bands->rmsLevel = 0.0f;
    bands->sampleRate = 0.0f;
    bands->binCount = 0u;
    bands->configured = false;
}

bool MIAFXBandsConfigure(MIAFXBands *bands, float sampleRate, uint32_t binCount, float binHz) {
    if (!bands) return false;
    MIAFXBandsReset(bands);
    if (!(sampleRate > 100.0f) || binCount < 2u || !(binHz > 0.0f)) return false;

    float nyquist = 0.5f * sampleRate;
    float top = MIAFX_BAND_MAX_HZ;
    if (top > nyquist) top = nyquist;
    if (!(top > MIAFX_BAND_MIN_HZ)) return false;

    float ratio = top / MIAFX_BAND_MIN_HZ;
    for (uint32_t i = 0u; i <= MIAFX_BAND_COUNT; i++) {
        float exponent = (float)i / (float)MIAFX_BAND_COUNT;
        bands->edges[i] = MIAFX_BAND_MIN_HZ * powf(ratio, exponent);
    }

    for (uint32_t i = 0u; i < MIAFX_BAND_COUNT; i++) {
        float low = bands->edges[i] / binHz;
        float high = bands->edges[i + 1u] / binHz;
        long startL = lroundf(low);
        long endL = lroundf(high);
        if (startL < 1L) startL = 1L; /* bin 0 is DC */
        if (startL > (long)(binCount - 1u)) startL = (long)(binCount - 1u);
        if (endL < startL + 1L) endL = startL + 1L;
        if (endL > (long)binCount) endL = (long)binCount;
        if (startL >= endL) startL = endL - 1L;
        bands->start[i] = (uint16_t)startL;
        bands->end[i] = (uint16_t)endL;
    }

    bands->sampleRate = sampleRate;
    bands->binCount = binCount;
    bands->configured = true;
    return true;
}

void MIAFXBandsAnalyze(MIAFXBands *bands, const float *magnitude, uint32_t binCount, uint8_t out[MIAFX_BAND_COUNT]) {
    if (!out) return;
    if (!bands || !bands->configured || !magnitude) {
        for (uint32_t i = 0u; i < MIAFX_BAND_COUNT; i++) out[i] = 0u;
        return;
    }
    uint32_t usable = bands->binCount;
    if (binCount < usable) usable = binCount;

    for (uint32_t band = 0u; band < MIAFX_BAND_COUNT; band++) {
        uint32_t start = bands->start[band];
        uint32_t end = bands->end[band];
        if (end > usable) end = usable;
        if (end <= start) {
            bands->level[band] = MIAFXBandsSmoothStep(bands->level[band], 0.0f, MIAFX_BAND_ATTACK, MIAFX_BAND_RELEASE);
            out[band] = MIAFXBandsQuantize(bands->level[band]);
            continue;
        }
        float maxValue = 0.0f;
        float sum = 0.0f;
        for (uint32_t bin = start; bin < end; bin++) {
            float value = magnitude[bin];
            if (value < 0.0f) value = -value;
            if (value > maxValue) maxValue = value;
            sum += value;
        }
        float mean = sum / (float)(end - start);
        float mixed = maxValue * MIAFX_BAND_PEAK_WEIGHT + mean * MIAFX_BAND_MEAN_WEIGHT;
        float target = MIAFXBandsNormalizeMagnitude(mixed);
        bands->level[band] = MIAFXBandsSmoothStep(bands->level[band], target, MIAFX_BAND_ATTACK, MIAFX_BAND_RELEASE);
        out[band] = MIAFXBandsQuantize(bands->level[band]);
    }
}

void MIAFXBandsAnalyzeLevels(MIAFXBands *bands, float peakLinear, float rmsLinear, uint8_t *outPeak, uint8_t *outRms) {
    if (!bands || !outPeak || !outRms) {
        if (outPeak) *outPeak = 0u;
        if (outRms) *outRms = 0u;
        return;
    }
    if (peakLinear < 0.0f) peakLinear = -peakLinear;
    if (rmsLinear < 0.0f) rmsLinear = -rmsLinear;

    float peakTarget = MIAFXBandsNormalizeLevel(peakLinear);
    float rmsTarget = MIAFXBandsNormalizeLevel(rmsLinear);
    bands->peakLevel = MIAFXBandsSmoothStep(bands->peakLevel, peakTarget, MIAFX_PEAK_ATTACK, MIAFX_PEAK_RELEASE);
    bands->rmsLevel = MIAFXBandsSmoothStep(bands->rmsLevel, rmsTarget, MIAFX_RMS_ATTACK, MIAFX_RMS_RELEASE);
    *outPeak = MIAFXBandsQuantize(bands->peakLevel);
    *outRms = MIAFXBandsQuantize(bands->rmsLevel);
}
