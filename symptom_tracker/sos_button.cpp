/**
 * sos_button.cpp — SOS 按钮模块（实现）
 *
 * 接线：GPIO25 → 按钮一端；按钮另一端 → GND
 * 使用 INPUT_PULLUP（内部上拉），无需外接电阻：
 *   未按下 → GPIO25 = HIGH（内部上拉到 3.3V）
 *   按下   → GPIO25 = LOW （接地）
 *
 * 触发条件：连续按住超过 SOS_HOLD_MS（2秒），只触发一次。
 */

#include "sos_button.h"
#include "config.h"
#include <Arduino.h>  // HIGH/LOW、pinMode、digitalRead、Serial、uint32_t 等都来自这里

// ─── 模块内部状态（static = 仅本文件可见）──────────────────

// 消抖相关：
// 机械按钮按下瞬间金属触点会快速弹跳（bounce），
// 产生几毫秒内多次 HIGH/LOW 切换，直接读会误判。
// 解决方法：等信号稳定超过 SOS_DEBOUNCE_MS 毫秒再确认。
static bool     s_lastRaw       = HIGH;  // 上一次直接读到的原始电平
static bool     s_stableState   = HIGH;  // 消抖后确认的稳定电平
static uint32_t s_lastChangeMs  = 0;     // 电平最近一次发生变化的时间（毫秒）

// 长按相关：
static bool     s_pressing      = false; // 当前是否处于"已确认按下"状态
static uint32_t s_pressStartMs  = 0;     // 按下开始的时间
static bool     s_triggered     = false; // 本次长按是否已经触发过（防止重复触发）

// ─────────────────────────────────────────────────────────────

void SOS_init() {
    // INPUT_PULLUP = 数字输入模式 + 启用内部上拉电阻
    // 内部上拉约 45kΩ，让引脚默认处于 HIGH，按下接地变 LOW
    pinMode(SOS_PIN, INPUT_PULLUP);

    Serial.println("[SOS] 初始化完成，引脚: GPIO" + String(SOS_PIN)
                   + "  长按触发: " + String(SOS_HOLD_MS) + "ms");
}

bool SOS_update() {
    uint32_t now = millis();  // millis() = 程序运行到现在的毫秒数

    // ── 第一步：消抖 ──────────────────────────────────────────
    // 每次读取按钮原始电平
    bool raw = digitalRead(SOS_PIN);  // HIGH = 未按，LOW = 按下

    if (raw != s_lastRaw) {
        // 电平发生了变化，记录变化时间，重新开始计时
        // 还不能确认，需要等信号保持稳定超过 SOS_DEBOUNCE_MS
        s_lastChangeMs = now;
        s_lastRaw = raw;
    }

    // 判断电平是否已经稳定了足够长时间（超过消抖时间窗口）
    // now - s_lastChangeMs = 距上次变化已经过去的毫秒数
    if (now - s_lastChangeMs >= SOS_DEBOUNCE_MS) {
        // 信号稳定，更新确认状态
        // 这里才算"真正"的按键状态，去掉了弹跳噪声
        s_stableState = raw;
    }

    // ── 第二步：检测长按 ──────────────────────────────────────
    if (s_stableState == LOW && !s_pressing) {
        // 刚确认按下（之前是松开状态，现在变成按下）
        s_pressing     = true;
        s_pressStartMs = now;   // 记录按下开始时间
        s_triggered    = false; // 重置触发标志，允许本次长按触发一次
        Serial.println("[SOS] 按钮按下，等待长按...");
    }

    if (s_stableState == HIGH && s_pressing) {
        // 按钮松开了
        if (!s_triggered) {
            // 没有达到长按时间就松开 → 无效短按，忽略
            Serial.printf("[SOS] 短按 %lu ms，未触发（需长按 %d ms）\n",
                          now - s_pressStartMs, SOS_HOLD_MS);
        }
        s_pressing  = false;
        s_triggered = false;
    }

    // 检查是否达到长按时长
    // now - s_pressStartMs = 已经按住了多少毫秒
    if (s_pressing && !s_triggered
        && (now - s_pressStartMs >= SOS_HOLD_MS)) {
        // 达到长按阈值，触发一次 SOS
        s_triggered = true;  // 标记已触发，防止手不松的情况下重复触发
        Serial.println("[SOS] ★★★ SOS 触发！★★★");
        return true;  // 通知主循环本次触发了 SOS
    }

    return false;  // 本次 loop() 没有触发
}
