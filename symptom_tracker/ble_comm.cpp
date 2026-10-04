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
#include "mic_recorder.h"
#include "event_store.h"
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ArduinoJson.h>
#include <SPIFFS.h>

// ─── BLE UUID 定义 ─────────────────────────────────────
// UUID 是 128 位标识符，用于区分不同的 BLE 服务和特征。
// 这里使用随机生成的私有 UUID（非蓝牙标准 UUID）。
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHAR_PRESSURE_UUID  "beb5483e-36e1-4688-b7f5-ea07361b26a8"  // 实时压力值
#define CHAR_EVENT_UUID     "cba1d466-344c-4be3-ab3f-189f80dd7518"  // 事件通知
#define CHAR_SETTINGS_UUID  "a1b2c3d4-5678-9abc-def0-123456789abc"  // App→ESP32 设置写入
#define CHAR_FILE_DATA_UUID "d4e5f607-1829-4a3b-8c9d-0e1f2a3b4c5d"  // ESP32→App 二进制文件包

// ─── 运行时设置（可被 App 通过 BLE Write 更新）────────────────
static bool     s_startVibration   = true;
static bool     s_endVibration     = true;
static bool     s_realtimeFeedback = true;
static uint8_t  s_maxVibPWM        = 204;  // 80% of 255
static uint16_t s_pressThreshold   = FSR_THRESHOLD;
static uint8_t  s_recordCmd        = 0;    // 0=无 1=开始录音 2=停止录音（App发来）

// ─── 模块内部状态（须在文件传输函数之前声明）────────────────
static BLEServer*         s_pServer        = nullptr;
static BLECharacteristic* s_pPressureChar  = nullptr;  // 压力值特征
static BLECharacteristic* s_pBatteryChar   = nullptr;
static uint8_t            s_lastBatteryPct = 255;
static uint32_t           s_lastBatteryMs  = 0;
static BLECharacteristic* s_pEventChar     = nullptr;  // 事件特征
static BLECharacteristic* s_pSettingsChar  = nullptr;  // 设置写入特征
static BLECharacteristic* s_pFileDataChar  = nullptr;  // WAV 二进制 Notify
static bool               s_connected      = false;    // 当前是否有客户端连接
static bool               s_wasConnected   = false;    // 上一次是否连接（用于检测断开）

// ─── 可靠 WAV 文件传输 ─────────────────────────────────────
// DATA 包：[seq:u32 LE][len:u16 LE][flags:u8][reserved:u8][binary payload]
// 每 4 包等待 App ACK；最终 CRC32/size 校验后，收到 file_ok 才删除 Flash 文件。
#define FILE_HEADER_SIZE       8
#define FILE_MIN_PACKET_SIZE  20
#define FILE_MAX_PACKET_SIZE 244
#define FILE_WINDOW_PACKETS    4
#define FILE_ACK_TIMEOUT_MS 3000
#define FILE_MAX_RETRIES       5

static bool     s_xferActive       = false;
static bool     s_xferWaitingAck   = false;
static bool     s_xferWaitingOk    = false;
static File     s_xferFile;
static size_t   s_xferOffset       = 0;
static size_t   s_xferTotal        = 0;
static size_t   s_xferWindowOffset = 0;
static uint32_t s_xferNextSeq      = 0;
static uint32_t s_xferWindowSeq    = 0;
static uint32_t s_xferLastSentSeq  = 0;
static uint32_t s_xferCrc          = 0;
static uint32_t s_xferAckDeadline  = 0;
static uint8_t  s_xferWindowCount  = 0;
static uint8_t  s_xferRetries      = 0;
static uint16_t s_xferPacketSize   = FILE_MIN_PACKET_SIZE;
static char     s_xferPath[64]     = "";

static uint32_t crc32Update(uint32_t crc, const uint8_t* data, size_t len) {
    crc = ~crc;
    for (size_t i = 0; i < len; i++) {
        crc ^= data[i];
        for (uint8_t bit = 0; bit < 8; bit++) {
            crc = (crc >> 1) ^ (0xEDB88320UL & (uint32_t)-(int32_t)(crc & 1));
        }
    }
    return ~crc;
}

static uint32_t calculateFileCrc(File& file) {
    uint8_t buf[256];
    uint32_t crc = 0;
    file.seek(0);
    while (file.available()) {
        size_t n = file.read(buf, sizeof(buf));
        if (n == 0) break;
        crc = crc32Update(crc, buf, n);
    }
    file.seek(0);
    return crc;
}

