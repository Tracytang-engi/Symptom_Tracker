/**
 * mic_recorder.h — INMP441 麦克风录音模块（头文件）
 *
 * 功能：
 *   - 通过 I2S 接口采集 INMP441 的数字音频
 *   - 以标准 WAV 格式写入 SPIFFS（ESP32 内置闪存文件系统）
 *   - 录音在独立的 FreeRTOS 任务里运行，不阻塞主循环
 *
 * 存储路径格式：
 *   - 关联疼痛事件：/rec_<eventId>_<seg>.wav（多段，累计 ≤ MIC_MAX_DURATION_S）
 *   - 无事件：/rec_<millis>.wav
 *
 * 限制：
 *   SPIFFS 约 1.5MB 可用，16kHz/16bit/单声道 = 32KB/秒，
 *   约能存 1~2 段 30 秒录音。App 下载后建议及时删除。
 */

#pragma once
#include <Arduino.h>

// ─── 初始化 ──────────────────────────────────────────────────

/**
 * MIC_init()
 * 初始化 SPIFFS 文件系统 + I2S 驱动。
 * 必须在 setup() 里调用一次。
 * 返回 false 表示 SPIFFS 挂载失败（通常是第一次上传需要格式化）。
 */
bool MIC_init();

// ─── 录音控制 ─────────────────────────────────────────────────

/**
 * MIC_startRecording(eventId)
 * 开始录音。同一 eventId 可多段，累计满 MIC_MAX_DURATION_S 后返回 false。
 * @param eventId  关联的疼痛事件 ID（写入文件名便于 App 对应），可传 ""
 * 返回 false 表示已在录音、累计已满或文件创建失败。
 */
bool MIC_startRecording(const char* eventId = "");

/**
 * MIC_stopRecording()
 * 停止录音，补写 WAV 文件头，关闭文件。
 * 录音结束后调用 MIC_getLastFilePath() 获取文件路径。
 */
void MIC_stopRecording();

// ─── 状态查询 ─────────────────────────────────────────────────

bool        MIC_isRecording();       // 当前是否正在录音
const char* MIC_getLastFilePath();   // 最近一次录音的文件路径
uint32_t    MIC_getLastDurationMs(); // 最近一次录音时长（毫秒）
size_t      MIC_getLastFileSize();   // 最近一次录音文件大小（字节）
bool        MIC_lastRecordingOk();   // 最近一次是否成功写出有效 WAV（可通知 App 下载）

/** 剩余可用字节 */
size_t MIC_freeBytes();

/**
 * MIC_ensureSpace(needBytes)
 * 仅检查空闲是否 ≥ needBytes，**不会**删除任何未上传文件。
 * 空间不够时应拒绝开始新录音；删除只发生在 App 下载成功后的 file_delete。
 */
bool MIC_ensureSpace(size_t needBytes);

/**
 * MIC_clearAllRecordings()
 * 手动清空 SPIFFS 上所有录音（仅用户主动调用，如 Settings → Clear）。
 * 未下载的会丢失。
 */
int MIC_clearAllRecordings();

// ─── 文件管理 ─────────────────────────────────────────────────

/**
 * MIC_deleteFile(path)
 * 删除指定录音文件（App 下载后调用，释放闪存空间）。
 */
bool MIC_deleteFile(const char* path);

/**
 * MIC_listFiles(outBuf, bufSize)
 * 把所有录音文件路径写入 outBuf（逗号分隔），供 BLE 查询。
 */
void MIC_listFiles(char* outBuf, size_t bufSize);
