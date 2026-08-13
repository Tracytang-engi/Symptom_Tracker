/**
 * symptom_tracker_mic_test — 独立短录音测试（无 BLE / FSR）
 *
 * 数据读取方式与主工程 mic_recorder.cpp 保持一致：
 *   I2S_NUM_1 + STD Philips + 32bit MONO + SLOT（默认 RIGHT，与主工程一致）
 *   样本转换：int16 = (int32 >> 16)
 *   采样率 8000，DMA 8×512
 *
 * 接线（与主工程一致）：
 *   INMP441 VDD → 3.3V
 *   INMP441 GND → GND
 *   INMP441 SCK → GPIO14
 *   INMP441 WS  → GPIO15
 *   INMP441 SD  → GPIO32
 *   INMP441 L/R → GND（左声道）
 *
 * Arduino：ESP32 Dev Module，Partition = Default 4MB with spiffs，串口 115200
 *
 * 命令：H / V / D / R / R10 / S / LIST / C / LEFT / RIGHT
 *   LEFT/RIGHT 切换 I2S 声道（其余读法与主工程相同）
 *   L/R 接 GND 时若 D 全 0，多半要发 RIGHT
 */

#include <driver/i2s_std.h>
#include <SPIFFS.h>
#include <FS.h>

// 与 config.h / mic_recorder.cpp 一致
#define MIC_SCK_PIN         14
#define MIC_WS_PIN          15
#define MIC_SD_PIN          32
#define MIC_SAMPLE_RATE     8000
#define MIC_DMA_BUF_COUNT   8
#define MIC_DMA_BUF_LEN     512

#define DEFAULT_SECS  5
#define MAX_SECS      30

// 与主工程一致：默认 LEFT；可用 LEFT/RIGHT 命令切换
static i2s_std_slot_mask_t s_slotMask = I2S_STD_SLOT_LEFT;

struct WavHeader {
  char     riff[4] = {'R','I','F','F'};
  uint32_t fileSize = 0;
  char     wave[4] = {'W','A','V','E'};
  char     fmt[4]  = {'f','m','t',' '};
  uint32_t fmtSize = 16;
  uint16_t audioFormat = 1;
  uint16_t numChannels = 1;
  uint32_t sampleRate = MIC_SAMPLE_RATE;
  uint32_t byteRate = MIC_SAMPLE_RATE * 2;
  uint16_t blockAlign = 2;
  uint16_t bitsPerSample = 16;
  char     data[4] = {'d','a','t','a'};
  uint32_t dataSize = 0;
} __attribute__((packed));

static i2s_chan_handle_t s_rxChan = nullptr;
static int32_t s_i2sBuf[MIC_DMA_BUF_LEN];
static int16_t s_pcmBuf[MIC_DMA_BUF_LEN];

static volatile bool recording = false;
static volatile bool shouldStop = false;
static TaskHandle_t recTask = nullptr;
static char filePath[40] = "";
static uint32_t recMaxMs = DEFAULT_SECS * 1000UL;
static bool meterMode = false;

static void printHelp() {
  Serial.println();
  Serial.println("=== MIC 录音测试（读法=主工程）===");
  Serial.println("H      帮助");
  Serial.println("V      实时音量（不写盘）");
  Serial.println("D      打印一批原始样本（诊断）");
  Serial.println("LEFT   声道=LEFT（主工程默认）");
  Serial.println("RIGHT  声道=RIGHT（L/R→GND 时常需要）");
  Serial.println("R      录 5 秒");
  Serial.println("R10    录 N 秒（1~30）");
  Serial.println("S      停止录音");
  Serial.println("LIST   列文件");
  Serial.println("C      清空 test_*.wav");
  Serial.println();
}

static void deinitI2S() {
  if (!s_rxChan) return;
  i2s_channel_disable(s_rxChan);
  i2s_del_channel(s_rxChan);
  s_rxChan = nullptr;
}

/** 与 mic_recorder.cpp::initI2S() 相同，仅 slot_mask 可切换 */
static bool initI2S() {
  deinitI2S();

  i2s_chan_config_t chanCfg = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_1, I2S_ROLE_MASTER);
  chanCfg.dma_desc_num = MIC_DMA_BUF_COUNT;
  chanCfg.dma_frame_num = MIC_DMA_BUF_LEN;
  esp_err_t err = i2s_new_channel(&chanCfg, NULL, &s_rxChan);
  if (err != ESP_OK) {
    Serial.printf("[MIC] i2s_new_channel 失败: %s\n", esp_err_to_name(err));
    s_rxChan = nullptr;
    return false;
  }

  i2s_std_config_t stdCfg = {
    .clk_cfg  = I2S_STD_CLK_DEFAULT_CONFIG(MIC_SAMPLE_RATE),
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
  stdCfg.slot_cfg.slot_mask = s_slotMask;

  err = i2s_channel_init_std_mode(s_rxChan, &stdCfg);
  if (err != ESP_OK) {
    Serial.printf("[MIC] i2s_channel_init_std_mode 失败: %s\n", esp_err_to_name(err));
    i2s_del_channel(s_rxChan);
    s_rxChan = nullptr;
    return false;
  }

  err = i2s_channel_enable(s_rxChan);
  if (err != ESP_OK) {
    Serial.printf("[MIC] i2s_channel_enable 失败: %s\n", esp_err_to_name(err));
    i2s_del_channel(s_rxChan);
    s_rxChan = nullptr;
    return false;
  }

  Serial.printf("[MIC] I2S OK  slot=%s  pins SCK=%d WS=%d SD=%d  %dHz\n",
                (s_slotMask == I2S_STD_SLOT_RIGHT) ? "RIGHT" : "LEFT",
                MIC_SCK_PIN, MIC_WS_PIN, MIC_SD_PIN, MIC_SAMPLE_RATE);
  return true;
}