static void xferAbort(const char* reason) {
    if (s_xferFile) s_xferFile.close();
    s_xferActive     = false;
    s_xferWaitingAck = false;
    s_xferWaitingOk  = false;
    Serial.printf("[BLE] 文件传输中止: %s\n", reason);
    char buf[160];
    snprintf(buf, sizeof(buf),
             "{\"type\":\"file_error\",\"path\":\"%s\",\"reason\":\"%s\"}",
             s_xferPath, reason);
    if (s_connected && s_pEventChar) {
        s_pEventChar->setValue((uint8_t*)buf, strlen(buf));
        s_pEventChar->notify();
    }
}

static void xferSendEnd() {
    char buf[180];
    snprintf(buf, sizeof(buf),
             "{\"type\":\"file_end\",\"path\":\"%s\",\"size\":%u,\"crc\":%lu}",
             s_xferPath, (unsigned)s_xferTotal, (unsigned long)s_xferCrc);
    if (s_connected && s_pEventChar) {
        s_pEventChar->setValue((uint8_t*)buf, strlen(buf));
        s_pEventChar->notify();
    }
    Serial.printf("[BLE] %s\n", buf);
}

static void xferRewindWindow() {
    s_xferFile.seek(s_xferWindowOffset);
    s_xferOffset      = s_xferWindowOffset;
    s_xferNextSeq     = s_xferWindowSeq;
    s_xferWindowCount = 0;
    s_xferWaitingAck  = false;
}

/** 每次最多发 4 包，随后必须等手机 ACK */
static void BLE_processFileXfer() {
    if (!s_xferActive || !s_connected || !s_pFileDataChar) return;
    if (s_xferWaitingOk) return;

    if (s_xferWaitingAck) {
        if ((int32_t)(millis() - s_xferAckDeadline) >= 0) {
            if (++s_xferRetries > FILE_MAX_RETRIES) {
                xferAbort("ack_timeout");
                return;
            }
            Serial.printf("[BLE] ACK 超时，重传窗口 seq=%lu（第 %u 次）\n",
                          (unsigned long)s_xferWindowSeq, s_xferRetries);
            xferRewindWindow();
        } else {
            return;
        }
    }

    if (s_xferWindowCount == 0) {
        s_xferWindowOffset = s_xferOffset;
        s_xferWindowSeq    = s_xferNextSeq;
    }

    uint8_t packet[FILE_MAX_PACKET_SIZE];
    const size_t payloadCapacity = s_xferPacketSize - FILE_HEADER_SIZE;

    while (s_xferWindowCount < FILE_WINDOW_PACKETS && s_xferOffset < s_xferTotal) {
        size_t remaining = s_xferTotal - s_xferOffset;
        size_t want = remaining < payloadCapacity ? remaining : payloadCapacity;
        size_t n = s_xferFile.read(packet + FILE_HEADER_SIZE, want);
        if (n == 0) {
            xferAbort("read_failed");
            return;
        }

        uint32_t seq = s_xferNextSeq;
        uint16_t payloadLen = (uint16_t)n;
        memcpy(packet + 0, &seq, sizeof(seq));
        memcpy(packet + 4, &payloadLen, sizeof(payloadLen));
        packet[6] = (s_xferOffset + n >= s_xferTotal) ? 0x01 : 0x00;
        packet[7] = 0;

        s_pFileDataChar->setValue(packet, FILE_HEADER_SIZE + n);
        s_pFileDataChar->notify();

        s_xferLastSentSeq = seq;
        s_xferNextSeq++;
        s_xferOffset += n;
        s_xferWindowCount++;
    }

    s_xferWaitingAck  = true;
    s_xferAckDeadline = millis() + FILE_ACK_TIMEOUT_MS;
}

