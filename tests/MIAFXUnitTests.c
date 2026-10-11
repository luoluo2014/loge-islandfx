/*
 * MIAFX 离线单元测试（宿主编译，不依赖 iOS SDK）
 *
 * 覆盖：FFT / 16 频段分析 / 无锁环形缓冲 / IPC 打包 / 频谱插值重采样。
 * 这些模块是纯 C，可在 macOS / Linux 上用 clang 直接编译运行，
 * 用于在无法真机编译的环境下验证数值与内存语义正确。
 *
 * 编译：见 tests/Makefile（make -C tests && ./tests/miafx-tests）
 */

#include <math.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "MIAFXFFT.h"
#include "MIAFXBands.h"
#include "MIAFXRing.h"
#include "MIAFXIPC.h"
#include "MIAFXSpectrumResample.h"

static int gFailures = 0;
static int gChecks = 0;

static void check(bool condition, const char *name, const char *detail) {
    gChecks++;
    if (!condition) {
        gFailures++;
        printf("  [FAIL] %s%s%s\n", name, detail ? " - " : "", detail ? detail : "");
    } else {
        printf("  [ ok ] %s\n", name);
    }
}

/* ------------------------------------------------------------------ FFT --- */

static void testFFT(void) {
    printf("\n== FFT ==\n");
    MIAFXFFT fft;
    MIAFXFFTInit(&fft);
    check(fft.initialized, "FFT 初始化完成", NULL);

    float input[MIAFX_FFT_SIZE];
    float magnitude[MIAFX_FFT_BINS];
    char detail[128];

    /* 1) 直流信号：能量应集中在 bin 0 */
    for (uint32_t i = 0; i < MIAFX_FFT_SIZE; i++) input[i] = 1.0f;
    check(MIAFXFFTForward(&fft, input, magnitude, MIAFX_FFT_BINS), "直流输入变换成功", NULL);
    check(magnitude[0] > 0.5f, "直流能量集中在 bin0", NULL);
    /* Hann 窗的主瓣宽度为 4 个 bin，DC 的能量必然溢出到 bin1（理论值为
     * magnitude[0] 的一半），因此只校验远离主瓣的泄漏足够小。 */
    float farTail = 0.0f;
    for (uint32_t i = 2; i < MIAFX_FFT_BINS; i++) farTail += magnitude[i];
    check(farTail < magnitude[0] * 0.05f, "直流输入远区泄漏低于 5%", NULL);
    float bin1Ratio = magnitude[1] / magnitude[0];
    snprintf(detail, sizeof(detail), "bin1/bin0 = %.3f（理论 0.500）", bin1Ratio);
    check(fabsf(bin1Ratio - 0.5f) < 0.08f, "Hann 窗主瓣形状正确", detail);

    /* 2) 纯正弦：峰值 bin 应落在目标频率附近 */
    float sampleRate = 48000.0f;
    float binHz = sampleRate / (float)MIAFX_FFT_SIZE; /* 46.875 Hz */
    float targetHz = 1000.0f;
    uint32_t expectedBin = (uint32_t)llroundf(targetHz / binHz);
    for (uint32_t i = 0; i < MIAFX_FFT_SIZE; i++) {
        input[i] = sinf(2.0f * (float)M_PI * targetHz * (float)i / sampleRate);
    }
    check(MIAFXFFTForward(&fft, input, magnitude, MIAFX_FFT_BINS), "1kHz 正弦变换成功", NULL);
    uint32_t peakBin = 0;
    float peakValue = -1.0f;
    for (uint32_t i = 0; i < MIAFX_FFT_BINS; i++) {
        if (magnitude[i] > peakValue) { peakValue = magnitude[i]; peakBin = i; }
    }
    snprintf(detail, sizeof(detail), "期望 bin %u 实际 %u", expectedBin, peakBin);
    check(peakBin >= expectedBin - 1 && peakBin <= expectedBin + 1, "1kHz 峰值 bin 正确", detail);
    check(peakValue > 0.2f, "1kHz 峰值幅度合理", NULL);

    /* 3) 静音：不得产生 NaN / Inf，且整体接近 0 */
    memset(input, 0, sizeof(input));
    check(MIAFXFFTForward(&fft, input, magnitude, MIAFX_FFT_BINS), "静音输入变换成功", NULL);
    bool finite = true, silent = true;
    for (uint32_t i = 0; i < MIAFX_FFT_BINS; i++) {
        if (!isfinite(magnitude[i])) finite = false;
        if (magnitude[i] > 1e-3f) silent = false;
    }
    check(finite, "静音输入无 NaN/Inf", NULL);
    check(silent, "静音输入幅度接近 0", NULL);

    /* 4) 容量不足时必须拒绝写入而不是越界 */
    float tiny[4];
    check(!MIAFXFFTForward(&fft, input, tiny, 4), "容量不足时安全返回 false", NULL);

    /* 5) 空指针防御 */
    check(!MIAFXFFTForward(NULL, input, magnitude, MIAFX_FFT_BINS), "空上下文被拒绝", NULL);
    check(!MIAFXFFTForward(&fft, NULL, magnitude, MIAFX_FFT_BINS), "空输入被拒绝", NULL);

    /* 6) 未初始化的上下文不得崩溃 */
    MIAFXFFT zero = {0};
    check(!MIAFXFFTForward(&zero, input, magnitude, MIAFX_FFT_BINS), "未初始化上下文被拒绝", NULL);
}

