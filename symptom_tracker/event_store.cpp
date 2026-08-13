/**
 * event_store.cpp — 离线事件 SPIFFS 队列 + BLE 同步推送
 */

#include "event_store.h"
#include "config.h"
#include "ble_comm.h"
#include <SPIFFS.h>

static const char* kMagic = "EV01";

#pragma pack(push, 1)
struct EvtHeader {
    char     magic[4];
    uint32_t startTime;
    uint32_t endTime;
    uint32_t duration;
    uint16_t peakValue;
    uint16_t sampleCount;
};
#pragma pack(pop)

static bool isEvtName(const char* name) {
    if (!name) return false;
    const char* base = (name[0] == '/') ? name + 1 : name;
    return strncmp(base, "evt_", 4) == 0;
}

static void makePath(char* out, size_t outLen, unsigned long startTime) {
    snprintf(out, outLen, "/evt_%lu.bin", startTime);
}

size_t EventStore_usedBytes() {
    size_t used = 0;
    File root = SPIFFS.open("/");
    if (!root) return 0;
    File f = root.openNextFile();
    while (f) {
        if (!f.isDirectory() && isEvtName(f.name())) {
            used += f.size();
        }
        f = root.openNextFile();
    }
    return used;
}

int EventStore_count() {
    int n = 0;
    File root = SPIFFS.open("/");
    if (!root) return 0;
    File f = root.openNextFile();
    while (f) {
        if (!f.isDirectory() && isEvtName(f.name())) n++;
        f = root.openNextFile();
    }
    return n;
}

bool EventStore_isFull() {
    return EventStore_usedBytes() >= OFFLINE_QUEUE_MAX_BYTES;
}

bool EventStore_canStartNew() {
    // 至少预留一次约 2s 曲线（100 点）的空间，否则拒绝开录
    const size_t reserve = sizeof(EvtHeader) + 100 * 2;
    size_t used = EventStore_usedBytes();
    if (used >= OFFLINE_QUEUE_MAX_BYTES) return false;
    if (OFFLINE_QUEUE_MAX_BYTES - used < reserve) return false;
    return true;
}

void EventStore_init() {
    size_t used = EventStore_usedBytes();
    int n = EventStore_count();
    Serial.printf("[EvtStore] 离线队列: %d 条, %u / %u KB\n",
                  n,
                  (unsigned)(used / 1024),
                  (unsigned)(OFFLINE_QUEUE_MAX_BYTES / 1024));
}

bool EventStore_save(const PressEvent* evt) {
    if (!evt || evt->sampleCount == 0) return false;

    size_t payload = sizeof(EvtHeader) + (size_t)evt->sampleCount * 2;
    size_t used = EventStore_usedBytes();
    if (used + payload > OFFLINE_QUEUE_MAX_BYTES) {
        Serial.printf("[EvtStore] 保存失败：队列将超限（需 +%uB，已用 %uB）\n",
                      (unsigned)payload, (unsigned)used);
        return false;
    }

    char path[40];
    makePath(path, sizeof(path), evt->startTime);

    File f = SPIFFS.open(path, FILE_WRITE);
    if (!f) {
        Serial.printf("[EvtStore] 无法创建 %s\n", path);
        return false;
    }

    EvtHeader h;
    memcpy(h.magic, kMagic, 4);
    h.startTime   = (uint32_t)evt->startTime;
    h.endTime     = (uint32_t)evt->endTime;
    h.duration    = (uint32_t)evt->duration;
    h.peakValue   = evt->peakValue;
    h.sampleCount = evt->sampleCount;

    f.write((const uint8_t*)&h, sizeof(h));
    f.write((const uint8_t*)evt->curve, (size_t)evt->sampleCount * 2);
    f.close();

    Serial.printf("[EvtStore] 已存离线 %s (%u B)，队列 %u KB\n",
                  path, (unsigned)payload,
                  (unsigned)(EventStore_usedBytes() / 1024));
    return true;
}

bool EventStore_delete(const char* path) {
    if (!path) return false;
    if (SPIFFS.remove(path)) {
        Serial.printf("[EvtStore] 已删除 %s\n", path);
        return true;
    }
    return false;
}

// ─── 同步状态机 ───────────────────────────────────────────

enum SyncPhase {
    SYNC_IDLE,
    SYNC_BEGIN,
    SYNC_OPEN,
    SYNC_META,
    SYNC_CHUNKS,
    SYNC_EVENT_DONE,
    SYNC_WAIT_ACK,
    SYNC_END,
};

