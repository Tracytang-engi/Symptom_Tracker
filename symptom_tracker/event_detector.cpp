/**
 * event_detector.cpp — 按压事件检测模块（实现）
 *
 * 状态机：
 *
 *   IDLE ──按下──> PRESSING ──松开──> GAP(1s) ──再按下──> PRESSING
 *     ^                                │
 *     └──────── 超时未再按 ────────────┘
 *
 * 离线：未连 BLE 时写入 EventStore；队列满则拒绝开录。
 * 单次最长 EVENT_MAX_DURATION_MS（60s）。
 */

#include "event_detector.h"
#include "vibration.h"
#include "ble_comm.h"
#include "event_store.h"

enum EventState {
    STATE_IDLE,
    STATE_PRESSING,
    STATE_GAP,
};

static EventState s_state        = STATE_IDLE;
static bool       s_prevPressed  = false;
static PressEvent s_currentEvent;
static PressEvent s_latestEvent;
static bool       s_hasLatest    = false;
static uint32_t   s_gapDeadline  = 0;

static unsigned long s_voiceEventId  = 0;
static uint32_t      s_voiceDeadline = 0;
static bool          s_voiceOpen     = false;

static uint16_t calcPeak(const PressEvent* evt) {
    uint16_t peak = 0;
    for (uint16_t i = 0; i < evt->sampleCount; i++) {
        if (evt->curve[i] > peak) peak = evt->curve[i];
    }
    return peak;
}

static void appendSample(uint16_t rawValue) {
    if (s_currentEvent.sampleCount < MAX_SAMPLES) {
        s_currentEvent.curve[s_currentEvent.sampleCount] = rawValue;
        s_currentEvent.sampleCount++;
    } else {
        memmove(&s_currentEvent.curve[0],
                &s_currentEvent.curve[1],
                (MAX_SAMPLES - 1) * sizeof(uint16_t));
        s_currentEvent.curve[MAX_SAMPLES - 1] = rawValue;
    }
}

static void finalizeEvent() {
    s_currentEvent.endTime   = millis();
    s_currentEvent.duration  = s_currentEvent.endTime - s_currentEvent.startTime;
    if (s_currentEvent.duration > EVENT_MAX_DURATION_MS) {
        s_currentEvent.duration = EVENT_MAX_DURATION_MS;
    }
    s_currentEvent.peakValue = calcPeak(&s_currentEvent);

    memcpy(&s_latestEvent, &s_currentEvent, sizeof(PressEvent));
    s_hasLatest = true;

    if (BLE_getEndVibration()) {
        Vibration_patternStop();
    }

    if (BLE_isConnected()) {
        BLE_sendEventEnd(&s_latestEvent);
    } else {
        if (!EventStore_save(&s_latestEvent)) {
            Serial.println("[Event] ⚠ 离线保存失败（队列满或写盘错误）");
        }
    }

    Serial.printf("[Event] ■ 记录结束，时长: %lu ms，采样点: %u，峰值: %u%s\n",
                  s_latestEvent.duration,
                  s_latestEvent.sampleCount,
                  s_latestEvent.peakValue,
                  BLE_isConnected() ? "" : " [离线已存]");

    s_voiceDeadline = millis() + VOICE_NOTE_WINDOW_MS;
    s_voiceOpen     = true;
    Serial.printf("[Event] 语音窗口开放至 +%lu ms（共 %d s）\n",
                  s_voiceDeadline, VOICE_NOTE_WINDOW_MS / 1000);

    s_state       = STATE_IDLE;
    s_gapDeadline = 0;
}

void Event_init() {
    s_state         = STATE_IDLE;
    s_prevPressed   = false;
    s_hasLatest     = false;
    s_gapDeadline   = 0;
    s_voiceEventId  = 0;
    s_voiceDeadline = 0;
    s_voiceOpen     = false;
    memset(&s_currentEvent, 0, sizeof(s_currentEvent));
    memset(&s_latestEvent,  0, sizeof(s_latestEvent));

    Serial.println("[Event] 初始化完成（2.5s 合并 / 最长 60s / 离线队列）");
}

void Event_update(uint16_t rawValue, bool isPressed) {
    bool risingEdge  = ( isPressed && !s_prevPressed);
    bool fallingEdge = (!isPressed &&  s_prevPressed);

    switch (s_state) {

        case STATE_IDLE:
            if (risingEdge) {
                // 离线且队列满 → 拒绝新记
                if (!BLE_isConnected() && !EventStore_canStartNew()) {
                    Serial.println("[Event] ✗ 离线队列已满（100KB），拒绝新记录。请先连接手机同步。");
                    break;
                }

                memset(&s_currentEvent, 0, sizeof(s_currentEvent));
                s_currentEvent.startTime   = millis();
                s_currentEvent.sampleCount = 0;
                appendSample(rawValue);

                if (BLE_getStartVibration()) {
                    Vibration_patternStart();
                }

                if (BLE_isConnected()) {
                    BLE_sendEventStart(s_currentEvent.startTime);
                }

                Serial.printf("[Event] ▶ 开始记录，时间戳: %lu ms%s\n",
                              s_currentEvent.startTime,
                              BLE_isConnected() ? "" : " [离线]");

                s_voiceEventId  = s_currentEvent.startTime;
                s_voiceDeadline = 0;
                s_voiceOpen     = true;

                s_state = STATE_PRESSING;
            }
            break;

        case STATE_PRESSING:
            appendSample(rawValue);

            if (millis() - s_currentEvent.startTime >= EVENT_MAX_DURATION_MS) {
                Serial.println("[Event] 已达 60s 上限，自动结束");
                finalizeEvent();
                break;
            }

            if (fallingEdge) {
                s_gapDeadline = millis() + EVENT_MERGE_GAP_MS;
                s_state       = STATE_GAP;
                Serial.printf("[Event] … 松开，%d ms 内再按仍算同一次\n",
                              EVENT_MERGE_GAP_MS);
            }
            break;

        case STATE_GAP:
            appendSample(rawValue);

            if (millis() - s_currentEvent.startTime >= EVENT_MAX_DURATION_MS) {
                Serial.println("[Event] 已达 60s 上限，自动结束");
                finalizeEvent();
                break;
            }

            if (risingEdge) {
                Serial.printf("[Event] … %d ms 内再按，继续同一次记录\n",
                              EVENT_MERGE_GAP_MS);
                s_gapDeadline = 0;
                s_state       = STATE_PRESSING;
            } else if (millis() >= s_gapDeadline) {
                finalizeEvent();
            }
            break;
    }

    if (s_voiceOpen && s_state == STATE_IDLE
        && s_voiceDeadline != 0 && millis() >= s_voiceDeadline) {
        s_voiceOpen     = false;
        s_voiceEventId  = 0;
        s_voiceDeadline = 0;
        Serial.println("[Event] 语音窗口已关闭");
    }

    s_prevPressed = isPressed;
}

bool Event_isRecording() {
    return s_state == STATE_PRESSING || s_state == STATE_GAP;
}

const PressEvent* Event_getLatest() {
    if (!s_hasLatest) return nullptr;
    return &s_latestEvent;
}

bool Event_isVoiceWindowOpen() {
    return s_voiceOpen;
}

unsigned long Event_getVoiceEventId() {
    return s_voiceOpen ? s_voiceEventId : 0;
}
