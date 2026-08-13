/**
 * rec_button.cpp — 录音按钮（短按边沿 + 消抖）
 */

#include "rec_button.h"
#include "config.h"
#include <Arduino.h>

// 消抖状态（与 SOS 相同原理，但触发条件是短按边沿，不是长按）
static bool     s_lastRaw      = HIGH;
static bool     s_stableState  = HIGH;
static uint32_t s_lastChangeMs = 0;
static bool     s_prevStable   = HIGH;  // 上一拍稳定电平，用于检测按下边沿

void RecBtn_init() {
    pinMode(REC_BTN_PIN, INPUT_PULLUP);
    s_lastRaw      = digitalRead(REC_BTN_PIN);
    s_stableState  = s_lastRaw;
    s_prevStable   = s_stableState;
    s_lastChangeMs = millis();

    Serial.println("[RecBtn] 初始化完成，引脚: GPIO" + String(REC_BTN_PIN)
                   + "（窗口内可开始，开始后最长 " + String(MIC_MAX_DURATION_S) + "s）");
}

bool RecBtn_update() {
    uint32_t now = millis();
    bool raw = digitalRead(REC_BTN_PIN);  // HIGH=未按，LOW=按下

    // ── 消抖：电平变化后需稳定超过 REC_BTN_DEBOUNCE_MS ──
    if (raw != s_lastRaw) {
        s_lastChangeMs = now;
        s_lastRaw = raw;
    }

    if (now - s_lastChangeMs >= REC_BTN_DEBOUNCE_MS) {
        s_stableState = raw;
    }

    // ── 按下边沿：稳定电平从 HIGH → LOW ──
    bool pressedEdge = (s_prevStable == HIGH && s_stableState == LOW);
    s_prevStable = s_stableState;

    return pressedEdge;
}
