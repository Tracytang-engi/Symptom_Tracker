import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';             // uuid 库：生成全球唯一 ID
import '../models/pain_event.dart';
import '../services/ble_service.dart';
import '../services/calibration_service.dart';
import '../services/sos_service.dart';
import 'events_provider.dart';
import 'settings_provider.dart';

// ─── BleService 单例 ──────────────────────────────────────────────────────────

// Provider = 提供一个共享的 BleService 实例；ref.onDispose = 销毁时自动调用 dispose()
final bleServiceProvider = Provider<BleService>((ref) {
  final service = BleService();
  ref.onDispose(service.dispose);  // 当 ProviderScope 销毁时，自动关闭 StreamController
  return service;
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

// ─── 连接状态 Stream ──────────────────────────────────────────────────────────

// StreamProvider = 把 Stream 包装成 Provider，UI 可以 .watch() 监听
final bleConnectionStateProvider =
    StreamProvider<BleConnectionState>((ref) {
  final service = ref.watch(bleServiceProvider);
  return service.connectionState;  // 返回 BleService 里的 Stream
});

// ─── 电量 ─────────────────────────────────────────────────────────────────────

final bleBatteryProvider = StreamProvider<int>((ref) {
  final service = ref.watch(bleServiceProvider);
  return service.batteryLevel;
});

// ─── 实时压力（0.0~1.0）──────────────────────────────────────────────────────

// StateProvider = 最简单的可修改状态；其他 provider 或 UI 可以读写
final realtimePressureProvider = StateProvider<double>((ref) => 0.0);

// ─── 是否正在记录 ─────────────────────────────────────────────────────────────

final isRecordingProvider = StateProvider<bool>((ref) => false);

// ─── 事件积累器（私有辅助类）───────────────────────────────────────────────────

class _EventAccumulator {
  DateTime? startTime;        // ? = 未开始时为 null
  final List<int> rawSamples = [];  // 本次事件的原始 ADC 采样序列
}

// ─── BLE 事件监听 Provider ────────────────────────────────────────────────────

// 这个 Provider 的返回值是 void（不关心返回值），只是为了触发副作用（监听 BLE 事件）
// 在 HomeScreen.initState 里用 ref.read(bleEventListenerProvider) 激活
final bleEventListenerProvider = Provider<void>((ref) {
  final service = ref.watch(bleServiceProvider);
  final accumulator = _EventAccumulator();  // 在 Provider 内部保存积累中的事件数据
  const uuid = Uuid();                       // 用于生成唯一 ID

  StreamSubscription? sub;  // sub = 订阅凭证，销毁时取消

  sub = service.bleEvents.listen((event) {  // 监听所有 BLE 事件
    final deviceSettings = ref.read(deviceSettingsProvider);  // ref.read = 读取一次，不监听变化

    switch (event.type) {
      case BleEventType.pressureUpdate:
        final raw = event.pressureRaw ?? 0;
        final relative = CalibrationService.mapToRelative(raw, deviceSettings);
        ref.read(realtimePressureProvider.notifier).state = relative;  // .notifier.state = 修改 StateProvider 的值

        if (ref.read(isRecordingProvider)) {   // 记录中才追加采样
          accumulator.rawSamples.add(raw);
        }
        break;

      case BleEventType.recordingStart:
        accumulator.startTime = event.timestamp ?? DateTime.now();
        accumulator.rawSamples.clear();
        ref.read(isRecordingProvider.notifier).state = true;  // 更新"记录中"状态
        break;

      case BleEventType.recordingEnd:
        ref.read(isRecordingProvider.notifier).state = false;
        ref.read(realtimePressureProvider.notifier).state = 0.0;  // 压力清零

        final start = accumulator.startTime ?? DateTime.now();
        final end = DateTime.now();
        final durationMs = event.durationMs ?? end.difference(start).inMilliseconds;  // .difference().inMilliseconds = 两时间之差（毫秒）
        final samples = List<int>.from(accumulator.rawSamples);  // List.from() = 复制列表（避免共享引用）

        final mean = CalibrationService.computeMean(samples, deviceSettings);
        final peak = event.peakRaw != null
            ? CalibrationService.mapToRelative(event.peakRaw!, deviceSettings)
            : CalibrationService.computePeak(samples, deviceSettings);

        final activeProfileId = ref.read(userSettingsProvider).activeProfileId;

        // 构造完整的 PainEvent 对象并保存
        final painEvent = PainEvent(
          id: uuid.v4(),            // uuid.v4() = 生成 v4 随机 UUID 字符串
          profileId: activeProfileId,
          startTime: start,
          endTime: end,
          durationMs: durationMs,
          meanForce: mean,
          peakForce: peak,
          rawSamples: samples,
          fromDevice: true,         // 来自硬件按压
        );

        ref.read(eventsProvider.notifier).addEvent(painEvent);  // 存入状态 + Hive
        accumulator.startTime = null;
        accumulator.rawSamples.clear();
        break;

      case BleEventType.sos:
        // 硬件长按 SOS：发通知 + 更新 UI 告警状态（异步，不阻塞 BLE 监听）
        unawaited(() async {
          final loc = await ref.read(sosServiceProvider).trigger();
          ref.read(lastSosAlertProvider.notifier).state = SosAlert(
            time: DateTime.now(),
            location: loc,
            fromDevice: true,
          );
        }());
        break;
    }
  });

  ref.onDispose(() => sub?.cancel());  // Provider 销毁时取消 BLE 监听
});