/** 与主工程相同：32-bit → 16-bit，取高 16 位 */
static inline int16_t sampleToPcm16(int32_t raw) {
  return (int16_t)(raw >> 16);
}

static void finalizeWav(File& f, uint32_t dataBytes) {
  uint32_t fileSize = 36 + dataBytes;
  f.seek(4);
  f.write((const uint8_t*)&fileSize, 4);
  f.seek(40);
  f.write((const uint8_t*)&dataBytes, 4);
}

static void recordingTask(void*) {
  File f = SPIFFS.open(filePath, FILE_WRITE);
  if (!f) {
    Serial.println("[MIC] 打开文件失败");
    recording = false;
    vTaskDelete(nullptr);
    return;
  }

  WavHeader hdr;
  f.write((const uint8_t*)&hdr, sizeof(hdr));

  uint32_t dataBytes = 0;
  uint32_t maxBytes = (uint32_t)((uint64_t)MIC_SAMPLE_RATE * 2UL * recMaxMs / 1000UL);
  uint32_t t0 = millis();
  size_t bytesRead = 0;

  Serial.printf("[MIC] 开始 → %s  最长 %.1fs\n", filePath, recMaxMs / 1000.0f);

  while (!shouldStop && dataBytes < maxBytes) {
    esp_err_t err = i2s_channel_read(
      s_rxChan, (void*)s_i2sBuf, sizeof(s_i2sBuf), &bytesRead, portMAX_DELAY);
    if (err != ESP_OK || bytesRead == 0) continue;

    int samplesRead = bytesRead / sizeof(int32_t);
    for (int i = 0; i < samplesRead; i++) {
      s_pcmBuf[i] = sampleToPcm16(s_i2sBuf[i]);
    }
    dataBytes += f.write((const uint8_t*)s_pcmBuf, samplesRead * sizeof(int16_t));
  }

  finalizeWav(f, dataBytes);
  size_t sz = f.size();
  f.close();

  float sec = (millis() - t0) / 1000.0f;
  bool ok = (sz > 44 && dataBytes > 0);
  Serial.printf("[MIC] 结束 ok=%d  时长≈%.1fs  数据=%u B  文件=%u B  路径=%s\n",
                ok ? 1 : 0, sec, dataBytes, (unsigned)sz, filePath);

  recording = false;
  recTask = nullptr;
  vTaskDelete(nullptr);
}

static void listFiles() {
  File root = SPIFFS.open("/");
  File f = root.openNextFile();
  int n = 0;
  while (f) {
    if (!f.isDirectory()) {
      Serial.printf("  %s  %u B\n", f.name(), (unsigned)f.size());
      n++;
    }
    f = root.openNextFile();
  }
  if (n == 0) Serial.println("  （空）");
  Serial.printf("剩余 %u KB / 共 %u KB\n",
                (SPIFFS.totalBytes() - SPIFFS.usedBytes()) / 1024,
                SPIFFS.totalBytes() / 1024);
}

static void clearTests() {
  for (;;) {
    File root = SPIFFS.open("/");
    if (!root) break;
    File f = root.openNextFile();
    bool removed = false;
    while (f) {
      const char* name = f.name();
      const char* base = (name[0] == '/') ? name + 1 : name;
      if (!f.isDirectory() && strncmp(base, "test_", 5) == 0) {
        char path[48];
        if (name[0] == '/') strncpy(path, name, sizeof(path) - 1);
        else snprintf(path, sizeof(path), "/%s", name);
        path[sizeof(path) - 1] = '\0';
        f.close();
        root.close();
        if (SPIFFS.remove(path)) {
          Serial.printf("已删 %s\n", path);
          removed = true;
        }
        break;
      }
      f = root.openNextFile();
    }
    if (!removed) {
      root.close();
      break;
    }
  }
}

static bool startRec(uint32_t secs) {
  if (recording) {
    Serial.println("已在录音，先发 S");
    return false;
  }
  if (!s_rxChan) {
    Serial.println("I2S 不可用");
    return false;
  }
  if (!SPIFFS.begin(false) && !SPIFFS.begin(true)) {
    Serial.println("SPIFFS 不可用");
    return false;
  }

  if (secs < 1) secs = 1;
  if (secs > MAX_SECS) secs = MAX_SECS;
  recMaxMs = secs * 1000UL;
  snprintf(filePath, sizeof(filePath), "/test_%lu.wav", millis());
  shouldStop = false;
  recording = true;
  meterMode = false;

  if (xTaskCreatePinnedToCore(recordingTask, "MicTest", 8192, nullptr, 1, &recTask, 0) != pdPASS) {
    recording = false;
    Serial.println("任务创建失败");
    return false;
  }
  return true;
}

