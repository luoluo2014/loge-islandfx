#include "MIAFXSpectrumResample.h"
#include <math.h>

static float clampf(float value, float low, float high) {
    return value < low ? low : (value > high ? high : value);
}

void MIAFXSpectrumResample(const uint8_t input[16], float *output, size_t count, float sensitivity, float smoothing, float *history) {
    if (!input || !output || count == 0) return;
    sensitivity = clampf(sensitivity, 0.05f, 4.0f);
    smoothing = clampf(smoothing, 0.0f, 0.98f);
    for (size_t i = 0; i < count; i++) {
        float t = count == 1 ? 0.0f : (float)i / (float)(count - 1);
        float source = t * 15.0f;
        size_t lo = (size_t)floorf(source);
        size_t hi = lo < 15 ? lo + 1 : lo;
        float f = source - (float)lo;
        float sample = ((1.0f - f) * input[lo] + f * input[hi]) / 255.0f;
        sample = clampf(sample * sensitivity, 0.0f, 1.0f);
        if (history) {
            float previous = history[i];
            sample = previous * smoothing + sample * (1.0f - smoothing);
            history[i] = sample;
        }
        output[i] = sample;
    }
}
