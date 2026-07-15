/**
 * event_detector.cpp — 按压事件检测模块（实现）
 *
 * 状态机详细说明：
 *
 *  STATE_IDLE（待机）：
 *    - 等待 isPressed 变为 true
 *    - 变为 true 时：记录 startTime，触发震动，切换到 PRESSING
 *
 *  STATE_PRESSING（记录中）：
 *    - 每次循环将 rawValue 追加到 curve[]
 *    - 如果曲线缓冲区满了（达到 MAX_SAMPLES），继续记录但覆盖最旧的数据
 *      → 保留最新 MAX_SAMPLES 个点（滑动窗口）
 *    - isPressed 变为 false 时：记录 endTime，计算 duration 和 peak，
 *      触发结束震动，发送 BLE，切换回 IDLE
 */

#include "event_detector.h"
#include "vibration.h"
#include "ble_comm.h"

// ─── 状态定义 ─────────────────────────────────────────────
enum EventState {
    STATE_IDLE,      // 待机，未检测到按压
    STATE_PRESSING,  // 正在按压，正在记录
};

// ─── 模块内部状态 ─────────────────────────────────────────
static EventState s_state        = STATE_IDLE;
static bool       s_prevPressed  = false;   // 上一次循环的按压状态（用于检测边沿）
static PressEvent s_currentEvent;           // 正在记录的事件（临时）
static PressEvent s_latestEvent;            // 最近一次完成的事件
static bool       s_hasLatest    = false;   // 是否已有完成的事件

// ─── 内部辅助：计算峰值 ───────────────────────────────────
static uint16_t calcPeak(const PressEvent* evt) {
    uint16_t peak = 0;
    for (uint16_t i = 0; i < evt->sampleCount; i++) {
        if (evt->curve[i] > peak) peak = evt->curve[i];
    }
    return peak;
}

// ─────────────────────────────────────────────────────────

void Event_init() {
    s_state       = STATE_IDLE;
    s_prevPressed = false;
    s_hasLatest   = false;
    memset(&s_currentEvent, 0, sizeof(s_currentEvent));
    memset(&s_latestEvent,  0, sizeof(s_latestEvent));

    Serial.println("[Event] 初始化完成");
}

void Event_update(uint16_t rawValue, bool isPressed) {

    // ── 上升沿检测：false → true，按压刚开始 ──────────────
    bool risingEdge  = ( isPressed && !s_prevPressed);
    bool fallingEdge = (!isPressed &&  s_prevPressed);

    // ─── 状态机 ───────────────────────────────────────────
    switch (s_state) {

        case STATE_IDLE:
            if (risingEdge) {
                // 按压开始：初始化新事件
                memset(&s_currentEvent, 0, sizeof(s_currentEvent));
                s_currentEvent.startTime  = millis();
                s_currentEvent.sampleCount = 0;

                // 追加第一个采样点
                s_currentEvent.curve[0] = rawValue;
                s_currentEvent.sampleCount = 1;

                // 触发"开始"震动反馈（仅当 App 未禁用时）
                if (BLE_getStartVibration()) {
                    Vibration_patternStart();
                }

                // 通知 BLE/Serial 按压开始
                BLE_sendEventStart(s_currentEvent.startTime);

                Serial.printf("[Event] ▶ 开始记录，时间戳: %lu ms\n",
                              s_currentEvent.startTime);

                s_state = STATE_PRESSING;
            }
            break;

        case STATE_PRESSING:
            // 追加采样点到压力曲线
            if (s_currentEvent.sampleCount < MAX_SAMPLES) {
                // 缓冲区未满，正常追加
                s_currentEvent.curve[s_currentEvent.sampleCount] = rawValue;
                s_currentEvent.sampleCount++;
            } else {
                // 缓冲区已满（超过 10 秒）：滚动覆盖
                // 将所有数据向前移动一位，丢弃最旧的一个点
                memmove(&s_currentEvent.curve[0],
                        &s_currentEvent.curve[1],
                        (MAX_SAMPLES - 1) * sizeof(uint16_t));
                s_currentEvent.curve[MAX_SAMPLES - 1] = rawValue;
                // sampleCount 保持 MAX_SAMPLES 不变
            }

            if (fallingEdge) {
                // 按压结束：完成事件记录
                s_currentEvent.endTime  = millis();
                s_currentEvent.duration = s_currentEvent.endTime - s_currentEvent.startTime;
                s_currentEvent.peakValue = calcPeak(&s_currentEvent);

                // 拷贝到 latestEvent
                memcpy(&s_latestEvent, &s_currentEvent, sizeof(PressEvent));
                s_hasLatest = true;

                // 触发"结束"震动反馈（仅当 App 未禁用时）
                if (BLE_getEndVibration()) {
                    Vibration_patternStop();
                }

                // 发送完整事件数据
                BLE_sendEventEnd(&s_latestEvent);

                Serial.printf("[Event] ■ 记录结束，时长: %lu ms，采样点: %u，峰值: %u\n",
                              s_latestEvent.duration,
                              s_latestEvent.sampleCount,
                              s_latestEvent.peakValue);

                s_state = STATE_IDLE;
            }
            break;
    }

    // 保存本次按压状态，供下次循环检测边沿
    s_prevPressed = isPressed;
}

bool Event_isRecording() {
    return s_state == STATE_PRESSING;
}

const PressEvent* Event_getLatest() {
    if (!s_hasLatest) return nullptr;
    return &s_latestEvent;
}
