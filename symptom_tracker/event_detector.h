/**
 * event_detector.h — 按压事件检测模块（头文件）
 *
 * 职责：
 *   监控 FSR 的按压状态变化，识别"按压开始"和"按压结束"，
 *   记录整个按压过程的时间戳和压力曲线，
 *   并在事件发生时触发震动反馈和 BLE 发送。
 *
 * 状态机：
 *
 *   ┌────────┐  按下   ┌──────────┐  松开   ┌─────┐
 *   │  IDLE  │ ──────> │ PRESSING │ ──────> │ GAP │
 *   └────────┘         └──────────┘ <────── └─────┘
 *        ^                 再按(≤1s)          │
 *        └────────── 超时未再按 ──────────────┘
 *
 * GAP = EVENT_MERGE_GAP_MS（默认 2.5s）：握力抖动不拆成多条事件。
 *
 * 数据结构 PressEvent：
 *   记录一次完整按压的所有信息。
 */

#pragma once
#include <Arduino.h>
#include "config.h"

// ─── 核心数据结构 ────────────────────────────────────────

/**
 * PressEvent — 一次完整按压事件的数据
 *
 * curve[]      保存完整的压力时间序列（最多 MAX_SAMPLES 个点）
 * sampleCount  实际采集到的点数（可能 < MAX_SAMPLES）
 * startTime    按下时刻（millis()，设备上电后的毫秒数）
 * endTime      松开时刻（millis()）
 * duration     按压总时长（毫秒）= endTime - startTime
 * peakValue    整个按压过程的峰值 ADC 值
 */
struct PressEvent {
    unsigned long startTime;
    unsigned long endTime;
    unsigned long duration;
    uint16_t      curve[MAX_SAMPLES];  // 压力曲线（原始 ADC 值）
    uint16_t      sampleCount;
    uint16_t      peakValue;
};

// ─── 模块函数 ─────────────────────────────────────────────

/** 初始化事件检测模块，必须在 setup() 中调用 */
void Event_init();

/**
 * Event_update(rawValue, isPressed)
 * 推进事件状态机，必须在 loop() 中每次调用。
 *
 * @param rawValue   本次采样的 FSR 原始 ADC 值（来自 FSR_getRaw()）
 * @param isPressed  消抖后的按压状态（来自 FSR_isPressed()）
 */
void Event_update(uint16_t rawValue, bool isPressed);

/**
 * Event_isRecording()
 * 当前是否仍在一次疼痛记录中（含松开后的 1s 合并窗口 GAP）。
 */
bool Event_isRecording();

/**
 * Event_getLatest()
 * 返回指向最近一次完成的 PressEvent 的指针。
 * 如果还没有任何完成的事件，返回 nullptr。
 * 注意：此指针指向内部静态变量，下次按压时会被覆盖。
 */
const PressEvent* Event_getLatest();

/**
 * Event_isVoiceWindowOpen()
 * 「允许开始语音备注」的窗口是否打开：
 *   FSR 疼痛记录进行中，或疼痛结束后 VOICE_NOTE_WINDOW_MS 内。
 * 注意：只约束「能否开始录音」；已开始的录音不受窗口关闭影响，最长仍录 MIC_MAX_DURATION_S。
 */
bool Event_isVoiceWindowOpen();

/**
 * Event_getVoiceEventId()
 * 返回当前语音窗口关联的疼痛事件 ID（用按压开始的 millis 作为 ID）。
 * 窗口未打开时返回 0。
 */
unsigned long Event_getVoiceEventId();
