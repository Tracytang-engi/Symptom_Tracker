/**
 * ble_comm.cpp — BLE/Serial 通信模块（实现）
 *
 * BLE 工作流程：
 *   1. BLE_init()：创建 Server + Service + 三个 Characteristic，开始广播
 *   2. 手机扫描到 "SymptomTracker"，连接
 *   3. 手机订阅 Notify，之后每次调用 notify() 手机会收到推送
 *   4. 手机写入 CHAR_SETTINGS_UUID → onWrite 回调解析 JSON 并更新运行时参数
 *   5. 断开时，BLE_update() 会自动重新开始广播
 *
 * 关于 Characteristic 大小限制：
 *   BLE 单次 Notify 最大约 512 字节（ESP32 支持 517 字节 MTU）。
 *   压力曲线完整数据可能超过此限制，因此：
 *   - 实时压力（2 字节）→ 直接发送 uint16_t
 *   - 事件摘要（JSON ~150 字节）→ BLE Notify
 *   - 完整曲线 → Serial 打印（调试用）
 *   后续 App 开发时可以通过分包协议发送完整曲线。
 */

#include "ble_comm.h"
#include "config.h"
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>  // 标准 Client Characteristic Configuration Descriptor（CCCD），启用 Notify
#include <ArduinoJson.h>  // 用于解析 App 下发的 JSON 设置

// ─── BLE UUID 定义 ─────────────────────────────────────
// UUID 是 128 位标识符，用于区分不同的 BLE 服务和特征。
// 这里使用随机生成的私有 UUID（非蓝牙标准 UUID）。
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHAR_PRESSURE_UUID  "beb5483e-36e1-4688-b7f5-ea07361b26a8"  // 实时压力值
#define CHAR_EVENT_UUID     "cba1d466-344c-4be3-ab3f-189f80dd7518"  // 事件通知
#define CHAR_SETTINGS_UUID  "a1b2c3d4-5678-9abc-def0-123456789abc"  // App→ESP32 设置写入

// ─── 运行时设置（可被 App 通过 BLE Write 更新）────────────────
static bool     s_startVibration   = true;
static bool     s_endVibration     = true;
static bool     s_realtimeFeedback = true;
static uint8_t  s_maxVibPWM        = 204;  // 80% of 255
static uint16_t s_pressThreshold   = FSR_THRESHOLD;

// ─── 模块内部状态 ─────────────────────────────────────────
static BLEServer*         s_pServer        = nullptr;
static BLECharacteristic* s_pPressureChar  = nullptr;  // 压力值特征
static BLECharacteristic* s_pEventChar     = nullptr;  // 事件特征
static BLECharacteristic* s_pSettingsChar  = nullptr;  // 设置写入特征
static bool               s_connected      = false;    // 当前是否有客户端连接
static bool               s_wasConnected   = false;    // 上一次是否连接（用于检测断开）

// ─── 设置写入回调 ─────────────────────────────────────────
/**
 * SettingsCallbacks：App 发送 JSON 时被调用。
 *
 * 期望格式：
 *   {"cmd":"update_settings","startVibration":true,"endVibration":true,
 *    "realtimeFeedback":false,"maxVibrationPower":180,"pressThreshold":200}
 *
 * 参数说明：
 *   maxVibrationPower：PWM 值（0~255），App 端已从 0.0~1.0 转换
 *   pressThreshold   ：ADC 阈值（直接使用 FSR 原始值）
 */
class SettingsCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* pChar) override {
        String rawValue = pChar->getValue().c_str();  // getValue() 返回 std::string，转为 Arduino String
        if (rawValue.length() == 0) return;

        // 用 ArduinoJson 解析（StaticJsonDocument 大小可根据 JSON 长度调整）
        StaticJsonDocument<256> doc;
        DeserializationError err = deserializeJson(doc, rawValue.c_str());

        if (err) {
            Serial.printf("[BLE] 设置解析失败: %s\n", err.c_str());
            return;
        }

