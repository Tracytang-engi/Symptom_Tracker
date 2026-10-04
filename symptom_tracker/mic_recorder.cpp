/**
 * mic_recorder.cpp — INMP441 麦克风录音模块（实现）
 *
 * 架构说明：
 *   录音使用独立的 FreeRTOS 任务（运行在 Core 0），
 *   主循环在 Core 1 继续正常采样 FSR / 处理 BLE。
 *   两个核心通过 volatile 标志位通信，不需要加锁。
 *
 * WAV 文件格式（标准 PCM）：
 *   [RIFF 头 44 字节] + [16-bit PCM 样本数据]
 *   写入时先占位，录音结束后再回填实际数据大小。
 */

#include "mic_recorder.h"
#include "config.h"
#include <driver/i2s_std.h>  // ESP-IDF 5 / Arduino 3 新版 I2S（勿用 driver/i2s.h，会与 analogRead 的 ADC 冲突）
#include <SPIFFS.h>           // SPIFFS = SPI Flash File System，ESP32 内置闪存文件系统
#include <FS.h>               // 通用文件系统接口

// ─── WAV 文件头结构 ────────────────────────────────────────────
// WAV 格式固定为 44 字节头 + PCM 数据
// __attribute__((packed)) = 告诉编译器不要在字段间添加对齐填充
struct WavHeader {
    // RIFF 块
    char     riff[4]       = {'R','I','F','F'};  // 固定标识
    uint32_t fileSize      = 0;                  // 总文件大小 - 8（录完后填）
    char     wave[4]       = {'W','A','V','E'};  // 格式标识

    // fmt 子块（描述音频格式）
    char     fmt[4]        = {'f','m','t',' '};
    uint32_t fmtSize       = 16;        // PCM 格式固定 16 字节
    uint16_t audioFormat   = 1;         // 1 = PCM 线性编码（无压缩）
    uint16_t numChannels   = 1;         // 1 = 单声道
    uint32_t sampleRate    = MIC_SAMPLE_RATE;
    uint32_t byteRate      = MIC_SAMPLE_RATE * 1 * 2;  // 采样率 × 声道数 × 每样本字节数
    uint16_t blockAlign    = 2;         // 声道数 × 每样本字节数
    uint16_t bitsPerSample = 16;        // 16-bit 深度

    // data 子块
    char     data[4]       = {'d','a','t','a'};
    uint32_t dataSize      = 0;         // PCM 数据字节数（录完后填）
} __attribute__((packed));

// ─── 模块内部状态 ──────────────────────────────────────────────
static volatile bool s_recording    = false;
static volatile bool s_shouldStop   = false;
static TaskHandle_t  s_taskHandle   = nullptr;
static char          s_filePath[48] = "";
static uint32_t      s_startMs      = 0;
static uint32_t      s_durationMs   = 0;
static size_t        s_fileSize     = 0;
static bool          s_lastOk       = false;  // 最近一次是否写出有效文件
static bool          s_spiffsOk     = false;   // SPIFFS 是否可用；false 时禁用录音但不崩溃
static i2s_chan_handle_t s_rxChan   = nullptr; // 新版 I2S 接收通道句柄

// DMA 读取缓冲区（每次从 I2S 读 MIC_DMA_BUF_LEN 个 32-bit 样本）
// 放在全局而非栈上，避免任务栈溢出
static int32_t  s_i2sBuf[MIC_DMA_BUF_LEN];    // int32_t = INMP441 原始 32-bit 输出
static int16_t  s_pcmBuf[MIC_DMA_BUF_LEN];    // int16_t = 转换后的 16-bit PCM

// 多段累计：同一疼痛事件下多份 /rec_<id>_N.wav，累计时长 ≤ MIC_MAX_DURATION_S
static char     s_activeEventId[24] = "";
static uint8_t  s_segIndex          = 0;
static uint32_t s_usedMs            = 0;   // 本事件已用累计毫秒
static uint32_t s_maxThisSegMs      = MIC_MAX_DURATION_S * 1000UL;

// ─── 内部：初始化 I2S（STD / Philips，与 INMP441 兼容）────────────────