static void stopRec() {
  if (!recording) {
    Serial.println("当前未在录音");
    return;
  }
  shouldStop = true;
  uint32_t t = millis() + 3000;
  while (recording && millis() < t) delay(20);
}

/** 与录音相同的 i2s_channel_read + >>16，仅算峰值 */
static void runMeter() {
  if (!s_rxChan) return;
  size_t bytesRead = 0;
  esp_err_t err = i2s_channel_read(
    s_rxChan, (void*)s_i2sBuf, sizeof(s_i2sBuf), &bytesRead, portMAX_DELAY);
  if (err != ESP_OK) {
    Serial.printf("读失败 %s\n", esp_err_to_name(err));
    return;
  }
  if (bytesRead == 0) {
    Serial.println("bytes=0");
    return;
  }

  int n = bytesRead / sizeof(int32_t);
  int32_t peak = 0;
  for (int i = 0; i < n; i++) {
    int32_t s = sampleToPcm16(s_i2sBuf[i]);
    if (s < 0) s = -s;
    if (s > peak) peak = s;
  }
  // 小声说话 peak 往往只有几百，量程放到 2000 更易看出变化
  int bars = constrain(map((long)peak, 0, 2000, 0, 20), 0, 20);
  Serial.printf("音量 %5ld  bytes=%u  n=%d |", (long)peak, (unsigned)bytesRead, n);
  for (int i = 0; i < bars; i++) Serial.print('#');
  Serial.println();
}

/** 诊断：打印一批 raw32 与 >>16，不改读法 */
static void dumpOnce() {
  if (!s_rxChan) {
    Serial.println("I2S 不可用");
    return;
  }
  size_t bytesRead = 0;
  esp_err_t err = i2s_channel_read(
    s_rxChan, (void*)s_i2sBuf, sizeof(s_i2sBuf), &bytesRead, portMAX_DELAY);
  Serial.printf("err=%s bytes=%u\n", esp_err_to_name(err), (unsigned)bytesRead);
  int n = bytesRead / sizeof(int32_t);
  int show = n < 8 ? n : 8;
  for (int i = 0; i < show; i++) {
    Serial.printf("  [%d] raw=0x%08lx  pcm16=%d\n",
                  i, (unsigned long)s_i2sBuf[i], (int)sampleToPcm16(s_i2sBuf[i]));
  }
}

void setup() {
  Serial.begin(115200);
  delay(400);
  Serial.println();
  Serial.println("MIC 独立录音测试（读法对齐 mic_recorder）");

  bool fsOk = SPIFFS.begin(true);
  Serial.printf("SPIFFS: %s\n", fsOk ? "OK" : "FAIL");
  if (fsOk) {
    Serial.printf("  空闲 %u / %u KB\n",
                  (SPIFFS.totalBytes() - SPIFFS.usedBytes()) / 1024,
                  SPIFFS.totalBytes() / 1024);
  }

  Serial.printf("I2S: %s\n", initI2S() ? "OK" : "FAIL");
  printHelp();
}

void loop() {
  if (Serial.available()) {
    String line = Serial.readStringUntil('\n');
    line.trim();
    line.toUpperCase();
    if (line.length() == 0) return;

    if (line == "H" || line == "?") {
      printHelp();
    } else if (line == "V") {
      meterMode = !meterMode;
      Serial.println(meterMode ? "音量监视 ON（再按 V 关闭）" : "音量监视 OFF");
    } else if (line == "D") {
      dumpOnce();
    } else if (line == "LEFT") {
      if (recording) { Serial.println("先停录音 S"); }
      else {
        s_slotMask = I2S_STD_SLOT_LEFT;
        Serial.println(initI2S() ? "已切 LEFT，再发 D" : "I2S 失败");
      }
    } else if (line == "RIGHT") {
      if (recording) { Serial.println("先停录音 S"); }
      else {
        s_slotMask = I2S_STD_SLOT_RIGHT;
        Serial.println(initI2S() ? "已切 RIGHT，再发 D" : "I2S 失败");
      }
    } else if (line == "S") {
      stopRec();
    } else if (line == "LIST" || line == "L") {
      listFiles();
    } else if (line == "C") {
      clearTests();
    } else if (line.startsWith("R") && line != "RIGHT") {
      uint32_t secs = DEFAULT_SECS;
      if (line.length() > 1) {
        secs = (uint32_t)line.substring(1).toInt();
      }
      startRec(secs);
    } else {
      Serial.println("未知命令，发 H");
    }
  }

  if (meterMode && !recording) {
    runMeter();
    delay(80);
  } else {
    delay(10);
  }
}
