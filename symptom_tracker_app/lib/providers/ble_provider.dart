import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/pain_event.dart';
import '../services/ble_service.dart';
import '../services/calibration_service.dart';
import '../services/post_event_service.dart';
import '../services/sos_service.dart';
import '../services/device_file_transfer.dart';
import 'events_provider.dart';
import 'settings_provider.dart';

// ─── BleService 单例 ──────────────────────────────────────────────────────────

final bleServiceProvider = Provider<BleService>((ref) {
  final service = BleService();
  ref.onDispose(service.dispose);
  return service;
});

/// 当前正在从设备下载的录音路径；null 表示没有文件传输。
final activeDeviceFileTransferPathProvider =
    StateProvider<String?>((ref) => null);

/// 全局唯一的设备文件下载服务，确保自动下载和手动下载共享同一状态。
final deviceFileTransferProvider = Provider<DeviceFileTransfer>((ref) {
  return DeviceFileTransfer(
    ref.watch(bleServiceProvider),
    onTransferChanged: (path) {
      ref.read(activeDeviceFileTransferPathProvider.notifier).state = path;
    },
  );
});

// ─── PostEventService（由 main 注入已 init 的实例）────────────────────────────

final postEventServiceProvider = Provider<PostEventService>((ref) {
  throw UnimplementedError('PostEventService must be overridden in main()');
});

// ─── SosService 单例 ──────────────────────────────────────────────────────────

final sosServiceProvider = Provider<SosService>((ref) => SosService());

/// 最近一次 SOS 告警（手动按钮或硬件长按），供 UI 弹出对话框
class SosAlert {
  final DateTime time;
  final String? location;
  final bool fromDevice; // true = 设备按钮；false = App 内按钮

  const SosAlert({
    required this.time,
    this.location,
    this.fromDevice = false,
  });
}

final lastSosAlertProvider = StateProvider<SosAlert?>((ref) => null);

/// 发作结束后需要弹标签选择时，把事件放进这里（由 Shell 监听并弹出 TagSelector）
final pendingTagPromptProvider = StateProvider<PainEvent?>((ref) => null);

/// 设备端是否正在录语音（与 FSR isRecordingProvider 分开）
final isDeviceVoiceRecordingProvider = StateProvider<bool>((ref) => false);

/// 最近一次设备语音录完通知（供 SnackBar / 后续下载）
class DeviceRecDone {
  final String path;
  final int durationMs;
  final int sizeBytes;
  final DateTime time;

  const DeviceRecDone({
    required this.path,
    required this.durationMs,
    required this.sizeBytes,
    required this.time,
  });
}

final lastDeviceRecDoneProvider = StateProvider<DeviceRecDone?>((ref) => null);

// ─── 连接状态 Stream ──────────────────────────────────────────────────────────

final bleConnectionStateProvider = StreamProvider<BleConnectionState>((ref) {
  final service = ref.watch(bleServiceProvider);
  return service.connectionState;
});

// ─── 电量 ─────────────────────────────────────────────────────────────────────

final bleBatteryProvider = StreamProvider<int>((ref) {
  final service = ref.watch(bleServiceProvider);
  return service.batteryLevel;
});

// ─── 实时压力（0.0~1.0）──────────────────────────────────────────────────────

final realtimePressureProvider = StateProvider<double>((ref) => 0.0);

// ─── 是否正在记录（FSR 疼痛事件）──────────────────────────────────────────────

final isRecordingProvider = StateProvider<bool>((ref) => false);

// ─── 事件积累器（私有辅助类）───────────────────────────────────────────────────

class _EventAccumulator {
  DateTime? startTime;
  int? deviceStartMs;
  final List<int> rawSamples = [];
}

// ─── BLE 事件监听 Provider ────────────────────────────────────────────────────