static void initI2S() {
    // 创建 RX 通道（只用接收，不用发送）
    i2s_chan_config_t chanCfg = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_1, I2S_ROLE_MASTER);
    chanCfg.dma_desc_num = MIC_DMA_BUF_COUNT;
    chanCfg.dma_frame_num = MIC_DMA_BUF_LEN;
    esp_err_t err = i2s_new_channel(&chanCfg, NULL, &s_rxChan);
    if (err != ESP_OK) {
        Serial.printf("[MIC] i2s_new_channel 失败: %s\n", esp_err_to_name(err));
        s_rxChan = nullptr;
        return;
    }

    i2s_std_config_t stdCfg = {
        .clk_cfg  = I2S_STD_CLK_DEFAULT_CONFIG(MIC_SAMPLE_RATE),
        // 32-bit 槽位：INMP441 有效 24-bit 在高位；声道见 MIC_I2S_SLOT_RIGHT
        .slot_cfg = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_32BIT, I2S_SLOT_MODE_MONO),
        .gpio_cfg = {
            .mclk = I2S_GPIO_UNUSED,
            .bclk = (gpio_num_t)MIC_SCK_PIN,
            .ws   = (gpio_num_t)MIC_WS_PIN,
            .dout = I2S_GPIO_UNUSED,
            .din  = (gpio_num_t)MIC_SD_PIN,
            .invert_flags = {
                .mclk_inv = false,
                .bclk_inv = false,
                .ws_inv   = false,
            },
        },
    };
#if MIC_I2S_SLOT_RIGHT
    stdCfg.slot_cfg.slot_mask = I2S_STD_SLOT_RIGHT;
#else
    stdCfg.slot_cfg.slot_mask = I2S_STD_SLOT_LEFT;
#endif

    err = i2s_channel_init_std_mode(s_rxChan, &stdCfg);
    if (err != ESP_OK) {
        Serial.printf("[MIC] i2s_channel_init_std_mode 失败: %s\n", esp_err_to_name(err));
        i2s_del_channel(s_rxChan);
        s_rxChan = nullptr;
        return;
    }

    err = i2s_channel_enable(s_rxChan);
    if (err != ESP_OK) {
        Serial.printf("[MIC] i2s_channel_enable 失败: %s\n", esp_err_to_name(err));
        i2s_del_channel(s_rxChan);
        s_rxChan = nullptr;
        return;
    }
}

// ─── 内部：WAV 头写入 / 回填 ──────────────────────────────────

// 在文件开头写占位头（dataSize 和 fileSize 先填 0，录完后回填）
static void writeWavHeader(File& f) {
    WavHeader hdr;
    f.write((const uint8_t*)&hdr, sizeof(hdr));  // 把结构体按字节写入文件
}

// 录音结束后，回到文件头填写实际大小
static void finalizeWavHeader(File& f, uint32_t dataBytes) {
    uint32_t fileSize = 36 + dataBytes;  // RIFF 块大小 = "WAVE" + fmt块 + data块

    f.seek(4);   // 定位到 fileSize 字段（偏移 4 字节）
    f.write((const uint8_t*)&fileSize, 4);

    f.seek(40);  // 定位到 dataSize 字段（偏移 40 字节）
    f.write((const uint8_t*)&dataBytes, 4);
}

// ─── 内部：FreeRTOS 录音任务 ──────────────────────────────────
/**
 * 运行在 Core 0，持续从 I2S 读取样本并写入 WAV 文件。
 * 主循环（Core 1）通过 s_shouldStop 信号通知停止。
 * void* param = 任务启动时传入的参数（这里不用，设为 nullptr）
 */
