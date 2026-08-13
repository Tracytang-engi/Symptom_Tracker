import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'ble_service.dart';

/// 从 ESP32 SPIFFS 经 BLE 分块下载 WAV，保存到本地后可选删除设备端文件
class DeviceFileTransfer {
  DeviceFileTransfer(
    this._ble, {
    this.onTransferChanged,
  });

  final BleService _ble;
  final void Function(String? activePath)? onTransferChanged;
  static bool _busy = false;

  static String normalizePath(String path) {
    var p = path.trim();
    if (p.isEmpty) return p;
    if (!p.startsWith('/')) p = '/$p';
    return p;
  }

  /// 下载 [remotePath]；失败自动重试。成功返回本地路径。
  Future<String?> downloadAndSave(
    String remotePath, {
    Duration timeout = const Duration(seconds: 120),
    int maxAttempts = 3,
  }) async {
    final path = normalizePath(remotePath);
    if (_ble.currentState != BleConnectionState.connected) return null;
    if (_busy) return null;
    _busy = true;
    onTransferChanged?.call(path);

    try {
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        final result = await _downloadOnce(path, timeout: timeout);
        if (result != null) return result;
        await _ble.writeFileCancel();
        if (attempt < maxAttempts) {
          await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
      return null;
    } finally {
      _busy = false;
      onTransferChanged?.call(null);
    }
  }

  Future<String?> _downloadOnce(
    String remotePath, {
    required Duration timeout,
  }) async {
    if (_ble.currentState != BleConnectionState.connected) return null;

    final packets = <int, Uint8List>{};
    final meta = Completer<BleEvent>();
    final ended = Completer<BleEvent>();
    final failed = Completer<void>();
    var highestContiguous = -1;
    var lastAcked = -1;
    var window = 4;
    Future<void> ackChain = Future<void>.value();

    bool samePath(BleEvent ev) =>
        ev.recPath != null && normalizePath(ev.recPath!) == remotePath;

    late final StreamSubscription eventSub;
    late final StreamSubscription dataSub;

    eventSub = _ble.bleEvents.listen((ev) {
      if (!samePath(ev)) return;
      if (ev.type == BleEventType.fileMeta && !meta.isCompleted) {
        window = ev.fileWindow ?? 4;
        meta.complete(ev);
      } else if (ev.type == BleEventType.fileEnd && !ended.isCompleted) {
        ended.complete(ev);
      } else if (ev.type == BleEventType.fileError && !failed.isCompleted) {
        failed.complete();
      }
    });

    dataSub = _ble.fileDataPackets.listen((packet) {
      packets.putIfAbsent(packet.sequence, () => packet.payload);

      while (packets.containsKey(highestContiguous + 1)) {
        highestContiguous++;
      }

      final shouldAck = highestContiguous >= 0 &&
          (highestContiguous - lastAcked >= window || packet.isLast);
      if (shouldAck) {
        final ackSeq = highestContiguous;
        lastAcked = ackSeq;
        ackChain = ackChain.then((_) async {
          await _ble.writeFileAck(ackSeq);
        });
      }
    });

    try {
      // 监听 DATA/STATUS 成功建立后再发 GET_FILE。
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final started = await _ble.writeFileGet(remotePath);
      if (!started) return null;

      final metadata = await Future.any<Object?>([
        meta.future,
        failed.future,
      ]).timeout(timeout, onTimeout: () => null);
      if (metadata is! BleEvent) return null;

      final endEvent = await Future.any<Object?>([
        ended.future,
        failed.future,
      ]).timeout(timeout, onTimeout: () => null);
      if (endEvent is! BleEvent) return null;
      await ackChain;

      final expectedSize = metadata.recSize ?? endEvent.recSize ?? -1;
      final expectedCrc = metadata.fileCrc ?? endEvent.fileCrc;
      if (expectedSize < 0 || expectedCrc == null) return null;

      final bytesBuilder = BytesBuilder(copy: false);
      for (var seq = 0; seq <= highestContiguous; seq++) {
        final payload = packets[seq];
        if (payload == null) return null;
        bytesBuilder.add(payload);
      }
      final bytes = bytesBuilder.takeBytes();
      if (bytes.length != expectedSize) return null;
      if (_crc32(bytes) != expectedCrc) {
        return null;
      }

      final dir = await getApplicationDocumentsDirectory();
      final voiceDir = Directory('${dir.path}/voice_notes');
      if (!await voiceDir.exists()) {
        await voiceDir.create(recursive: true);
      }
      final name = remotePath.replaceAll('/', '_');
      final localPath = '${voiceDir.path}/$name';
      await File(localPath).writeAsBytes(bytes, flush: true);

      // 只有本地 size + CRC 都通过才通知设备删除。
      final confirmed = await _ble.writeFileOk(remotePath, expectedCrc);
      if (!confirmed) return null;
      return localPath;
    } finally {
      await eventSub.cancel();
      await dataSub.cancel();
    }
  }

  static int _crc32(Uint8List data) {
    var crc = 0xffffffff;
    for (final byte in data) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
      }
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }

  /// 从设备路径解析疼痛事件 key：/rec_12345_0.wav → 12345
  static String? eventKeyFromPath(String path) {
    final m =
        RegExp(r'/rec_(\d+)(?:_\d+)?\.wav$').firstMatch(normalizePath(path));
    return m?.group(1);
  }
}
