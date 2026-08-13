/**
 * event_store.h — 离线疼痛事件队列（SPIFFS，含压力曲线）
 *
 * 上限 OFFLINE_QUEUE_MAX_BYTES（默认 100KB）；满则拒绝新记。
 * 文件：/evt_<startMillis>.bin
 */

#pragma once
#include <Arduino.h>
#include "event_detector.h"

void   EventStore_init();
size_t EventStore_usedBytes();
bool   EventStore_isFull();
/** 队列未满且还能再塞下至少一次「短事件」头时允许开录 */
bool   EventStore_canStartNew();
bool   EventStore_save(const PressEvent* evt);
int    EventStore_count();
/** 删除已同步事件文件（path 如 /evt_123.bin） */
bool   EventStore_delete(const char* path);

/**
 * 同步状态机（在 BLE_update 里调用）：
 * 开始后按文件依次推送 sync_meta / sync_chunk / sync_event_done，最后 sync_end。
 */
void EventStore_requestSync();
void EventStore_processSync();
bool EventStore_isSyncing();
/** App 确认已入库后调用，删除对应文件并继续下一条 */
void EventStore_onAck(const char* pathOrId);
