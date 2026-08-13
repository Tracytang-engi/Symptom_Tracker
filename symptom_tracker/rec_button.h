/**
 * rec_button.h — 录音按钮模块（语音备注，短按）
 *
 * 接线：GPIO26（REC_BTN_PIN）→ 按钮一端；另一端 → GND
 * 使用 INPUT_PULLUP：未按=HIGH，按下=LOW
 *
 * 仅检测「短按边沿」；是否允许录音由 Event_isVoiceWindowOpen() 在主循环判断。
 */

#pragma once

void RecBtn_init();

/**
 * RecBtn_update()
 * 每次 loop 调用。返回 true = 本次检测到一次有效短按（消抖后）。
 */
bool RecBtn_update();
