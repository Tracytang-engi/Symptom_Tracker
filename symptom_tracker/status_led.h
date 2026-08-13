/**
 * status_led.h — 状态指示 LED
 *
 * 优先级（高 → 低）：
 *   1. SOS 按住 → 常亮
 *   2. 录音开始/结束 → 快速双闪（一次性）
 *   3. 录音进行中 → 缓慢闪烁
 *   4. 其它 → 熄灭
 */

#pragma once

void StatusLed_init();

/** 每 loop 调用，推进闪烁状态机（非阻塞） */
void StatusLed_update();

/** SOS 是否按住（常亮优先） */
void StatusLed_setSosHeld(bool held);

/** 是否处于录音中（慢闪） */
void StatusLed_setRecording(bool recording);

/** 触发一次快速双闪（录音开始或结束时调用） */
void StatusLed_pulseDouble();
