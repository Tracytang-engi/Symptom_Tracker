/**
 * fsr.cpp — FSR406 力敏电阻读取模块（实现）
 *
 * FSR406 工作原理：
 *   FSR（Force Sensitive Resistor）是一种力敏电阻，
 *   未按压时阻值很高（约 >1MΩ），按压越重阻值越低（可到几百 Ω）。
 *   通过与 10kΩ 下拉电阻组成分压电路，将阻值变化转换为电压变化。
 *
 *   电路公式：
 *     V_adc = 3.3V × R_pulldown / (R_fsr + R_pulldown)
 *   按压越重 → R_fsr 越小 → V_adc 越大 → ADC 值越大
 */

#include "fsr.h"
#include "config.h"

// ─── 模块内部状态（static = 仅本文件可见）────────────────
static uint16_t s_rawValue     = 0;  // 最近一次 ADC 原始值
static uint8_t  s_pressCount   = 0;  // 连续超过阈值的次数（用于消抖"按下"）
static uint8_t  s_releaseCount = 0;  // 连续低于阈值的次数（用于消抖"松开"）
static bool     s_pressed      = false; // 当前消抖后的按压状态

// ─────────────────────────────────────────────────────────

void FSR_init() {
    // ESP32 ADC 默认分辨率是 12 位（0~4095），这里显式设置以防万一
    analogReadResolution(12);

    // GPIO34 是仅输入引脚，不需要 pinMode 设置
    // 但如果使用其他 GPIO（如 GPIO32），需要取消下面这行注释：
    // pinMode(FSR_PIN, INPUT);

    Serial.println("[FSR] 初始化完成，引脚: GPIO" + String(FSR_PIN));
}

void FSR_update() {
    // ① 读取 ADC 原始值
    s_rawValue = (uint16_t)analogRead(FSR_PIN);

    // ② 更新消抖计数器
    if (s_rawValue > FSR_THRESHOLD) {
        // 信号超过阈值：累加按下计数，重置松开计数
        if (s_pressCount < FSR_DEBOUNCE_COUNT) s_pressCount++;
        s_releaseCount = 0;
    } else {
        // 信号低于阈值：累加松开计数，重置按下计数
        if (s_releaseCount < FSR_DEBOUNCE_COUNT) s_releaseCount++;
        s_pressCount = 0;
    }

    // ③ 根据计数器更新按压状态
    //    只有连续 N 次都超阈值，才从"未按"变为"按下"
    if (!s_pressed && s_pressCount >= FSR_DEBOUNCE_COUNT) {
        s_pressed = true;
    }
    //    只有连续 N 次都低于阈值，才从"按下"变为"未按"
    if (s_pressed && s_releaseCount >= FSR_DEBOUNCE_COUNT) {
        s_pressed = false;
    }
}

uint16_t FSR_getRaw() {
    return s_rawValue;
}

bool FSR_isPressed() {
    return s_pressed;
}