final bleEventListenerProvider = Provider<void>((ref) {
  final service = ref.watch(bleServiceProvider);
  final accumulator = _EventAccumulator();
  const uuid = Uuid();
  // 语音先于 end 到达时，按 deviceEventKey 暂存路径
  final orphanDeviceRecs = <String, List<String>>{};

  // 实时 end：同步占位，防止 Notify 重复 / 异步竞态各 insert 一次
  final claimedRealtimeKeys = <String>{};
  // 串行处理 end，避免并发 add
  var realtimeEndChain = Future<void>.value();

  // 离线 sync 组装器
  String? syncId;
  String? syncPath;
  int? syncStartMs;
  int? syncEndMs;
  int? syncNowMs;
  int? syncDur;
  int? syncPeak;
  final syncChunks = <int, Uint8List>{};
  int? syncTotal;
  final recoveredRecPaths = <String>[];

  StreamSubscription? sub;

  sub = service.bleEvents.listen((event) {
    final deviceSettings = ref.read(deviceSettingsProvider);

    switch (event.type) {
      case BleEventType.pressureUpdate:
        final raw = event.pressureRaw ?? 0;
        final relative = CalibrationService.mapToRelative(raw, deviceSettings);
        ref.read(realtimePressureProvider.notifier).state = relative;

        if (ref.read(isRecordingProvider)) {
          accumulator.rawSamples.add(raw);
        }
        break;

      case BleEventType.recordingStart:
        accumulator.startTime = event.timestamp ?? DateTime.now();
        accumulator.deviceStartMs = event.deviceStartMs;
        accumulator.rawSamples.clear();
        ref.read(isRecordingProvider.notifier).state = true;
        break;

      case BleEventType.recordingEnd:
        ref.read(isRecordingProvider.notifier).state = false;
        ref.read(realtimePressureProvider.notifier).state = 0.0;

        // 与离线 sync 一致：deviceEventKey = 设备 startTime(ms) 字符串
        final deviceKey =
            (event.deviceStartMs ?? accumulator.deviceStartMs)?.toString();

        // 重复 end Notify：同步丢弃（须在清空 accumulator 之前判断）
        if (deviceKey != null) {
          if (claimedRealtimeKeys.contains(deviceKey)) {
            break;
          }
          claimedRealtimeKeys.add(deviceKey);
          if (claimedRealtimeKeys.length > 80) {
            claimedRealtimeKeys.remove(claimedRealtimeKeys.first);
          }
        }

        final start = accumulator.startTime ?? DateTime.now();
        final end = DateTime.now();
        final durationMs =
            event.durationMs ?? end.difference(start).inMilliseconds;
        final samples = List<int>.from(accumulator.rawSamples);

        final mean = CalibrationService.computeMean(samples, deviceSettings);
        final peak = event.peakRaw != null
            ? CalibrationService.mapToRelative(event.peakRaw!, deviceSettings)
            : CalibrationService.computePeak(samples, deviceSettings);

        final activeProfileId = ref.read(userSettingsProvider).activeProfileId;

        final orphanPaths = deviceKey != null
            ? (orphanDeviceRecs.remove(deviceKey) ?? [])
            : <String>[];

        accumulator.startTime = null;
        accumulator.deviceStartMs = null;
        accumulator.rawSamples.clear();

        realtimeEndChain = realtimeEndChain.then((_) async {
          PainEvent? existing;
          if (deviceKey != null) {
            for (final e in ref.read(eventsProvider)) {
              if (e.deviceEventKey == deviceKey) {
                existing = e;
                break;
              }
            }
          }

          if (existing != null) {
            final pending = List<String>.from(existing.pendingDeviceRecPaths);
            for (final p in orphanPaths) {
              if (!pending.contains(p)) pending.add(p);
            }
            final useSamples =
                samples.isNotEmpty ? samples : existing.rawSamples;
            await ref.read(eventsProvider.notifier).updateEvent(
                  existing.copyWith(
                    durationMs: durationMs,
                    meanForce:
                        samples.isNotEmpty ? mean : existing.meanForce,
                    peakForce:
                        samples.isNotEmpty ? peak : existing.peakForce,
                    rawSamples: useSamples,
                    pendingDeviceRecPaths: pending,
                  ),
                );
            for (final p in orphanPaths) {
              unawaited(_attachAndDownloadDeviceRec(ref, p));
            }
            return;
          }

          final painEvent = PainEvent(
            id: uuid.v4(),
            profileId: activeProfileId,
            startTime: start,
            endTime: end,
            durationMs: durationMs,
            meanForce: mean,
            peakForce: peak,
            rawSamples: samples,
            fromDevice: true,
            deviceEventKey: deviceKey,
            pendingDeviceRecPaths: orphanPaths,
          );

          await ref.read(eventsProvider.notifier).addEvent(painEvent);

          for (final p in orphanPaths) {
            unawaited(_attachAndDownloadDeviceRec(ref, p));
          }

          final settings = ref.read(userSettingsProvider);
          final recent = ref.read(eventsProvider).take(20).toList();
          await ref.read(postEventServiceProvider).onEventEnd(
                event: painEvent,
                settings: settings,
                context: null,
                recentEvents: recent,
                onTagsRequested: () {
                  ref.read(pendingTagPromptProvider.notifier).state = painEvent;
                },
              );
        });
        unawaited(realtimeEndChain);
        break;

      case BleEventType.sos:
        unawaited(() async {
          final loc = await ref.read(sosServiceProvider).trigger();
          ref.read(lastSosAlertProvider.notifier).state = SosAlert(
            time: DateTime.now(),
            location: loc,
            fromDevice: true,
          );
        }());
        break;

      case BleEventType.recDone:
        ref.read(isDeviceVoiceRecordingProvider.notifier).state = false;
        final path = event.recPath ?? '';
        final size = event.recSize ?? 0;
        final dur = event.durationMs ?? 0;
        if (path.isNotEmpty) {
          ref.read(lastDeviceRecDoneProvider.notifier).state = DeviceRecDone(
            path: path,
            durationMs: dur,
            sizeBytes: size,
            time: DateTime.now(),
          );

          if (size <= 44 || dur <= 0) {
            break;
          }

          final key = DeviceFileTransfer.eventKeyFromPath(path);
          final events = ref.read(eventsProvider);
          final matched =
              key != null && events.any((e) => e.deviceEventKey == key);

          // 疼痛仍在进行且尚无匹配事件：暂存，等 recordingEnd
          // 否则立刻下载（避免只进 orphan 后永远不传）
          if (!matched && key != null && ref.read(isRecordingProvider)) {
            final list = orphanDeviceRecs.putIfAbsent(key, () => []);
            if (!list.contains(path)) list.add(path);
          } else {
            unawaited(_attachAndDownloadDeviceRec(ref, path));
          }
        }
        break;

      case BleEventType.fileChunk:
      case BleEventType.fileMeta:
      case BleEventType.fileEnd:
      case BleEventType.fileError:
      case BleEventType.fileDone:
        // DeviceFileTransfer 直接监听这些事件。
        break;

      case BleEventType.recListBegin:
        recoveredRecPaths.clear();
        break;

      case BleEventType.recFile:
        final path = event.recPath;
        if (path != null &&
            path.isNotEmpty &&
            (event.recSize ?? 0) > 44 &&
            !recoveredRecPaths.contains(path)) {
          recoveredRecPaths.add(path);
        }
        break;

      case BleEventType.recListEnd:
        final paths = List<String>.from(recoveredRecPaths);
        recoveredRecPaths.clear();
        unawaited(() async {
          // 单通道依次下载，避免多个 file_get 互相冲突。
          for (final path in paths) {
            await _attachAndDownloadDeviceRec(
              ref,
              path,
              allowFallback: false,
            );
          }
        }());
        break;

      case BleEventType.syncBegin:
        syncId = null;
        syncPath = null;
        syncChunks.clear();
        syncTotal = null;
        break;

      case BleEventType.syncMeta:
        syncId = event.syncId;
        syncPath = event.recPath;
        syncStartMs = event.deviceStartMs;
        syncEndMs = event.deviceEndMs;
        syncNowMs = event.deviceNowMs;
        syncDur = event.durationMs;
        syncPeak = event.peakRaw;
        syncChunks.clear();
        syncTotal = null;
        break;

      case BleEventType.syncChunk:
        if (event.syncId != syncId) break;
        if (event.fileData != null) {
          syncChunks[event.fileOffset ?? 0] = event.fileData!;
        }
        syncTotal = event.fileTotal ?? syncTotal;
        break;

      case BleEventType.syncEventDone:
        unawaited(_finishSyncEvent(
          ref,
          uuid: uuid,
          syncId: event.syncId ?? syncId,
          syncPath: event.recPath ?? syncPath,
          startMs: syncStartMs,
          endMs: syncEndMs,
          deviceNowMs: syncNowMs,
          durationMs: syncDur,
          peakRaw: syncPeak,
          chunks: Map<int, Uint8List>.from(syncChunks),
          total: syncTotal,
        ));
        syncChunks.clear();
        break;

      case BleEventType.syncEnd:
        // 离线曲线全部入库并 ACK 后，再查询遗留 WAV，避免两种传输冲突。
        unawaited(service.writeFileList());
        break;
    }
  });

  ref.onDispose(() => sub?.cancel());
});