static SyncPhase s_phase = SYNC_IDLE;
static File      s_syncFile;
static char      s_syncPath[40] = "";
static char      s_syncId[24]   = "";
static size_t    s_syncOff      = 0;
static size_t    s_syncTotal    = 0;
static EvtHeader s_syncHdr;
static bool      s_syncRequested = false;
static uint8_t   s_chunkBurst    = 0;
static uint32_t  s_ackDeadline   = 0;
static uint8_t   s_syncRetries   = 0;

static const uint32_t SYNC_ACK_TIMEOUT_MS = 10000;
static const uint8_t  SYNC_MAX_RETRIES    = 3;

static size_t base64Encode(const uint8_t* in, size_t inLen, char* out, size_t outCap) {
    static const char* kTbl =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    size_t o = 0;
    for (size_t i = 0; i < inLen && o + 4 < outCap; i += 3) {
        uint32_t n = ((uint32_t)in[i]) << 16;
        if (i + 1 < inLen) n |= ((uint32_t)in[i + 1]) << 8;
        if (i + 2 < inLen) n |= (uint32_t)in[i + 2];
        out[o++] = kTbl[(n >> 18) & 63];
        out[o++] = kTbl[(n >> 12) & 63];
        out[o++] = (i + 1 < inLen) ? kTbl[(n >> 6) & 63] : '=';
        out[o++] = (i + 2 < inLen) ? kTbl[n & 63] : '=';
    }
    out[o] = '\0';
    return o;
}

static bool openNextEvtFile() {
    File root = SPIFFS.open("/");
    if (!root) return false;
    File f = root.openNextFile();
    while (f) {
        if (!f.isDirectory() && isEvtName(f.name())) {
            const char* n = f.name();
            if (n[0] == '/') {
                strncpy(s_syncPath, n, sizeof(s_syncPath) - 1);
            } else {
                snprintf(s_syncPath, sizeof(s_syncPath), "/%s", n);
            }
            s_syncPath[sizeof(s_syncPath) - 1] = '\0';
            // id = 文件名中的数字
            const char* p = strstr(s_syncPath, "evt_");
            if (p) {
                strncpy(s_syncId, p + 4, sizeof(s_syncId) - 1);
                char* dot = strchr(s_syncId, '.');
                if (dot) *dot = '\0';
            }
            f.close();
            root.close();
            s_syncFile = SPIFFS.open(s_syncPath, FILE_READ);
            return (bool)s_syncFile;
        }
        f = root.openNextFile();
    }
    return false;
}

void EventStore_requestSync() {
    if (s_phase != SYNC_IDLE) {
        Serial.println("[EvtStore] 同步已在进行");
        return;
    }
    s_syncRequested = true;
}

bool EventStore_isSyncing() {
    return s_phase != SYNC_IDLE;
}