        // 验证命令类型
        const char* cmd = doc["cmd"];
        if (!cmd || strcmp(cmd, "update_settings") != 0) {
            Serial.println("[BLE] 未知命令，忽略。");
            return;
        }

        // 更新运行时参数（键存在时才更新，保持未提供字段不变）
        if (doc.containsKey("startVibration"))
            s_startVibration = doc["startVibration"].as<bool>();
        if (doc.containsKey("endVibration"))
            s_endVibration = doc["endVibration"].as<bool>();
        if (doc.containsKey("realtimeFeedback"))
            s_realtimeFeedback = doc["realtimeFeedback"].as<bool>();
        if (doc.containsKey("maxVibrationPower"))
            s_maxVibPWM = (uint8_t)doc["maxVibrationPower"].as<int>();
        if (doc.containsKey("pressThreshold"))
            s_pressThreshold = (uint16_t)doc["pressThreshold"].as<int>();

        Serial.printf("[BLE] 设置已更新: startVib=%d endVib=%d realtime=%d maxPWM=%u thresh=%u\n",
                      s_startVibration, s_endVibration, s_realtimeFeedback,
                      s_maxVibPWM, s_pressThreshold);
    }
};

// ─── BLE 连接回调类 ───────────────────────────────────────
/**
 * ServerCallbacks：监听客户端连接和断开事件。
 * 继承 BLEServerCallbacks，重写两个虚函数。
 */
class ServerCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) override {
        s_connected = true;
        Serial.println("[BLE] 手机已连接！");
    }

    void onDisconnect(BLEServer* pServer) override {
        s_connected    = false;
        s_wasConnected = true;  // 标记需要重新广播
        Serial.println("[BLE] 手机已断开连接。");
    }
};

// ─────────────────────────────────────────────────────────

void BLE_init() {
    // ① 初始化 BLE 设备，设置设备名（手机扫描时显示的名字）
    BLEDevice::init(BLE_DEVICE_NAME);

    // ② 创建 BLE Server，注册回调
    s_pServer = BLEDevice::createServer();
    s_pServer->setCallbacks(new ServerCallbacks());

    // ③ 创建主 Service
    BLEService* pService = s_pServer->createService(SERVICE_UUID);

    // ④ 创建"实时压力"特征
    //    属性：READ（可读）+ NOTIFY（主动推送）
    s_pPressureChar = pService->createCharacteristic(
        CHAR_PRESSURE_UUID,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
    );
    // 添加 CCCD Descriptor（客户端通过它来开启/关闭 Notify）
    s_pPressureChar->addDescriptor(new BLE2902());

    // ⑤ 创建"事件"特征
    //    属性：READ + NOTIFY
    s_pEventChar = pService->createCharacteristic(
        CHAR_EVENT_UUID,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
    );
    s_pEventChar->addDescriptor(new BLE2902());

    // ⑥ 创建"设置写入"特征（WRITE）
    //    App 通过此特征下发 JSON 更新震动/阈值等参数
    s_pSettingsChar = pService->createCharacteristic(
        CHAR_SETTINGS_UUID,
        BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
    );
    s_pSettingsChar->setCallbacks(new SettingsCallbacks());

    // ⑦ 启动 Service
    pService->start();

    // ⑧ 开始广播（让手机能扫描到本设备）
    BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    // 设置广播间隔（20ms~40ms 是 BLE 推荐的快速发现间隔）
    pAdvertising->setMinPreferred(0x06);
    pAdvertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();

    Serial.println("[BLE] 初始化完成，设备名: " + String(BLE_DEVICE_NAME));
    Serial.println("[BLE] 正在广播，等待手机连接...");
}

void BLE_update() {
    // 如果刚刚断开连接，重新开始广播
    if (s_wasConnected && !s_connected) {
        s_wasConnected = false;
        delay(500);  // 等待 BLE 栈稳定
        s_pServer->startAdvertising();
        Serial.println("[BLE] 重新开始广播...");
    }
}

bool BLE_isConnected() {
    return s_connected;
}