Future<void> _finishSyncEvent(
  Ref ref, {
  required Uuid uuid,
  required String? syncId,
  required String? syncPath,
  required int? startMs,
  required int? endMs,
  required int? deviceNowMs,
  required int? durationMs,
  required int? peakRaw,
  required Map<int, Uint8List> chunks,
  required int? total,
}) async {
  if (syncId == null) return;

  final offsets = chunks.keys.toList()..sort();
  final builder = BytesBuilder(copy: false);
  var cursor = 0;
  for (final off in offsets) {
    if (off != cursor) return; // 缺包
    final part = chunks[off]!;
    builder.add(part);
    cursor += part.length;
  }
  if (total != null && total > 0 && cursor != total) return;

  final bytes = builder.takeBytes();
  final samples = <int>[];
  final bd = ByteData.sublistView(bytes);
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    samples.add(bd.getUint16(i, Endian.little));
  }

  final deviceSettings = ref.read(deviceSettingsProvider);
  final dur = durationMs ?? (samples.length * 20);
  final receivedAt = DateTime.now();
  final end = endMs != null && deviceNowMs != null && deviceNowMs >= endMs
      ? receivedAt.subtract(Duration(milliseconds: deviceNowMs - endMs))
      : receivedAt;
  final start = startMs != null && deviceNowMs != null && deviceNowMs >= startMs
      ? receivedAt.subtract(Duration(milliseconds: deviceNowMs - startMs))
      : end.subtract(Duration(milliseconds: dur));
  final mean = CalibrationService.computeMean(samples, deviceSettings);
  final peak = peakRaw != null
      ? CalibrationService.mapToRelative(peakRaw, deviceSettings)
      : CalibrationService.computePeak(samples, deviceSettings);

  final deviceKey = startMs?.toString() ?? syncId;
  PainEvent? existing;
  for (final event in ref.read(eventsProvider)) {
    if (event.deviceEventKey == deviceKey) {
      existing = event;
      break;
    }
  }

  if (existing != null) {
    // 实时摘要可能已经入库；用离线文件补齐权威曲线，但不创建重复事件。
    await ref.read(eventsProvider.notifier).updateEvent(
          existing.copyWith(
            durationMs: dur,
            meanForce: mean,
            peakForce: peak,
            rawSamples: samples,
          ),
        );
    await ref.read(bleServiceProvider).writeSyncAck(path: syncPath, id: syncId);
    return;
  }

  final painEvent = PainEvent(
    id: uuid.v4(),
    profileId: ref.read(userSettingsProvider).activeProfileId,
    startTime: start,
    endTime: end,
    durationMs: dur,
    meanForce: mean,
    peakForce: peak,
    rawSamples: samples,
    fromDevice: true,
    deviceEventKey: deviceKey,
  );

  await ref.read(eventsProvider.notifier).addEvent(painEvent);
  await ref.read(bleServiceProvider).writeSyncAck(path: syncPath, id: syncId);
}

