/**
 * ble_comm.h — BLE/Serial 通信模块（头文件）
 *
 * MVP 策略：
 *   - BLE Server 完整初始化，设备广播，等待手机连接
 *   - 所有数据【同时】通过 Serial 输出（方便调试，不依赖手机）
 *   - 手机未连接时，BLE 发送会静默跳过，不报错
 *
 * BLE 数据通道：
 *   ┌─────────────────────────────────────────────────────┐
 *   │ Service UUID:  4fafc201-1fb5-459e-8fcc-c5c9c331914b │
 *   ├────────────────────┬────────────────────────────────┤
 *   │ 压力特征            │ beb5483e-36e1-4688-b7f5-ea07361b26a8 │
 *   │ (Notify, 实时)      │ 格式: uint16_t 小端序（2字节）          │
 *   ├────────────────────┼────────────────────────────────┤
 *   │ 事件特征            │ cba1d466-344c-4be3-ab3f-189f80dd7518 │
 *   │ (Notify, 事件触发)  │ 格式: JSON 字符串                       │
 *   │                     │ start / end / sos                     │
 *   └────────────────────┴────────────────────────────────┘
 *
 * 后续手机 App 开发时：
 *   1. 扫描并连接设备名 "SymptomTracker"
 *   2. 订阅（Subscribe）两个特征的 Notify
 *   3. 即可实时收到压力值和事件数据
 */

#pragma once
#include <Arduino.h>
#include "event_detector.h"  // 需要 PressEvent 结构体定义

/**
 * BLE_init()
 * 初始化 BLE Server 并开始广播。
 * 必须在 setup() 中调用。
 */
void BLE_init();

/**
 * BLE_update()
 * 处理 BLE 连接状态变化（连接/断开重新广播）。
 * 必须在 loop() 中每次调用。
 */
void BLE_update();

/**
 * 若 config.h 里 BATTERY_ADC_PIN >= 0，按约 30 秒上报标准电量服务。
 * 未接线时为空操作。
 */
void BLE_updateBattery();

/**
 * BLE_isConnected()
 * 返回当前是否有手机连接到本设备。
 */
bool BLE_isConnected();

/**
 * BLE_sendPressure(value)
 * 发送实时压力值（ADC 原始值，0~4095）。
 * 通过 BLE Notify 发送，同时打印到 Serial。
 * 建议在主循环每次采样后调用。
 *
 * @param value  FSR 原始 ADC 值（0~4095）
 */
void BLE_sendPressure(uint16_t value);

/**
 * BLE_sendEventStart(timestamp)
 * 发送"按压开始"事件。
 *
 * @param timestamp  按下时刻的 millis() 值
 */
void BLE_sendEventStart(unsigned long timestamp);

/**
 * BLE_sendEventEnd(event)
 * 发送"按压结束"完整事件。
 * BLE 端发送事件摘要（JSON），Serial 端发送完整压力曲线。
 *
 * @param event  指向已完成的 PressEvent 数据
 */
void BLE_sendEventEnd(const PressEvent* event);

/**
 * BLE_sendSos()
 * 发送 SOS 紧急求助事件给手机 App。
 */
void BLE_sendSos();

/**
 * BLE_sendRecordingDone(filePath, durationMs, fileSize)
 * 录音完成后通知手机 App，携带文件路径和大小信息。
 * App 收到后可以发起文件传输请求。
 */
void BLE_sendRecordingDone(const char* filePath, uint32_t durationMs, size_t fileSize);

/**
 * BLE_notifyJson(json)
 * 向事件特征推送任意 JSON（需已连接）。
 */
void BLE_notifyJson(const char* json);

/** 是否正在 BLE 文件分块传输（同步应让路） */
bool BLE_isFileXferActive();

/**
 * BLE_getRecordCmd()
 * 返回 App 最近通过 BLE 发来的录音指令：
 *   0 = 无新指令
 *   1 = 开始录音
 *   2 = 停止录音
 * 读取后自动清零（一次性消费）。
 */
uint8_t BLE_getRecordCmd();

// ─── App → ESP32 设置写回接口 ─────────────────────────────────────────────────
//
// App 通过 Write 特征（CHAR_SETTINGS_UUID）发送 JSON 命令：
//   {"cmd":"update_settings","startVibration":true,"endVibration":true,
//    "realtimeFeedback":false,"maxVibrationPower":180,"pressThreshold":200}
//
// ESP32 解析后更新以下运行时参数，下次循环即生效。

/**
 * BLE_getStartVibration()   — App 是否开启"开始震动"
 * BLE_getEndVibration()     — App 是否开启"结束震动"
 * BLE_getRealtimeFeedback() — App 是否开启实时力度反馈
 * BLE_getMaxVibrationPWM()  — 最大震动 PWM 值（0~255）
 * BLE_getPressThreshold()   — 按压检测阈值（ADC 原始值）
 */
bool     BLE_getStartVibration();
bool     BLE_getEndVibration();
bool     BLE_getRealtimeFeedback();
uint8_t  BLE_getMaxVibrationPWM();
uint16_t BLE_getPressThreshold();