static void startFileGet(const char* path, uint16_t requestedPacketSize) {
    if (s_xferActive) {
        xferAbort("superseded");
    }
    if (!path || path[0] == '\0') return;

    File f = SPIFFS.open(path, FILE_READ);
    if (!f || f.isDirectory()) {
        strncpy(s_xferPath, path, sizeof(s_xferPath) - 1);
        s_xferPath[sizeof(s_xferPath) - 1] = '\0';
        Serial.printf("[BLE] file_get 失败，文件不存在: %s\n", path);
        xferAbort("not_found");
        return;
    }

    strncpy(s_xferPath, path, sizeof(s_xferPath) - 1);
    s_xferPath[sizeof(s_xferPath) - 1] = '\0';
    if (requestedPacketSize < FILE_MIN_PACKET_SIZE) requestedPacketSize = FILE_MIN_PACKET_SIZE;
    if (requestedPacketSize > FILE_MAX_PACKET_SIZE) requestedPacketSize = FILE_MAX_PACKET_SIZE;

    s_xferFile        = f;
    s_xferOffset      = 0;
    s_xferTotal       = f.size();
    s_xferPacketSize  = requestedPacketSize;
    s_xferNextSeq     = 0;
    s_xferWindowCount = 0;
    s_xferRetries     = 0;
    s_xferWaitingAck  = false;
    s_xferWaitingOk   = false;
    s_xferCrc         = calculateFileCrc(s_xferFile);
    s_xferActive      = true;

    Serial.printf("[BLE] file_get: %s size=%u crc=%08lX packet=%u payload=%u\n",
                  s_xferPath, (unsigned)s_xferTotal,
                  (unsigned long)s_xferCrc, s_xferPacketSize,
                  s_xferPacketSize - FILE_HEADER_SIZE);

    char meta[200];
    snprintf(meta, sizeof(meta),
             "{\"type\":\"file_meta\",\"path\":\"%s\",\"size\":%u,\"crc\":%lu,\"packet\":%u,\"window\":%u}",
             s_xferPath, (unsigned)s_xferTotal, (unsigned long)s_xferCrc,
             s_xferPacketSize, FILE_WINDOW_PACKETS);
    s_pEventChar->setValue((uint8_t*)meta, strlen(meta));
    s_pEventChar->notify();

    if (s_xferTotal == 0) {
        s_xferWaitingOk = true;
        xferSendEnd();
    }
}

static void handleFileAck(uint32_t seq) {
    if (!s_xferActive || !s_xferWaitingAck) return;
    if (seq < s_xferLastSentSeq) return;

    s_xferWaitingAck  = false;
    s_xferWindowCount = 0;
    s_xferRetries     = 0;

    if (s_xferOffset >= s_xferTotal) {
        s_xferFile.close();
        s_xferWaitingOk = true;
        xferSendEnd();
    }
}

static void handleFileOk(const char* path, uint32_t crc) {
    if (!s_xferActive || !s_xferWaitingOk || !path) return;
    if (strcmp(path, s_xferPath) != 0 || crc != s_xferCrc) {
        xferAbort("file_ok_mismatch");
        return;
    }

    bool deleted = MIC_deleteFile(s_xferPath);
    char done[160];
    snprintf(done, sizeof(done),
             "{\"type\":\"file_done\",\"path\":\"%s\",\"ok\":true,\"deleted\":%s}",
             s_xferPath, deleted ? "true" : "false");
    s_pEventChar->setValue((uint8_t*)done, strlen(done));
    s_pEventChar->notify();
    Serial.printf("[BLE] 手机 CRC 校验成功，文件%s删除: %s\n",
                  deleted ? "已" : "未", s_xferPath);
    s_xferActive    = false;
    s_xferWaitingOk = false;
}