void BLE_sendPressure(uint16_t value) {
    // ── BLE 发送（仅在已连接时）──────────────────────────
    if (s_connected) {
        // 将 uint16_t 拆成 2 个字节（小端序）发送
        uint8_t buf[2];
        buf[0] = value & 0xFF;         // 低字节
        buf[1] = (value >> 8) & 0xFF;  // 高字节
        s_pPressureChar->setValue(buf, 2);
        s_pPressureChar->notify();
    }

    // ── Serial 输出（始终打印，方便调试）────────────────
    // 格式："P:1234" 简短格式，避免刷屏影响可读性
    // 注意：每 20ms 打印一次，建议在 Serial Monitor 中开启"时间戳"
    Serial.printf("P:%u\n", value);
}

void BLE_sendEventStart(unsigned long timestamp) {
    // 构造 JSON 字符串
    char buf[80];
    snprintf(buf, sizeof(buf),
             "{\"type\":\"start\",\"t\":%lu}",
             timestamp);

    // ── BLE 发送 ────────────────────────────────────────
    if (s_connected) {
        s_pEventChar->setValue((uint8_t*)buf, strlen(buf));
        s_pEventChar->notify();
    }

    // ── Serial 输出 ──────────────────────────────────────
    Serial.printf("[BLE] 发送开始事件: %s\n", buf);
}

void BLE_sendEventEnd(const PressEvent* evt) {
    if (evt == nullptr) return;

    // ── BLE：发送事件摘要 JSON（不含完整曲线，避免超出 512 字节限制）──
    char summary[200];
    snprintf(summary, sizeof(summary),
             "{\"type\":\"end\",\"t\":%lu,\"end\":%lu,\"dur\":%lu,\"peak\":%u,\"n\":%u}",
             evt->startTime,
             evt->endTime,
             evt->duration,
             evt->peakValue,
             evt->sampleCount);

    if (s_connected) {
        s_pEventChar->setValue((uint8_t*)summary, strlen(summary));
        s_pEventChar->notify();
    }

    // ── Serial：发送完整数据（含原始压力曲线）──────────────
    Serial.println("==== 事件记录 ====");
    Serial.printf("  开始时间:  %lu ms\n", evt->startTime);
    Serial.printf("  结束时间:  %lu ms\n", evt->endTime);
    Serial.printf("  持续时长:  %lu ms\n", evt->duration);
    Serial.printf("  峰值压力:  %u (ADC)\n", evt->peakValue);
    Serial.printf("  采样点数:  %u\n", evt->sampleCount);
    Serial.print("  压力曲线: [");
    for (uint16_t i = 0; i < evt->sampleCount; i++) {
        if (i > 0) Serial.print(",");
        Serial.print(evt->curve[i]);
    }
    Serial.println("]");
    Serial.println("==================");

    Serial.printf("[BLE] 发送事件摘要: %s\n", summary);
}

void BLE_sendSos() {
    // 构造 SOS 事件 JSON，包含触发时刻的时间戳
    char buf[60];
    snprintf(buf, sizeof(buf), "{\"type\":\"sos\",\"ts\":%lu}", millis());

    // BLE 发送（已连接时推送给手机 App）
    if (s_connected) {
        s_pEventChar->setValue((uint8_t*)buf, strlen(buf));
        s_pEventChar->notify();  // notify() = 主动推送给已订阅的客户端
    }

    // Serial 始终打印（方便调试，即使手机未连接也能看到）
    Serial.println("[SOS] ★★★ SOS 已发送！★★★");
    Serial.printf("[SOS] BLE payload: %s\n", buf);
}

// ─── 运行时设置 getter 函数 ──────────────────────────────────
bool     BLE_getStartVibration()   { return s_startVibration; }
bool     BLE_getEndVibration()     { return s_endVibration; }
bool     BLE_getRealtimeFeedback() { return s_realtimeFeedback; }
uint8_t  BLE_getMaxVibrationPWM()  { return s_maxVibPWM; }
uint16_t BLE_getPressThreshold()   { return s_pressThreshold; }
