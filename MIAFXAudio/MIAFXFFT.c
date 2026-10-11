#include "MIAFXFFT.h"

#include <math.h>

#define MIAFX_FFT_PI 3.14159265358979323846f

_Static_assert((MIAFX_FFT_SIZE & (MIAFX_FFT_SIZE - 1u)) == 0u, "FFT size must be a power of two");
_Static_assert(MIAFX_FFT_SIZE >= 2u, "FFT size must be at least 2");
_Static_assert(MIAFX_FFT_SIZE <= 0xffffu, "FFT size must fit the uint16_t reverse table");

void MIAFXFFTInit(MIAFXFFT *fft) {
    if (!fft) return;

    /* Periodic Hann window. */
    for (uint32_t i = 0u; i < MIAFX_FFT_SIZE; i++) {
        float phase = (2.0f * MIAFX_FFT_PI * (float)i) / (float)MIAFX_FFT_SIZE;
        fft->window[i] = 0.5f * (1.0f - cosf(phase));
    }

    /* Twiddle factors exp(-2*pi*i*k/N) for k in [0, N/2). */
    for (uint32_t k = 0u; k < MIAFX_FFT_SIZE / 2u; k++) {
        float angle = (-2.0f * MIAFX_FFT_PI * (float)k) / (float)MIAFX_FFT_SIZE;
        fft->cosTable[k] = cosf(angle);
        fft->sinTable[k] = sinf(angle);
    }

    /* Bit-reversal permutation table. */
    uint32_t bits = 0u;
    for (uint32_t n = MIAFX_FFT_SIZE; n > 1u; n >>= 1u) bits++;
    for (uint32_t i = 0u; i < MIAFX_FFT_SIZE; i++) {
        uint32_t reversed = 0u;
        for (uint32_t b = 0u; b < bits; b++) {
            if (i & (1u << b)) reversed |= 1u << (bits - 1u - b);
        }
        fft->reverse[i] = (uint16_t)reversed;
    }

    for (uint32_t i = 0u; i < MIAFX_FFT_SIZE; i++) {
        fft->re[i] = 0.0f;
        fft->im[i] = 0.0f;
    }

    fft->initialized = true;
}

float MIAFXFFTWindowValue(const MIAFXFFT *fft, uint32_t index) {
    if (!fft || index >= MIAFX_FFT_SIZE) return 0.0f;
    return fft->window[index];
}

bool MIAFXFFTForward(MIAFXFFT *fft, const float *input, float *magnitude, uint32_t magnitudeCapacity) {
    if (!fft || !fft->initialized || !input || !magnitude) return false;
    if (magnitudeCapacity < MIAFX_FFT_BINS) return false;

    /* Window + zeroed imaginary part. */
    for (uint32_t i = 0u; i < MIAFX_FFT_SIZE; i++) {
        fft->re[i] = input[i] * fft->window[i];
        fft->im[i] = 0.0f;
    }

    /* Bit-reversal permutation (in place, each pair swapped once). */
    for (uint32_t i = 0u; i < MIAFX_FFT_SIZE; i++) {
        uint32_t j = (uint32_t)fft->reverse[i];
        if (j <= i) continue;
        float tmp = fft->re[i];
        fft->re[i] = fft->re[j];
        fft->re[j] = tmp;
        tmp = fft->im[i];
        fft->im[i] = fft->im[j];
        fft->im[j] = tmp;
    }

    /* Decimation-in-time butterflies. */
    for (uint32_t length = 2u; length <= MIAFX_FFT_SIZE; length <<= 1u) {
        uint32_t half = length >> 1u;
        uint32_t step = MIAFX_FFT_SIZE / length;
        for (uint32_t base = 0u; base < MIAFX_FFT_SIZE; base += length) {
            for (uint32_t k = 0u; k < half; k++) {
                uint32_t twiddle = k * step; /* < N/2 for every stage */
                float wr = fft->cosTable[twiddle];
                float wi = fft->sinTable[twiddle];

                uint32_t lower = base + k;
                uint32_t upper = lower + half;

                float xr = fft->re[upper];
                float xi = fft->im[upper];
                float tr = xr * wr - xi * wi;
                float ti = xr * wi + xi * wr;

                float ur = fft->re[lower];
                float ui = fft->im[lower];

                fft->re[lower] = ur + tr;
                fft->im[lower] = ui + ti;
                fft->re[upper] = ur - tr;
                fft->im[upper] = ui - ti;
            }
        }
    }

    /* Single-sided magnitude spectrum. */
    const float scale = 2.0f / (float)MIAFX_FFT_SIZE;
    for (uint32_t i = 0u; i < MIAFX_FFT_BINS; i++) {
        float r = fft->re[i];
        float m = fft->im[i];
        magnitude[i] = sqrtf(r * r + m * m) * scale;
    }
    return true;
}