/** App 完成 Notify 订阅后主动查询遗留 WAV；逐条通知，最后发送结束标记。 */
static void sendRecordingList() {
    if (!s_connected || !s_pEventChar || s_xferActive) return;

    int count = 0;
    File root = SPIFFS.open("/");
    File f = root.openNextFile();
    while (f) {
        const char* name = f.name();
        const char* base = (name && name[0] == '/') ? name + 1 : name;
        if (!f.isDirectory() && base && strncmp(base, "rec_", 4) == 0) count++;
        f = root.openNextFile();
    }
    root.close();

    char msg[160];
    snprintf(msg, sizeof(msg), "{\"type\":\"rec_list_begin\",\"n\":%d}", count);
    BLE_notifyJson(msg);
    delay(30);

    root = SPIFFS.open("/");
    f = root.openNextFile();
    while (f) {
        const char* name = f.name();
        const char* base = (name && name[0] == '/') ? name + 1 : name;
        if (!f.isDirectory() && base && strncmp(base, "rec_", 4) == 0) {
            char path[64];
            if (name[0] == '/') {
                strncpy(path, name, sizeof(path) - 1);
            } else {
                snprintf(path, sizeof(path), "/%s", name);
            }
            path[sizeof(path) - 1] = '\0';
            snprintf(msg, sizeof(msg),
                     "{\"type\":\"rec_file\",\"path\":\"%s\",\"size\":%u}",
                     path, (unsigned)f.size());
            BLE_notifyJson(msg);
            delay(30);
        }
        f = root.openNextFile();
    }
    root.close();

    BLE_notifyJson("{\"type\":\"rec_list_end\"}");
    Serial.printf("[BLE] 已发送遗留录音列表: %d 个\n", count);
}

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
        // StaticJsonDocument 需容纳 file_get 的 path
        StaticJsonDocument<320> doc;
        DeserializationError err = deserializeJson(doc, rawValue.c_str());

        if (err) {
            Serial.printf("[BLE] 设置解析失败: %s\n", err.c_str());
            return;
        }

        // 验证命令类型，按 cmd 字段分发
        const char* cmd = doc["cmd"];
        if (!cmd) {
            Serial.println("[BLE] JSON 缺少 cmd 字段，忽略。");
            return;
        }

        // ── 设置更新命令 ──────────────────────────────────────
        if (strcmp(cmd, "update_settings") == 0) {
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
        // ── 录音控制命令：{"cmd":"record_start"} / {"cmd":"record_stop"} ──
        else if (strcmp(cmd, "record_start") == 0) {
            s_recordCmd = 1;  // 主循环在下次 BLE_getRecordCmd() 时取走并处理
            Serial.println("[BLE] 收到录音开始指令");
        }
        else if (strcmp(cmd, "record_stop") == 0) {
            s_recordCmd = 2;
            Serial.println("[BLE] 收到录音停止指令");
        }
        // ── 文件下载：{"cmd":"file_get","path":"/rec_x.wav"} ──
        else if (strcmp(cmd, "file_get") == 0) {
            const char* path = doc["path"];
            uint16_t packetSize = doc["packet"] | FILE_MIN_PACKET_SIZE;
            if (path) startFileGet(path, packetSize);
            else Serial.println("[BLE] file_get 缺少 path");
        }
        // ── 应用层流控：每个窗口确认最后一个连续 seq ──
        else if (strcmp(cmd, "file_ack") == 0) {
            handleFileAck(doc["seq"] | 0UL);
        }
        // ── 手机完成 size + CRC32 校验，确认后才删除 ──
        else if (strcmp(cmd, "file_ok") == 0) {
            const char* path = doc["path"];
            uint32_t crc = doc["crc"] | 0UL;
            handleFileOk(path, crc);
        }
        else if (strcmp(cmd, "file_cancel") == 0) {
            xferAbort("cancelled");
        }
        // ── App 订阅完成后查询所有尚未下载的录音 ──
        else if (strcmp(cmd, "file_list") == 0) {
            sendRecordingList();
        }
        // ── 清空全部录音腾空间：{"cmd":"file_clear"} ──
        else if (strcmp(cmd, "file_clear") == 0) {
            int n = MIC_clearAllRecordings();
            char buf[96];
            snprintf(buf, sizeof(buf),
                     "{\"type\":\"file_cleared\",\"n\":%d,\"free\":%u}",
                     n, (unsigned)MIC_freeBytes());
            if (s_connected && s_pEventChar) {
                s_pEventChar->setValue((uint8_t*)buf, strlen(buf));
                s_pEventChar->notify();
            }
            Serial.printf("[BLE] %s\n", buf);
        }
        // ── 离线事件同步：{"cmd":"sync_events"} ──
        else if (strcmp(cmd, "sync_events") == 0) {
            EventStore_requestSync();
            Serial.println("[BLE] 开始离线事件同步");
        }
        // ── 确认一条已入库：{"cmd":"sync_ack","path":"/evt_x.bin"} 或 "id":"x" ──
        else if (strcmp(cmd, "sync_ack") == 0) {
            const char* path = doc["path"];
            const char* id   = doc["id"];
            EventStore_onAck(path ? path : id);
        }
        else {
            Serial.printf("[BLE] 未知命令: %s\n", cmd);
        }
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
        s_lastBatteryPct = 255;
        Serial.println("[BLE] 手机已连接！");
        // 等 App 完成 Notify 订阅后，由 App 主动发送 sync_events。
    }

    void onDisconnect(BLEServer* pServer) override {
        s_connected    = false;
        s_wasConnected = true;
        Serial.println("[BLE] 手机已断开连接。");
    }
};

// ─────────────────────────────────────────────────────────