Future<void> _attachAndDownloadDeviceRec(
  Ref ref,
  String remotePath, {
  bool allowFallback = true,
}) async {
  final key = DeviceFileTransfer.eventKeyFromPath(remotePath);
  final events = ref.read(eventsProvider);

  PainEvent? target;
  if (key != null) {
    for (final e in events) {
      if (e.deviceEventKey == key) {
        target = e;
        break;
      }
    }
  }
  if (target == null && allowFallback) {
    for (final e in events) {
      if (e.fromDevice) {
        target = e;
        break;
      }
    }
    target ??= events.isEmpty ? null : events.first;
  }
  if (target == null) return;

  final pending = List<String>.from(target.pendingDeviceRecPaths);
  if (!pending.contains(remotePath)) pending.add(remotePath);
  var updated = target.copyWith(pendingDeviceRecPaths: pending);
  await ref.read(eventsProvider.notifier).updateEvent(updated);

  final xfer = ref.read(deviceFileTransferProvider);
  final local = await xfer.downloadAndSave(remotePath);
  if (local == null) return;

  PainEvent latest = updated;
  for (final e in ref.read(eventsProvider)) {
    if (e.id == updated.id) {
      latest = e;
      break;
    }
  }

  final paths = List<String>.from(latest.voiceNotePaths);
  if (!paths.contains(local)) paths.add(local);
  final stillPending = List<String>.from(latest.pendingDeviceRecPaths)
    ..remove(remotePath);

  await ref.read(eventsProvider.notifier).updateEvent(
        latest.copyWith(
          voiceNotePaths: paths,
          pendingDeviceRecPaths: stillPending,
        ),
      );
}

/// App 请求设备开始/停止语音录音（写入 Settings 特征）
Future<bool> requestDeviceVoiceRecord(
  WidgetRef ref, {
  required bool start,
}) async {
  final ok = await ref.read(bleServiceProvider).writeRecordCommand(
        start ? 'record_start' : 'record_stop',
      );
  if (ok && start) {
    ref.read(isDeviceVoiceRecordingProvider.notifier).state = true;
  }
  if (ok && !start) {
    ref.read(isDeviceVoiceRecordingProvider.notifier).state = false;
  }
  return ok;
}
