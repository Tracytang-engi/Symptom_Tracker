/**
 * fsr.h — FSR406 力敏电阻读取模块（头文件）
 *
 * 职责：
 *   1. 初始化 ADC
 *   2. 每次主循环调用 FSR_update()，读取并消抖
 *   3. 对外提供原始值和消抖后的"是否按压"状态
 *
 * 使用方式：
 *   setup() 中调用 FSR_init()
 *   loop()  中调用 FSR_update()，然后用 FSR_getRaw() / FSR_isPressed()
 */

#pragma once
#include <Arduino.h>

/**
 * FSR_init()
 * 初始化 ADC 分辨率，必须在 setup() 中调用一次。
 */
void FSR_init();

/**
 * FSR_update()
 * 读取一次 ADC 值并更新消抖状态机。
 * 必须在主循环中每次都调用，采样间隔由 main loop 的 delay 控制。
 */
void FSR_update();

/**
 * FSR_getRaw()
 * 返回最近一次 FSR_update() 读到的原始 ADC 值（0~4095）。
 * 未消抖，适合用于记录压力曲线。
 */
uint16_t FSR_getRaw();

/**
 * FSR_isPressed()
 * 返回消抖后的按压状态（true = 有按压，false = 未按压）。
 * 需要连续 FSR_DEBOUNCE_COUNT 次超过阈值才返回 true，
 * 连续 FSR_DEBOUNCE_COUNT 次低于阈值才返回 false。
 */
bool FSR_isPressed();
