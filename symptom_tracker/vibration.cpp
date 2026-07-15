/**
 * vibration.cpp — 振动/LED 反馈模块（实现）
 *
 * 当前测试配置：LED + 440Ω 电阻代替振动马达
 *   - LED 亮起 = 马达震动
 *   - LED 熄灭 = 马达停止
 *   接线确认后换上马达，代码无需任何修改。
 *
 * 为什么不用 delay()？
 *   delay() 会让整个程序暂停，FSR 采样、BLE 通信都会中断。
 *   例如震动 200ms 期间，你会丢失 10 个采样点（20ms × 10）。
 *
 * 解决方案：时间片状态机
 *   用一个数组描述震动序列（每步的"开/关"和"持续时间"），
 *   每次 loop() 中检查时间是否到了，到了就切换到下一步。
 *   这样主循环可以继续采样，不受影响。
 */

#include "vibration.h"
#include "config.h"

// ─── 震动序列描述结构 ─────────────────────────────────────
struct VibStep {
    bool     motorOn;      // true = 马达开（LED 亮），false = 马达关（LED 灭）
    uint16_t durationMs;   // 这一步持续多少毫秒（0 表示序列结束）
};

// ─── 预定义震动模式 ───────────────────────────────────────

// "开始记录"模式：短震 1 次（200ms）
static const VibStep PATTERN_START[] = {
    { true,  200 },  // 开 200ms
    { false, 0   },  // 结束（duration=0 表示序列终止）
};

// "结束记录"模式：短震 2 次（200ms on, 100ms off, 200ms on）
static const VibStep PATTERN_STOP[] = {
    { true,  200 },  // 开 200ms
    { false, 100 },  // 关 100ms
    { true,  200 },  // 开 200ms
    { false, 0   },  // 结束
};

// ─── 模块内部状态 ─────────────────────────────────────────
static const VibStep* s_pattern     = nullptr; // 当前序列指针
static uint8_t        s_stepIndex   = 0;       // 当前执行到第几步
static uint32_t       s_stepStartMs = 0;       // 当前这一步开始的时间

// ─── 内部辅助：向引脚写 PWM 值 ──────────────────────────
// 统一封装，将来改引脚或精度只改这一处。
// ESP32 Core 3.x：ledcWrite 第一个参数是引脚号（不再是通道号）
static inline void pwmWrite(uint8_t value) {
    ledcWrite(MOTOR_PIN, value);
}

// ─── 内部辅助：启动一个震动序列 ───────────────────────────
static void startPattern(const VibStep* pattern) {
    s_pattern     = pattern;
    s_stepIndex   = 0;
    s_stepStartMs = millis();

    // 立即执行第一步（全开或全关）
    pwmWrite(pattern[0].motorOn ? PWM_MAX : 0);
}

// ─────────────────────────────────────────────────────────

void Vibration_init() {
    // ESP32 Arduino Core 3.x 新 API：一行完成通道配置 + 引脚绑定
    // 旧版（2.x）用的是 ledcSetup() + ledcAttachPin()，3.x 已合并为 ledcAttach()
    ledcAttach(MOTOR_PIN, LEDC_FREQ_HZ, LEDC_RESOLUTION);
    pwmWrite(0); // 确保初始状态关闭

    Serial.println("[Vibration] 初始化完成，引脚: GPIO" + String(MOTOR_PIN)
                   + "  PWM范围: " + String(PWM_MIN) + "~" + String(PWM_MAX));
}

void Vibration_update() {
    // 如果没有正在执行的序列，直接返回
    if (s_pattern == nullptr) return;

    const VibStep& currentStep = s_pattern[s_stepIndex];

    // duration=0 是序列结束的标志，理论上不会到这里，但做个保护
    if (currentStep.durationMs == 0) {
        s_pattern = nullptr;
        pwmWrite(0);
        return;
    }

    // 检查当前这一步是否超时
    uint32_t elapsed = millis() - s_stepStartMs;
    if (elapsed >= currentStep.durationMs) {
        // 切换到下一步
        s_stepIndex++;
        const VibStep& nextStep = s_pattern[s_stepIndex];

        if (nextStep.durationMs == 0) {
            // 序列结束，输出归零（压力跟随将在下次 loop 里恢复）
            s_pattern = nullptr;
            pwmWrite(0);
        } else {
            // 执行下一步
            s_stepStartMs = millis();
            pwmWrite(nextStep.motorOn ? PWM_MAX : 0);
        }
    }
}

void Vibration_setPressure(uint16_t rawFSR) {
    // 事件反馈模式优先，模式运行时不覆盖
    if (s_pattern != nullptr) return;

    // 限幅：超过 FSR_MAP_MAX 的部分全部当作最大值处理
    // 这样调低 FSR_MAP_MAX 就能让较小的力度达到全亮/全震
    // 低于按压阈值时强制关闭马达（避免 PWM_MIN 导致待机时也在震动）
    if (rawFSR < FSR_THRESHOLD) {
        pwmWrite(0);
        return;
    }

    uint16_t clamped = (rawFSR < FSR_MAP_MAX) ? rawFSR : FSR_MAP_MAX;

    // 将 FSR 值（FSR_THRESHOLD~FSR_MAP_MAX）线性映射到 PWM 范围（PWM_MIN~PWM_MAX）
    // 从阈值开始映射，轻触即可感受到最低震动，而不是从 0 开始
    uint8_t pwm = (uint8_t)map(clamped, FSR_THRESHOLD, FSR_MAP_MAX, PWM_MIN, PWM_MAX);
    pwmWrite(pwm);

    // 【临时调试】每 300ms 打印一次压力→PWM 映射结果
    static uint32_t lastDbg = 0;
    if (millis() - lastDbg > 300) {
        lastDbg = millis();
        Serial.printf("  FSR=%4d  clamped=%4d  PWM=%3d  (%.0f%%)\n",
                      rawFSR, clamped, pwm, pwm / 255.0f * 100.0f);
    }
}

void Vibration_patternStart() {
    // 如果当前正在震动，直接打断并执行新序列
    // （因为开始事件优先级高）
    startPattern(PATTERN_START);
}

void Vibration_patternStop() {
    startPattern(PATTERN_STOP);
}

bool Vibration_isBusy() {
    return s_pattern != nullptr;
}