static void recordingTask(void* param) {
    if (s_rxChan == nullptr) {
        Serial.println("[MIC] I2S 未初始化，录音中止");
        s_recording = false;
        vTaskDelete(nullptr);
        return;
    }

    File f = SPIFFS.open(s_filePath, FILE_WRITE);  // 打开文件用于写入
    if (!f) {
        Serial.println("[MIC] 文件创建失败，录音中止（可能空间不足）");
        s_durationMs = 0;
        s_fileSize   = 0;
        s_lastOk     = false;
        s_recording  = false;
        vTaskDelete(nullptr);  // vTaskDelete(nullptr) = 删除当前任务自身
        return;
    }

    writeWavHeader(f);   // 先写占位头

    uint32_t dataBytes     = 0;
    // 本段上限 = 剩余累计预算（字节）
    uint32_t maxDataBytes  = (uint32_t)((uint64_t)MIC_SAMPLE_RATE * 2UL * s_maxThisSegMs / 1000UL);
    if (maxDataBytes < MIC_SAMPLE_RATE) maxDataBytes = MIC_SAMPLE_RATE;  // 至少约 0.5s
    size_t   bytesRead     = 0;

    Serial.printf("[MIC] 开始录音 → %s（本段最长 %.1fs，累计已用 %.1fs）\n",
                  s_filePath,
                  s_maxThisSegMs / 1000.0f,
                  s_usedMs / 1000.0f);

    // ── 录音主循环 ────────────────────────────────────────────
    while (!s_shouldStop && dataBytes < maxDataBytes) {

        // 新版 API：从 RX 通道读取一批 32-bit 原始样本
        esp_err_t err = i2s_channel_read(
            s_rxChan,
            (void*)s_i2sBuf,
            sizeof(s_i2sBuf),
            &bytesRead,
            portMAX_DELAY
        );

        if (err != ESP_OK || bytesRead == 0) continue;

        int samplesRead = bytesRead / sizeof(int32_t);  // 计算实际样本数

        // 32-bit → 16-bit：INMP441 有效数据在高位，取高 16 位
        for (int i = 0; i < samplesRead; i++) {
            s_pcmBuf[i] = (int16_t)(s_i2sBuf[i] >> 16);
        }

        // 把 16-bit PCM 数据写入 WAV 文件
        size_t written = f.write((const uint8_t*)s_pcmBuf, samplesRead * sizeof(int16_t));
        dataBytes += written;

        // 每 5 秒打印一次进度
        static uint32_t lastLog = 0;
        if (millis() - lastLog > 5000) {
            lastLog = millis();
            Serial.printf("[MIC] 录音中... %.1f 秒 / 本段上限 %.1fs\n",
                          (float)dataBytes / (MIC_SAMPLE_RATE * 2),
                          s_maxThisSegMs / 1000.0f);
        }
    }

    // ── 录音结束：回填 WAV 头，关闭文件 ─────────────────────────
    finalizeWavHeader(f, dataBytes);
    s_fileSize    = f.size();   // 记录文件大小（含 44 字节头）
    s_durationMs  = millis() - s_startMs;
    f.close();

    // 累计本事件已用时长，并推进段号（下次同事件 → _1, _2…）
    if (s_activeEventId[0] != '\0') {
        s_usedMs += s_durationMs;
        if (s_segIndex < 255) s_segIndex++;
        Serial.printf("[MIC] 事件 %s 累计 %.1fs / %ds\n",
                      s_activeEventId, s_usedMs / 1000.0f, MIC_MAX_DURATION_S);
    }

    Serial.printf("[MIC] 录音完成：%s  时长=%.1fs  大小=%uKB\n",
                  s_filePath,
                  s_durationMs / 1000.0f,
                  s_fileSize / 1024);

    // 至少要有 WAV 头 + 一点 PCM 才算有效
    s_lastOk      = (s_fileSize > 44 && s_durationMs > 0);
    s_recording   = false;
    s_taskHandle  = nullptr;
    vTaskDelete(nullptr);   // 任务自我删除，释放内存
}

// ─── 公开接口实现 ──────────────────────────────────────────────