/* ---------------------------------------------------------------- Bands --- */

static void testBands(void) {
    printf("\n== 16 频段分析 ==\n");
    MIAFXBands bands;
    MIAFXBandsReset(&bands);
    check(!bands.configured, "reset 后未配置", NULL);

    float sampleRate = 48000.0f;
    float binHz = sampleRate / (float)MIAFX_FFT_SIZE;
    uint32_t binCount = MIAFX_FFT_BINS;
    check(MIAFXBandsConfigure(&bands, sampleRate, binCount, binHz), "48k/1024 配置成功", NULL);
    check(bands.configured, "配置标志置位", NULL);

    /* 低频段受 bin 分辨率限制会共用相邻 bin（20Hz 远小于 46.9Hz 的 bin 宽度），
     * 这是预期行为；校验的是区间有效、单调不减且不越界。 */
    bool monotonic = true;
    for (uint32_t i = 0; i < MIAFX_BAND_COUNT; i++) {
        if (bands.end[i] <= bands.start[i]) monotonic = false;
        if (bands.end[i] > binCount) monotonic = false;
        if (i > 0 && (bands.start[i] < bands.start[i - 1] || bands.end[i] < bands.end[i - 1])) monotonic = false;
    }
    check(monotonic, "16 频段 bin 区间有效且单调不减", NULL);
    check(bands.start[0] >= 1u, "排除 DC bin", NULL);
    check(fabsf(bands.edges[MIAFX_BAND_COUNT] - 16000.0f) < 1.0f, "顶边为 16kHz（低于 Nyquist 时取 16k）", NULL);
    check(fabsf(bands.edges[0] - 20.0f) < 0.001f, "底边为 20Hz", NULL);

    /* 非法采样率必须被拒绝 */
    MIAFXBands bad;
    MIAFXBandsReset(&bad);
    check(!MIAFXBandsConfigure(&bad, 0.0f, binCount, binHz), "0Hz 采样率被拒绝", NULL);
    check(!MIAFXBandsConfigure(&bad, sampleRate, 0, binHz), "0 bin 被拒绝", NULL);

    float magnitude[MIAFX_FFT_BINS];
    uint8_t out[MIAFX_BAND_COUNT];

    /* 静音 → 低电平 */
    memset(magnitude, 0, sizeof(magnitude));
    MIAFXBandsAnalyze(&bands, magnitude, binCount, out);
    bool lowAll = true;
    for (uint32_t i = 0; i < MIAFX_BAND_COUNT; i++) if (out[i] > 8) lowAll = false;
    check(lowAll, "静音输入输出接近 0", NULL);

    /* 宽带强信号 → 多频段被点亮（attack 需要若干帧爬升） */
    for (uint32_t i = 0; i < MIAFX_FFT_BINS; i++) magnitude[i] = 0.5f;
    for (int frame = 0; frame < 60; frame++) MIAFXBandsAnalyze(&bands, magnitude, binCount, out);
    uint32_t lit = 0;
    for (uint32_t i = 0; i < MIAFX_BAND_COUNT; i++) if (out[i] > 40) lit++;
    char detail[96];
    snprintf(detail, sizeof(detail), "点亮频段 %u/16", lit);
    check(lit >= 12, "宽带强信号点亮多数频段", detail);

    /* release：信号撤走后应平滑回落而不是瞬间归零 */
    uint8_t before = out[4];
    memset(magnitude, 0, sizeof(magnitude));
    MIAFXBandsAnalyze(&bands, magnitude, binCount, out);
    check(out[4] > 0 && out[4] <= before, "单帧回落为平滑衰减", NULL);
    for (int frame = 0; frame < 200; frame++) MIAFXBandsAnalyze(&bands, magnitude, binCount, out);
    check(out[4] < before / 2 + 1, "持续静音后衰减到低电平", NULL);

    /* 未配置上下文必须是静音而不是崩溃 */
    MIAFXBands unconfigured;
    MIAFXBandsReset(&unconfigured);
    MIAFXBandsAnalyze(&unconfigured, magnitude, binCount, out);
    bool allZero = true;
    for (uint32_t i = 0; i < MIAFX_BAND_COUNT; i++) if (out[i] != 0) allZero = false;
    check(allZero, "未配置上下文输出静音", NULL);

    /* 量化与电平映射边界 */
    check(MIAFXBandsQuantize(0.0f) == 0, "量化 0 → 0", NULL);
    check(MIAFXBandsQuantize(1.0f) == 255, "量化 1 → 255", NULL);
    check(MIAFXBandsQuantize(-5.0f) == 0, "量化下界 clamp", NULL);
    check(MIAFXBandsQuantize(9.0f) == 255, "量化上界 clamp", NULL);
    check(MIAFXBandsNormalizeLevel(0.0f) <= 0.0f, "0 线性电平映射为 0", NULL);

    uint8_t peak = 0, rms = 0;
    MIAFXBandsAnalyzeLevels(&bands, 0.9f, 0.4f, &peak, &rms);
    check(peak > rms, "峰值电平高于 RMS 电平", NULL);
}