void BLE_init() {
    // ① 初始化 BLE 设备，设置设备名（手机扫描时显示的名字）
    BLEDevice::init(BLE_DEVICE_NAME);
    // Server 支持的上限；实际 MTU 仍由手机客户端发起协商并取双方较小值。
    BLEDevice::setMTU(247);

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

    // ⑦ WAV 二进制 DATA 特征（独立于事件 JSON）
    s_pFileDataChar = pService->createCharacteristic(
        CHAR_FILE_DATA_UUID,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
    );
    s_pFileDataChar->addDescriptor(new BLE2902());

    // ⑧ 电量：只有接了分压才创建标准 Battery Service
#if BATTERY_ADC_PIN >= 0
    analogReadResolution(12);
    analogSetPinAttenuation(BATTERY_ADC_PIN, ADC_11db);
    BLEService* pBattery = s_pServer->createService(BLEUUID((uint16_t)0x180F));
    s_pBatteryChar = pBattery->createCharacteristic(
        BLEUUID((uint16_t)0x2A19),
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
    );
    s_pBatteryChar->addDescriptor(new BLE2902());
    pBattery->start();
#else
    Serial.println("[BLE] 未接电池分压，不广播电量");
#endif

    // ⑨ 启动 Service
    pService->start();

    // ⑨ 开始广播（让手机能扫描到本设备）
    BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
#if BATTERY_ADC_PIN >= 0
    pAdvertising->addServiceUUID(BLEUUID((uint16_t)0x180F));
#endif
    pAdvertising->setScanResponse(true);
    // 设置广播间隔（20ms~40ms 是 BLE 推荐的快速发现间隔）
    pAdvertising->setMinPreferred(0x06);
    pAdvertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();

    Serial.println("[BLE] 初始化完成，设备名: " + String(BLE_DEVICE_NAME));
    Serial.println("[BLE] 正在广播，等待手机连接...");
}

void BLE_updateBattery() {
#if BATTERY_ADC_PIN >= 0
    if (!s_connected || !s_pBatteryChar) return;
    if (s_lastBatteryPct != 255 && millis() - s_lastBatteryMs < 30000) return;
    s_lastBatteryMs = millis();
    // 1:1 分压：ADC 看到的是电池电压的一半。3.0V→0%，4.2V→100%。
    uint32_t pinMv = analogReadMilliVolts(BATTERY_ADC_PIN);
    uint32_t batMv = pinMv * 2;
    uint8_t pct = 0;
    if (batMv >= 4200) pct = 100;
    else if (batMv > 3000) pct = (uint8_t)((batMv - 3000) * 100 / 1200);
    if (pct == s_lastBatteryPct) return;
    s_lastBatteryPct = pct;
    s_pBatteryChar->setValue(&pct, 1);
    s_pBatteryChar->notify();
#else
    (void)0;
#endif
}

void BLE_update() {
    // 文件下载优先；传输中暂停离线 sync，避免抢同一 Notify 通道
    BLE_processFileXfer();
    if (!s_xferActive) {
        EventStore_processSync();
    }

    if (s_wasConnected && !s_connected) {
        if (s_xferActive) xferAbort("disconnected");
        s_wasConnected = false;
        delay(500);
        s_pServer->startAdvertising();
        Serial.println("[BLE] 重新开始广播...");
    }
}

void BLE_notifyJson(const char* json) {
    if (!json || !s_connected || !s_pEventChar) return;
    // 文件传输中禁止其它 JSON 抢通道
    if (s_xferActive) return;
    s_pEventChar->setValue((uint8_t*)json, strlen(json));
    s_pEventChar->notify();
}

bool BLE_isFileXferActive() {
    return s_xferActive;
}

bool BLE_isConnected() {
    return s_connected;
}

void BLE_sendPressure(uint16_t value) {
    // ── BLE 发送（仅在已连接时）──────────────────────────
    // 文件传输期间暂停压力推送，避免冲掉 file_chunk
    if (s_connected && !s_xferActive) {
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

void BLE_sendRecordingDone(const char* filePath, uint32_t durationMs, size_t fileSize) {
    char buf[128];
    // 把录音结果打包成 JSON 通知 App
    snprintf(buf, sizeof(buf),
             "{\"type\":\"rec_done\",\"path\":\"%s\",\"dur\":%lu,\"size\":%u}",
             filePath, durationMs, (unsigned)fileSize);

    if (s_connected) {
        s_pEventChar->setValue((uint8_t*)buf, strlen(buf));
        s_pEventChar->notify();  // 推送给已订阅的 App
    }

    Serial.printf("[BLE] 录音完成通知: %s\n", buf);
}

uint8_t BLE_getRecordCmd() {
    uint8_t cmd = s_recordCmd;  // 取出指令
    s_recordCmd = 0;            // 清零，保证每条指令只处理一次（"一次性消费"模式）
    return cmd;
}

// ─── 运行时设置 getter 函数 ──────────────────────────────────
bool     BLE_getStartVibration()   { return s_startVibration; }
bool     BLE_getEndVibration()     { return s_endVibration; }
bool     BLE_getRealtimeFeedback() { return s_realtimeFeedback; }
uint8_t  BLE_getMaxVibrationPWM()  { return s_maxVibPWM; }
uint16_t BLE_getPressThreshold()   { return s_pressThreshold; }