void EventStore_processSync() {
    if (s_phase == SYNC_IDLE) {
        if (!s_syncRequested) return;
        if (!BLE_isConnected()) return;
        s_syncRequested = false;
        s_phase = SYNC_BEGIN;
    }

    if (!BLE_isConnected()) {
        if (s_syncFile) s_syncFile.close();
        s_phase = SYNC_IDLE;
        s_syncRequested = false;
        s_syncRetries = 0;
        Serial.println("[EvtStore] 同步中断：BLE 断开");
        return;
    }

    char msg[480];

    switch (s_phase) {
        case SYNC_BEGIN: {
            int n = EventStore_count();
            snprintf(msg, sizeof(msg), "{\"type\":\"sync_begin\",\"n\":%d}", n);
            BLE_notifyJson(msg);
            Serial.printf("[EvtStore] sync_begin n=%d\n", n);
            s_phase = (n > 0) ? SYNC_OPEN : SYNC_END;
            break;
        }
        case SYNC_OPEN:
            if (!openNextEvtFile()) {
                s_phase = SYNC_END;
                break;
            }
            if (s_syncFile.read((uint8_t*)&s_syncHdr, sizeof(s_syncHdr)) != sizeof(s_syncHdr) ||
                memcmp(s_syncHdr.magic, kMagic, 4) != 0) {
                Serial.printf("[EvtStore] 坏文件，删除 %s\n", s_syncPath);
                s_syncFile.close();
                EventStore_delete(s_syncPath);
                s_phase = SYNC_OPEN;
                break;
            }
            s_syncTotal = (size_t)s_syncHdr.sampleCount * 2;
            s_syncOff   = 0;
            s_phase     = SYNC_META;
            break;

        case SYNC_META:
            snprintf(msg, sizeof(msg),
                     "{\"type\":\"sync_meta\",\"id\":\"%s\",\"path\":\"%s\","
                     "\"t\":%lu,\"end\":%lu,\"now\":%lu,"
                     "\"dur\":%lu,\"peak\":%u,\"n\":%u}",
                     s_syncId, s_syncPath,
                     (unsigned long)s_syncHdr.startTime,
                     (unsigned long)s_syncHdr.endTime,
                     (unsigned long)millis(),
                     (unsigned long)s_syncHdr.duration,
                     (unsigned)s_syncHdr.peakValue,
                     (unsigned)s_syncHdr.sampleCount);
            BLE_notifyJson(msg);
            s_phase = SYNC_CHUNKS;
            s_chunkBurst = 0;
            break;

        case SYNC_CHUNKS: {
            // 每 loop 最多 3 包
            for (int i = 0; i < 3 && s_syncOff < s_syncTotal; i++) {
                uint8_t raw[90];
                size_t want = s_syncTotal - s_syncOff;
                if (want > sizeof(raw)) want = sizeof(raw);
                size_t n = s_syncFile.read(raw, want);
                if (n == 0) break;
                char b64[140];
                base64Encode(raw, n, b64, sizeof(b64));
                int len = snprintf(msg, sizeof(msg),
                                   "{\"type\":\"sync_chunk\",\"id\":\"%s\",\"off\":%u,\"total\":%u,\"data\":\"%s\"}",
                                   s_syncId, (unsigned)s_syncOff, (unsigned)s_syncTotal, b64);
                if (len > 0 && (size_t)len < sizeof(msg)) {
                    BLE_notifyJson(msg);
                }
                s_syncOff += n;
            }
            if (s_syncOff >= s_syncTotal) {
                s_phase = SYNC_EVENT_DONE;
            }
            break;
        }

        case SYNC_EVENT_DONE:
            snprintf(msg, sizeof(msg),
                     "{\"type\":\"sync_event_done\",\"id\":\"%s\",\"path\":\"%s\",\"ok\":true}",
                     s_syncId, s_syncPath);
            BLE_notifyJson(msg);
            s_syncFile.close();
            s_phase = SYNC_WAIT_ACK;
            s_ackDeadline = millis() + SYNC_ACK_TIMEOUT_MS;
            Serial.printf("[EvtStore] 等待 sync_ack: %s\n", s_syncPath);
            break;

        case SYNC_WAIT_ACK:
            // 丢包时 App 不会 ACK；超时后从 meta 开始重发本事件。
            if ((int32_t)(millis() - s_ackDeadline) >= 0) {
                if (s_syncRetries < SYNC_MAX_RETRIES) {
                    s_syncRetries++;
                    Serial.printf("[EvtStore] sync_ack 超时，重试 %u/%u: %s\n",
                                  (unsigned)s_syncRetries,
                                  (unsigned)SYNC_MAX_RETRIES,
                                  s_syncPath);
                    s_phase = SYNC_OPEN;
                } else {
                    Serial.printf("[EvtStore] 同步失败，保留文件稍后重试: %s\n",
                                  s_syncPath);
                    s_syncRetries = 0;
                    s_phase = SYNC_END;
                }
            }
            break;

        case SYNC_END:
            snprintf(msg, sizeof(msg), "{\"type\":\"sync_end\"}");
            BLE_notifyJson(msg);
            Serial.println("[EvtStore] sync_end");
            s_phase = SYNC_IDLE;
            break;

        default:
            s_phase = SYNC_IDLE;
            break;
    }
}

void EventStore_onAck(const char* path) {
    if (s_phase != SYNC_WAIT_ACK) return;
    if (!path) return;
    // 允许 path 或 id 匹配
    bool match = (strcmp(path, s_syncPath) == 0) || (strcmp(path, s_syncId) == 0);
    if (!match) {
        Serial.printf("[EvtStore] ack 不匹配: %s (期望 %s)\n", path, s_syncPath);
        return;
    }
    EventStore_delete(s_syncPath);
    s_syncRetries = 0;
    s_phase = SYNC_OPEN;
}
