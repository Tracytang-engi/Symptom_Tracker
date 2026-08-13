/**
 * mic_test.ino — INMP441 麦克风测试
 *
 * 接线（与主工程一致）：
 *   INMP441 VDD → 3.3V
 *   INMP441 GND → GND
 *   INMP441 SCK → GPIO14
 *   INMP441 WS  → GPIO15
 *   INMP441 SD  → GPIO32
 *   INMP441 L/R → GND（左声道）
 *
 * 测试方法：
 *   上传后打开 Serial Monitor（115200）
 *   对着麦克风说话或拍手，观察"音量"数字是否变化
 *   安静时应接近 0，有声音时应明显增大
 */

#include <driver/i2s.h>  // ESP32 的 I2S 驱动库（在 ESP32 Arduino 核心里自带）

// ─── 引脚定义 ─────────────────────────────────────────────────
#define I2S_SCK  14  // 位时钟（连 INMP441 的 SCK）
#define I2S_WS   15  // 字选择（连 INMP441 的 WS）
#define I2S_SD   32  // 数据输入（连 INMP441 的 SD）

// ─── I2S 采样参数 ──────────────────────────────────────────────
#define SAMPLE_RATE     16000  // 采样率 16kHz（人声清晰，数据量适中）
#define SAMPLE_BITS     32     // INMP441 输出 24bit，放在 32bit 帧里传输
#define READ_BUF_SIZE   256    // 每次读取的样本数（可调，越大延迟越高）

// ─── 全局缓冲区 ───────────────────────────────────────────────
int32_t buf[READ_BUF_SIZE];  // int32_t = 32位有符号整数，存储原始 I2S 样本

void setup() {
    Serial.begin(115200);
    Serial.println("INMP441 麦克风测试启动...");

    // ── 配置 I2S 接口 ──────────────────────────────────────────
    // i2s_config_t = I2S 配置结构体（来自 ESP-IDF 驱动）
    i2s_config_t i2s_config = {
        .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
        // MODE_MASTER = ESP32 提供时钟（主机）
        // MODE_RX     = 只接收（麦克风 → ESP32）

        .sample_rate          = SAMPLE_RATE,
        .bits_per_sample      = I2S_BITS_PER_SAMPLE_32BIT,
        .channel_format       = I2S_CHANNEL_FMT_ONLY_LEFT,
        // ONLY_LEFT = 只读左声道（L/R 接 GND 时选这个）

        .communication_format = I2S_COMM_FORMAT_STAND_I2S,
        // 标准 I2S 格式（INMP441 使用此格式）

        .intr_alloc_flags     = ESP_INTR_FLAG_LEVEL1,  // 中断优先级
        .dma_buf_count        = 8,   // DMA 缓冲区数量（DMA = 直接内存访问，让数据无需 CPU 干预自动传输）
        .dma_buf_len          = 64,  // 每个缓冲区容纳 64 个样本
        .use_apll             = false,
        .tx_desc_auto_clear   = false,
        .fixed_mclk           = 0
    };

    // i2s_pin_config_t = 引脚映射结构体
    i2s_pin_config_t pin_config = {
        .bck_io_num   = I2S_SCK,            // BCK = 位时钟 → SCK 引脚
        .ws_io_num    = I2S_WS,             // WS  = 字选择 → WS  引脚
        .data_out_num = I2S_PIN_NO_CHANGE,  // 不发送（只收音）
        .data_in_num  = I2S_SD              // 数据输入 → SD 引脚
    };

    // I2S_NUM_0 = 使用 ESP32 的第 0 个 I2S 接口（共有 I2S_NUM_0 和 I2S_NUM_1）
    i2s_driver_install(I2S_NUM_0, &i2s_config, 0, NULL);  // 安装驱动
    i2s_set_pin(I2S_NUM_0, &pin_config);                  // 绑定引脚
    i2s_zero_dma_buffer(I2S_NUM_0);                       // 清空缓冲区，防止启动时有噪声

    Serial.println("I2S 初始化完成，开始采集...");
    Serial.println("对着麦克风说话，观察音量变化：");
}

void loop() {
    size_t bytesRead = 0;

    // i2s_read = 从 I2S 接口读取一批样本到缓冲区
    // 第三个参数：要读的字节数（样本数 × 每样本字节数）
    // 第四个参数：实际读到的字节数（输出）
    // 最后参数：最多等待多少 tick（portMAX_DELAY = 一直等到有数据）
    i2s_read(I2S_NUM_0,
             (void*)buf,
             READ_BUF_SIZE * sizeof(int32_t),
             &bytesRead,
             portMAX_DELAY);

    int samplesRead = bytesRead / sizeof(int32_t);  // 实际读到的样本数

    // ── 计算本批样本的峰值（最大绝对值）─────────────────────────
    // INMP441 数据在 32bit 帧的高 24bit，右移 8 位还原真实幅度
    int32_t peak = 0;
    for (int i = 0; i < samplesRead; i++) {
        int32_t sample = buf[i] >> 8;  // >> 8 = 右移8位（去掉低8位的填充0）
        if (sample < 0) sample = -sample;   // 取绝对值（负数翻正）
        if (sample > peak) peak = sample;   // 保留最大值
    }

    // ── 把峰值转为简单的音量条显示 ────────────────────────────────
    // peak 最大约 8388607（2^23 - 1）
    int bars = map(peak, 0, 500000, 0, 20);  // map() = 线性映射到 0~20 格
    bars = constrain(bars, 0, 20);            // constrain() = 限制在 0~20 之间

    Serial.printf("音量: %6d  |", peak);
    for (int i = 0; i < bars; i++) Serial.print("█");
    Serial.println();

    delay(100);  // 每 100ms 刷新一次，不要太快刷屏
}
