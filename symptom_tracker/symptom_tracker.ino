/**
 * symptom_tracker.ino — 主程序入口
 *
 * 项目：ESP32 便携式症状记录设备
 * 硬件：ESP32D + FSR406 力敏电阻 + 1027 振动马达
 *
 * 整体架构（各模块职责）：
 * ┌─────────────────────────────────────────────────────────────┐
 * │  config.h          全局引脚和参数配置                        │
 * │  fsr.h/cpp         读取 FSR406，输出原始值和消抖后的按压状态 │
 * │  event_detector    检测按压开始/结束，记录压力曲线           │
 * │  vibration         非阻塞震动马达反馈（开始1震、结束2震）    │
 * │  ble_comm          BLE Server + Serial 双通道数据输出        │
 * │  sos_button        GPIO25 长按 SOS，经 BLE 推送给手机 App    │
 * └─────────────────────────────────────────────────────────────┘
 *
 * 主循环时序（每 20ms 一轮）：
 *   1. FSR_update()            读取 ADC，更新消抖状态
 *   2. Event_update()          状态机：检测按压，记录曲线
 *   3. Vibration_update()      推进震动序列（非阻塞）
 *   4. Vibration_setPressure() LED/马达强度跟随压力（PWM）
 *   5. SOS_update()            检测长按 SOS，触发时 BLE_sendSos()
 *   6. BLE_update()            处理 BLE 连接/断开
 *   7. BLE_sendPressure()      发送实时压力值
 *   8. delay(20)               控制采样间隔
 *
 * 上传前检查：
 *   - Arduino IDE 板子选择：ESP32 Dev Module（或对应型号）
 *   - 上传速度：115200 或更高
 *   - Serial Monitor 波特率：115200
 */

#include "config.h"
#include "fsr.h"
#include "event_detector.h"
#include "vibration.h"
#include "ble_comm.h"
#include "sos_button.h"  // SOS 长按按钮模块

// ─── setup()：上电后执行一次 ────────────────────────────────
void setup() {
    // 初始化串口（波特率 115200，与 Serial Monitor 保持一致）
    Serial.begin(115200);
    delay(500);  // 等待 Serial 稳定，确保后续日志能正常输出

    Serial.println("========================================");
    Serial.println("  症状记录设备 启动中...");
    Serial.println("========================================");

    // 按依赖顺序初始化各模块
    // 注意：BLE_init() 会占用较多时间（约 1~2 秒），放在最后
    FSR_init();
    Vibration_init();
    Event_init();
    SOS_init();   // SOS 按钮初始化（设置 GPIO25 内部上拉）
    BLE_init();

    Serial.println("----------------------------------------");
    Serial.println("  初始化完成，开始运行");
    Serial.println("  按压 FSR 传感器开始记录");
    Serial.println("----------------------------------------");

    // 上电完成：震动一下告知用户设备就绪
    Vibration_patternStart();
}

// ─── loop()：循环执行 ──────────────────────────────────────
void loop() {
    // ① 读取 FSR 传感器（更新内部原始值和消抖状态）
    FSR_update();

    // ② 获取本次采样结果
    uint16_t rawValue = FSR_getRaw();
    bool     pressed  = FSR_isPressed();

    // ③ 更新事件状态机
    //    - 检测按压开始/结束
    //    - 追加压力曲线数据
    //    - 在事件触发时内部调用 Vibration 和 BLE
    Event_update(rawValue, pressed);

    // ④ 推进震动马达状态机（非阻塞）
    //    必须每次 loop 都调用，否则震动序列不会前进
    Vibration_update();

    // ⑤ 实时压力强度反馈（LED 亮度 / 马达强度跟随 FSR 压力）
    //    内部会自动跳过事件模式运行期间，不会互相干扰。
    //    仅在 App 开启实时反馈（BLE_getRealtimeFeedback()）时执行。
    if (BLE_getRealtimeFeedback()) {
        Vibration_setPressure(rawValue);
    }

    // ⑥ 检测 SOS 按钮（长按 2 秒触发）
    //    SOS_update() 内部已处理消抖和长按计时，返回 true 表示本次触发
    if (SOS_update()) {
        BLE_sendSos();                  // 通过 BLE 发送 SOS 事件给手机
        Vibration_patternStart();       // 震动反馈：告知用户 SOS 已发出
    }

    // ⑦ 处理 BLE 连接/断开事件（断开后自动重新广播）
    BLE_update();

    // ⑧ 发送实时压力值（BLE Notify + Serial 打印）
    //    仅在按压期间发送，减少无效流量
    if (pressed || Event_isRecording()) {
        BLE_sendPressure(rawValue);
    }

    // ⑨ 等待下一个采样间隔
    //    20ms = 50Hz 采样率
    //    注意：这里的 delay 会让整个循环暂停 20ms，
    //    振动状态机使用 millis() 计时，所以仍然准确。
    delay(FSR_SAMPLE_INTERVAL_MS);
}