/* ----------------------------------------------------------------- Ring --- */

static void testRing(void) {
    printf("\n== 无锁环形缓冲 ==\n");
    MIAFXRing ring;
    MIAFXRingInit(&ring);
    check(MIAFXRingWritten(&ring) == 0, "初始化后已写入数为 0", NULL);

    float src[MIAFX_RING_MAX_WRITE];
    for (uint32_t i = 0; i < MIAFX_RING_MAX_WRITE; i++) src[i] = (float)i;

    uint32_t written = MIAFXRingWrite(&ring, src, MIAFX_RING_MAX_WRITE);
    check(written == MIAFX_RING_MAX_WRITE, "写入 512 样本", NULL);
    check(MIAFXRingWritten(&ring) == MIAFX_RING_MAX_WRITE, "已写入计数一致", NULL);

    float out[MIAFX_RING_MAX_WRITE];
    uint32_t read = MIAFXRingReadLatest(&ring, out, MIAFX_RING_MAX_WRITE);
    check(read == MIAFX_RING_MAX_WRITE, "读取 512 样本", NULL);
    bool identical = true;
    for (uint32_t i = 0; i < MIAFX_RING_MAX_WRITE; i++) if (out[i] != src[i]) identical = false;
    check(identical, "读回数据与写入一致（无生产者竞争）", NULL);

    /* 单次写入上限：超量必须被 clamp，绝不越界 */
    float big[2048];
    for (uint32_t i = 0; i < 2048; i++) big[i] = 1.0f;
    uint32_t clamped = MIAFXRingWrite(&ring, big, 2048);
    check(clamped <= MIAFX_RING_MAX_WRITE, "单次写入被 clamp 到 <=512", NULL);

    /* 长时间写入：环形回绕不得破坏计数与数据 */
    MIAFXRing ring2;
    MIAFXRingInit(&ring2);
    uint32_t total = 0;
    for (int round = 0; round < 40; round++) {
        for (uint32_t i = 0; i < MIAFX_RING_MAX_WRITE; i++) src[i] = (float)(round * 1000 + i);
        total += MIAFXRingWrite(&ring2, src, MIAFX_RING_MAX_WRITE);
    }
    check(total == 40u * MIAFX_RING_MAX_WRITE, "多圈写入总数正确", NULL);
    check(MIAFXRingWritten(&ring2) == total, "回绕后已写入总数正确", NULL);

    float latest[MIAFX_RING_MAX_WRITE];
    uint32_t got = MIAFXRingReadLatest(&ring2, latest, MIAFX_RING_MAX_WRITE);
    bool latestOK = true;
    if (got == MIAFX_RING_MAX_WRITE) {
        for (uint32_t i = 0; i < MIAFX_RING_MAX_WRITE; i++) {
            float expected = (float)(39u * 1000u + i);
            if (fabsf(latest[i] - expected) > 0.001f) latestOK = false;
        }
    } else {
        latestOK = false;
    }
    check(latestOK, "读取到最后一圈最新样本", NULL);

    /* 读取数量超过容量时必须安全失败而不是越界 */
    float huge[MIAFX_RING_CAPACITY + 64];
    check(MIAFXRingReadLatest(&ring2, huge, MIAFX_RING_CAPACITY + 64) != MIAFX_RING_CAPACITY + 64,
          "超容量读取被拒绝", NULL);

    /* 单样本写入路径 */
    MIAFXRing ring3;
    MIAFXRingInit(&ring3);
    for (uint32_t i = 0; i < 100; i++) MIAFXRingWriteOne(&ring3, (float)i);
    check(MIAFXRingWritten(&ring3) == 100, "单样本写入计数正确", NULL);
    float one[4];
    check(MIAFXRingReadLatest(&ring3, one, 4) == 4, "单样本缓冲可读取", NULL);
}

/* ------------------------------------------------------------------ IPC --- */

