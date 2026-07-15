/**
 * vibration.h — 1027 振动马达反馈模块（头文件）
 *
 * 职责：
 *   提供非阻塞（Non-blocking）的震动序列控制。
 *   使用状态机 + millis() 计时，不使用 delay()，
 *   保证主循环在震动期间仍能正常采样。
 *
 * 震动模式：
 *   patternStart → 短震 1 次（200ms）
 *   patternStop  → 短震 2 次（200ms on → 100ms off → 200ms on）
 *
 * 使用方式：
 *   setup() 中调用 Vibration_init()
 *   loop()  中每次都调用 Vibration_update()
 *   需要震动时调用 Vibration_patternStart() 或 Vibration_patternStop()
 */

#pragma once
#include <Arduino.h>

/** 初始化振动马达引脚 */
void Vibration_init();

/**
 * Vibration_update()
 * 推进震动状态机，必须在 loop() 中每次都调用。
 * 如果当前没有震动序列在执行，此函数几乎不耗时。
 */
void Vibration_update();

/**
 * Vibration_patternStart()
 * 触发"开始记录"震动模式：短震 1 次（200ms）。
 * 如果当前正在震动，会等当前序列结束后再执行（可根据需求修改为直接打断）。
 */
void Vibration_patternStart();

/**
 * Vibration_patternStop()
 * 触发"结束记录"震动模式：短震 2 次（200ms on / 100ms off / 200ms on）。
 */
void Vibration_patternStop();

/**
 * Vibration_isBusy()
 * 返回当前是否有震动序列正在执行。
 */
bool Vibration_isBusy();

/**
 * Vibration_setPressure(rawFSR)
 * 根据 FSR 原始值实时设置 LED 亮度 / 马达震动强度。
 *
 * 映射关系（由 config.h 中的 PWM_MIN / PWM_MAX 控制）：
 *   FSR 0    → PWM_MIN（最弱/关）
 *   FSR 4095 → PWM_MAX（最强/全力）
 *
 * 注意：当事件反馈模式（patternStart/Stop）正在运行时，
 *       此函数不会生效，模式结束后自动恢复压力跟随。
 *
 * 换马达后只需修改 config.h 中的 PWM_MIN，无需改这里。
 *
 * @param rawFSR  FSR_getRaw() 返回的原始 ADC 值（0~4095）
 */
void Vibration_setPressure(uint16_t rawFSR);