bool MIC_init() {
    // 擦除 flash 并选用 Default 4MB with spiffs 后，此处首次会自动格式化空分区。
    // 失败时只禁用录音，不崩溃，FSR/马达/BLE/SOS 仍可运行。
    s_spiffsOk = SPIFFS.begin(true);

    if (s_spiffsOk) {
        Serial.printf("[MIC] SPIFFS 可用: %u KB / %u KB\n",
                      (SPIFFS.totalBytes() - SPIFFS.usedBytes()) / 1024,
                      SPIFFS.totalBytes() / 1024);
        // 列出已有录音，方便确认「未上传旧文件」占了多少
        File root = SPIFFS.open("/");
        File f    = root.openNextFile();
        int  n    = 0;
        while (f) {
            if (!f.isDirectory()) {
                Serial.printf("[MIC]   文件: %s  (%u KB)\n",
                              f.name(), (unsigned)(f.size() / 1024));
                n++;
            }
            f = root.openNextFile();
        }
        if (n == 0) Serial.println("[MIC]   （无已存录音）");
        else Serial.printf("[MIC]   共 %d 个文件。下载成功后才会删除；"
                           "满了请 Clear device storage。\n", n);
        if (MIC_freeBytes() < (size_t)MIC_SAMPLE_RATE * 2UL * 5UL) {
            Serial.println("[MIC] ⚠ 空闲不足约 5 秒录音，新录音可能被拒绝或很短。");
        }
    } else {
        Serial.println("[MIC] ⚠ SPIFFS 不可用，录音功能已禁用。");
        Serial.println("[MIC]   确认 Partition Scheme = Default 4MB with spiffs，并已 erase_flash。");
    }

    // 模块 L/R 仍接在 D32。拉低后等效接地，I2S 取左声道。
    pinMode(MIC_LR_PIN, OUTPUT);
    digitalWrite(MIC_LR_PIN, LOW);

    initI2S();   // I2S 麦克风硬件照常初始化（不依赖 SPIFFS）
    Serial.println("[MIC] 麦克风初始化完成");
    return s_spiffsOk;
}

bool MIC_startRecording(const char* eventId) {
    if (!s_spiffsOk) {
        Serial.println("[MIC] SPIFFS 不可用，无法录音");
        return false;
    }
    if (s_rxChan == nullptr) {
        Serial.println("[MIC] I2S 不可用，无法录音");
        return false;
    }
    if (s_recording) {
        Serial.println("[MIC] 已在录音中，忽略");
        return false;
    }

    // 先算本段预算 / 文件名；累计满 30s 则拒绝（与 SPIFFS 空间无关）
    if (eventId && eventId[0] != '\0') {
        if (strcmp(eventId, s_activeEventId) != 0) {
            strncpy(s_activeEventId, eventId, sizeof(s_activeEventId) - 1);
            s_activeEventId[sizeof(s_activeEventId) - 1] = '\0';
            s_segIndex = 0;
            s_usedMs   = 0;
        }
        const uint32_t budgetMs = (uint32_t)MIC_MAX_DURATION_S * 1000UL;
        if (s_usedMs >= budgetMs) {
            Serial.printf("[MIC] 事件 %s 累计已满 %ds，拒绝再录\n",
                          s_activeEventId, MIC_MAX_DURATION_S);
            return false;
        }
        s_maxThisSegMs = budgetMs - s_usedMs;
        snprintf(s_filePath, sizeof(s_filePath), "/rec_%s_%u.wav",
                 eventId, (unsigned)s_segIndex);
    } else {
        s_activeEventId[0] = '\0';
        s_maxThisSegMs = (uint32_t)MIC_MAX_DURATION_S * 1000UL;
        snprintf(s_filePath, sizeof(s_filePath), "/rec_%lu.wav", millis());
    }

    // 按剩余空间缩短本段上限；绝不自动删未上传文件。
    // 16kHz×16bit×1ch ≈ 32000 字节/秒。
    const size_t bytesPerSec = (size_t)MIC_SAMPLE_RATE * 2UL;
    const size_t margin      = 8192;
    const size_t freeB       = MIC_freeBytes();
    if (freeB < bytesPerSec + margin + 44) {
        Serial.printf("[MIC] 空间不足，拒绝新录音（剩余 %uKB，至少需要约 %uKB）。"
                      "请先下载已有录音，或 Settings→Clear device storage。\n",
                      (unsigned)(freeB / 1024),
                      (unsigned)((bytesPerSec + margin) / 1024));
        return false;
    }
    {
        size_t maxSec = (freeB - margin) / bytesPerSec;
        if (maxSec < 1) maxSec = 1;
        if (maxSec > MIC_MAX_DURATION_S) maxSec = MIC_MAX_DURATION_S;
        uint32_t spaceCapMs = (uint32_t)maxSec * 1000UL;
        if (spaceCapMs < s_maxThisSegMs) {
            Serial.printf("[MIC] 剩余空间约 %uKB，本段最长缩短为 %lu s（不删旧文件）\n",
                          (unsigned)(freeB / 1024), (unsigned long)maxSec);
            s_maxThisSegMs = spaceCapMs;
        }
    }

    s_shouldStop = false;
    s_startMs    = millis();
    s_durationMs = 0;
    s_fileSize   = 0;
    s_lastOk     = false;
    s_recording  = true;

    BaseType_t result = xTaskCreatePinnedToCore(
        recordingTask,
        "MicRecord",
        8192,
        nullptr,
        1,
        &s_taskHandle,
        0
    );

    if (result != pdPASS) {
        Serial.println("[MIC] 任务创建失败");
        s_recording = false;
        return false;
    }

    return true;
}