static void testIPC(void) {
    printf("\n== IPC 打包 ==\n");
    MIAFXSpectrumFrame frame;
    memset(&frame, 0, sizeof(frame));
    for (uint32_t i = 0; i < 16; i++) frame.bands[i] = (uint8_t)(i * 16u);
    frame.peak = 200;
    frame.rms = 77;
    frame.flags = 0xA5;
    frame.tier = 3;
    frame.sequence = 65535;
    frame.sampleRate100 = 480;
    frame.timestamp32 = 0xDEADBEEFu;

    MIAFXIPCWords words;
    MIAFXIPCPack(&frame, &words);

    MIAFXSpectrumFrame decoded;
    memset(&decoded, 0, sizeof(decoded));
    check(MIAFXIPCUnpack(&words, &decoded), "解包成功（magic/version 校验通过）", NULL);

    bool bandsOK = true;
    for (uint32_t i = 0; i < 16; i++) if (decoded.bands[i] != frame.bands[i]) bandsOK = false;
    check(bandsOK, "16 个频段往返一致", NULL);
    check(decoded.peak == 200 && decoded.rms == 77, "peak/rms 往返一致", NULL);
    check(decoded.flags == 0xA5 && decoded.tier == 3, "flags/tier 往返一致", NULL);
    check(decoded.sequence == 65535, "sequence 往返一致", NULL);
    check(decoded.sampleRate100 == 480, "sampleRate100 往返一致", NULL);
    check(decoded.timestamp32 == 0xDEADBEEFu, "timestamp32 往返一致", NULL);

    /* 损坏的 magic 必须被拒绝 */
    MIAFXIPCWords corrupt = words;
    corrupt.metadata &= ~0xffULL;
    check(!MIAFXIPCUnpack(&corrupt, &decoded), "magic 错误被拒绝", NULL);

    MIAFXIPCWords badVersion = words;
    badVersion.metadata = (badVersion.metadata & ~0xff00ULL) | ((uint64_t)(MIAFX_IPC_VERSION + 1u) << 8u);
    check(!MIAFXIPCUnpack(&badVersion, &decoded), "版本不匹配被拒绝", NULL);

    check(!MIAFXIPCUnpack(NULL, &decoded), "空 words 被拒绝", NULL);
    check(!MIAFXIPCUnpack(&words, NULL), "空 frame 被拒绝", NULL);
}

/* -------------------------------------------------------------- Resample -- */

static void testResample(void) {
    printf("\n== 频谱插值重采样 ==\n");
    uint8_t input[16];
    for (uint32_t i = 0; i < 16; i++) input[i] = (uint8_t)(i * 17u);

    float history[64];
    float output[64];

    size_t counts[4] = { 8, 16, 32, 64 };
    for (int c = 0; c < 4; c++) {
        size_t count = counts[c];
        memset(history, 0, sizeof(history));
        /* 预热若干帧让平滑收敛 */
        for (int frame = 0; frame < 30; frame++) {
            MIAFXSpectrumResample(input, output, count, 1.0f, 0.5f, history);
        }
        bool finite = true, inRange = true;
        for (size_t i = 0; i < count; i++) {
            if (!isfinite(output[i])) finite = false;
            if (output[i] < -0.001f || output[i] > 1.5f) inRange = false;
        }
        char detail[96];
        snprintf(detail, sizeof(detail), "条数 %zu", count);
        bool ok = finite && inRange;
        check(ok, "插值输出有限且在合理范围内", detail);
    }

    /* 单调输入插值后整体趋势应单调不减 */
    memset(history, 0, sizeof(history));
    for (int frame = 0; frame < 60; frame++) MIAFXSpectrumResample(input, output, 32, 1.0f, 0.35f, history);
    check(output[31] > output[0], "低频到高频电平递增", NULL);

    /* 灵敏度：更高灵敏度应得到不低于原来的响应 */
    float low[32], high[32];
    float h1[64], h2[64];
    memset(h1, 0, sizeof(h1));
    memset(h2, 0, sizeof(h2));
    for (int frame = 0; frame < 30; frame++) {
        MIAFXSpectrumResample(input, low, 32, 1.0f, 0.5f, h1);
        MIAFXSpectrumResample(input, high, 32, 2.0f, 0.5f, h2);
    }
    check(high[16] >= low[16] - 0.001f, "灵敏度提升不降低响应", NULL);

    /* 空指针/零长度防御 */
    MIAFXSpectrumResample(input, NULL, 0, 1.0f, 0.5f, history);
    check(true, "零长度重采样安全返回", NULL);
}

int main(void) {
    printf("MIAFX 离线单元测试\n");
    testFFT();
    testBands();
    testRing();
    testIPC();
    testResample();
    printf("\n----\n断言 %d 条，失败 %d 条\n", gChecks, gFailures);
    return gFailures == 0 ? 0 : 1;
}
