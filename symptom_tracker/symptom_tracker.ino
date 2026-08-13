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
#include "sos_button.h"
#include "rec_button.h"
#include "mic_recorder.h"
#include "status_led.h"
#include "event_store.h"

// 录音结束后统一通知 App（避免多处重复）；仅成功写出有效文件时才通知
static void notifyRecordingDone() {
    if (!MIC_lastRecordingOk()) {
        Serial.println("[MIC] 跳过 rec_done：本次录音无效（建文件失败或空文件）");
        return;
    }
    BLE_sendRecordingDone(
        MIC_getLastFilePath(),
        MIC_getLastDurationMs(),
        MIC_getLastFileSize()
    );
}

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
    SOS_init();        // SOS 按钮初始化（设置 GPIO25 内部上拉）
    RecBtn_init();     // 录音按钮初始化（GPIO26 内部上拉）
    StatusLed_init();  // 状态 LED（GPIO13）
    MIC_init();        // 麦克风 + SPIFFS 初始化
    EventStore_init(); // 离线事件队列（共用 SPIFFS）
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
    if (SOS_update()) {
        BLE_sendSos();
        Vibration_patternStart();
    }
    StatusLed_setSosHeld(SOS_isHeld());  // 按住 SOS 时 LED 常亮

    // ⑥b 录音按钮逻辑：
    //   - 已在录音 → 短按随时可停（即使已过 15s 窗口）
    //   - 未在录音 → 仅窗口内可开始；开始后最长 MIC_MAX_DURATION_S（30s），不因窗口关闭而打断
    if (RecBtn_update()) {
        if (MIC_isRecording()) {
            MIC_stopRecording();
            Vibration_patternStart();
            Serial.println("[RecBtn] 停止录音");
        } else if (Event_isVoiceWindowOpen()) {
            char idBuf[24];
            snprintf(idBuf, sizeof(idBuf), "%lu", Event_getVoiceEventId());
            if (MIC_startRecording(idBuf)) {
                StatusLed_pulseDouble();  // 开始：快速双闪
                StatusLed_setRecording(true);
                Vibration_patternStart();
                Serial.printf("[RecBtn] 开始录音，关联事件 %s（本事件累计最长 %ds）\n",
                              idBuf, MIC_MAX_DURATION_S);
            } else {
                Serial.println("[RecBtn] 无法开始录音（空间不足 / 累计已满 / SPIFFS 异常）");
            }
        } else {
            Serial.println("[RecBtn] 忽略：不在可开始录音的窗口内");
        }
    }

    // ⑦ 处理 App 发来的录音控制指令（BLE Write → BLE_getRecordCmd()）
    {
        uint8_t recCmd = BLE_getRecordCmd();  // 取一次指令，自动清零
        if (recCmd == 1 && !MIC_isRecording()) {
            bool started = false;
            if (Event_isVoiceWindowOpen()) {
                char idBuf[24];
                snprintf(idBuf, sizeof(idBuf), "%lu", Event_getVoiceEventId());
                started = MIC_startRecording(idBuf);
            } else {
                started = MIC_startRecording();
            }
            if (started) {
                StatusLed_pulseDouble();
                StatusLed_setRecording(true);
            }
        } else if (recCmd == 2 && MIC_isRecording()) {
            MIC_stopRecording();
        }
    }

    // ⑧ 录音刚结束（按钮停 / App 停 / 达到最长 30s）→ LED 双闪 + 通知一次
    static bool s_wasRecording = false;
    if (s_wasRecording && !MIC_isRecording()) {
        StatusLed_pulseDouble();
        StatusLed_setRecording(false);
        notifyRecordingDone();
    }
    s_wasRecording = MIC_isRecording();

    // ⑧b 推进状态灯闪烁（必须每 loop 调用）
    StatusLed_update();

    // ⑨ 处理 BLE 连接/断开事件（断开后自动重新广播）
    BLE_update();

    // ⑩ 发送实时压力值（BLE Notify + Serial 打印）
    //    仅在按压期间发送，减少无效流量
    if (pressed || Event_isRecording()) {
        BLE_sendPressure(rawValue);
    }

    // ⑪ 等待下一个采样间隔
    //    20ms = 50Hz 采样率
    //    注意：这里的 delay 会让整个循环暂停 20ms，
    //    振动状态机使用 millis() 计时，所以仍然准确。
    delay(FSR_SAMPLE_INTERVAL_MS);
}
