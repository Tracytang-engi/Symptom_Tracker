/**
 * status_led.cpp — 状态指示 LED（非阻塞状态机）
 *
 * 接线（高电平点亮）：
 *   GPIO13 → 220Ω → LED(+) → LED(-) → GND
 */

#include "status_led.h"
#include "config.h"
#include <Arduino.h>

enum LedMode {
    LED_OFF,
    LED_SOLID,       // SOS 按住
    LED_SLOW_BLINK,  // 录音中
    LED_DOUBLE_FLASH // 开始/结束双闪
};

static LedMode  s_mode       = LED_OFF;
static bool     s_sosHeld    = false;
static bool     s_recording  = false;
static bool     s_ledOn      = false;
static uint32_t s_phaseStart = 0;
static uint8_t  s_flashStep  = 0;  // 双闪步骤 0~3（亮灭亮灭），然后结束

static void writeLed(bool on) {
    // 高电平点亮：on → HIGH
    digitalWrite(STATUS_LED_PIN, on ? HIGH : LOW);
    s_ledOn = on;
}

static void applyBaseMode() {
    // 双闪结束后回到录音慢闪或熄灭
    if (s_sosHeld) {
        s_mode = LED_SOLID;
        writeLed(true);
    } else if (s_recording) {
        s_mode = LED_SLOW_BLINK;
        s_phaseStart = millis();
        writeLed(true);
    } else {
        s_mode = LED_OFF;
        writeLed(false);
    }
}

void StatusLed_init() {
    pinMode(STATUS_LED_PIN, OUTPUT);
    writeLed(false);
    Serial.println("[StatusLed] 初始化完成，引脚: GPIO" + String(STATUS_LED_PIN));
}

void StatusLed_setSosHeld(bool held) {
    if (s_sosHeld == held) return;
    s_sosHeld = held;
    if (held) {
        // SOS 优先：打断双闪，常亮
        s_mode = LED_SOLID;
        writeLed(true);
    } else {
        // 松开后恢复录音慢闪或熄灭（若正在双闪则让双闪继续）
        if (s_mode != LED_DOUBLE_FLASH) {
            applyBaseMode();
        }
    }
}

void StatusLed_setRecording(bool recording) {
    s_recording = recording;
    // 不打断进行中的双闪；双闪结束后会 applyBaseMode
    if (s_mode == LED_DOUBLE_FLASH || s_sosHeld) return;
    applyBaseMode();
}

void StatusLed_pulseDouble() {
    if (s_sosHeld) return;  // SOS 按住时不闪，保持常亮
    s_mode = LED_DOUBLE_FLASH;
    s_flashStep = 0;
    s_phaseStart = millis();
    writeLed(true);  // 第一下亮
}

void StatusLed_update() {
    uint32_t now = millis();

    if (s_sosHeld) {
        // 始终常亮（即使 setSosHeld 漏调一轮）
        if (s_mode != LED_SOLID || !s_ledOn) {
            s_mode = LED_SOLID;
            writeLed(true);
        }
        return;
    }

    switch (s_mode) {
        case LED_OFF:
            break;

        case LED_SOLID:
            // SOS 已松开但模式未切回时，纠正
            applyBaseMode();
            break;

        case LED_SLOW_BLINK:
            if (now - s_phaseStart >= STATUS_LED_SLOW_MS) {
                s_phaseStart = now;
                writeLed(!s_ledOn);
            }
            break;

        case LED_DOUBLE_FLASH:
            // 步骤：0亮 1灭 2亮 3灭 → 结束
            if (now - s_phaseStart >= STATUS_LED_FAST_MS) {
                s_phaseStart = now;
                s_flashStep++;
                if (s_flashStep >= 4) {
                    applyBaseMode();  // 回到慢闪或熄灭
                } else {
                    // 偶数步亮，奇数步灭
                    writeLed((s_flashStep % 2) == 0);
                }
            }
            break;
    }
}