void MIC_stopRecording() {
    if (!s_recording) return;
    s_shouldStop = true;  // 通知录音任务退出循环

    // 等待任务自然结束（最多等 3 秒）
    uint32_t timeout = millis() + 3000;
    while (s_recording && millis() < timeout) {
        delay(50);  // 让出 CPU，等录音任务处理完最后一批数据
    }

    if (s_recording) {
        // 超时强制结束（通常不应该发生）
        if (s_taskHandle) vTaskDelete(s_taskHandle);
        s_recording  = false;
        s_taskHandle = nullptr;
        Serial.println("[MIC] 录音任务强制终止");
    }
}

bool        MIC_isRecording()       { return s_recording; }
const char* MIC_getLastFilePath()   { return s_filePath; }
uint32_t    MIC_getLastDurationMs() { return s_durationMs; }
size_t      MIC_getLastFileSize()   { return s_fileSize; }
bool        MIC_lastRecordingOk()   { return s_lastOk; }

size_t MIC_freeBytes() {
    if (!s_spiffsOk) return 0;
    return SPIFFS.totalBytes() - SPIFFS.usedBytes();
}

static bool isRecFileName(const char* name) {
    if (!name) return false;
    // SPIFFS 的 name() 有时带前导 '/'，有时不带
    const char* base = name;
    if (base[0] == '/') base++;
    return strncmp(base, "rec_", 4) == 0;
}

bool MIC_ensureSpace(size_t needBytes) {
    if (!s_spiffsOk) return false;
    // 只检查，不删除未上传文件
    return MIC_freeBytes() >= needBytes;
}

int MIC_clearAllRecordings() {
    if (!s_spiffsOk) return 0;
    int n = 0;
    for (;;) {
        File root = SPIFFS.open("/");
        if (!root) break;
        File f = root.openNextFile();
        bool removedOne = false;
        while (f) {
            if (!f.isDirectory() && isRecFileName(f.name())) {
                char path[64];
                const char* name = f.name();
                if (name[0] == '/') {
                    strncpy(path, name, sizeof(path) - 1);
                } else {
                    snprintf(path, sizeof(path), "/%s", name);
                }
                path[sizeof(path) - 1] = '\0';
                f.close();
                root.close();
                if (SPIFFS.remove(path)) {
                    Serial.printf("[MIC] 清空: %s\n", path);
                    n++;
                    removedOne = true;
                }
                break;
            }
            f = root.openNextFile();
        }
        if (!removedOne) {
            root.close();
            break;
        }
    }
    Serial.printf("[MIC] 共清空 %d 个录音，剩余 %uKB\n",
                  n, (unsigned)(MIC_freeBytes() / 1024));
    return n;
}

bool MIC_deleteFile(const char* path) {
    if (SPIFFS.remove(path)) {  // .remove() = 删除文件
        Serial.printf("[MIC] 已删除: %s\n", path);
        return true;
    }
    Serial.printf("[MIC] 删除失败: %s\n", path);
    return false;
}

void MIC_listFiles(char* outBuf, size_t bufSize) {
    outBuf[0] = '\0';  // 清空输出缓冲区
    // SPIFFS.open("/", "r") = 打开根目录
    File root = SPIFFS.open("/");
    File f    = root.openNextFile();  // 遍历目录中的文件

    while (f && strlen(outBuf) < bufSize - 32) {  // strlen = 字符串长度
        if (!f.isDirectory()) {                    // isDirectory() = 是否为子目录
            strncat(outBuf, f.name(), bufSize - strlen(outBuf) - 2);  // strncat = 安全字符串拼接
            strncat(outBuf, ",", 2);
        }
        f = root.openNextFile();
    }
}
