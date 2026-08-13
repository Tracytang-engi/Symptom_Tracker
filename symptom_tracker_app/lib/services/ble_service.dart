import 'dart:async'; // async = 异步支持；StreamController 等工具在这里
import 'dart:convert'; // jsonDecode、utf8 编解码
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'; // BLE 通信库
import '../models/device_settings.dart';

// ─── BLE UUID（必须与 ESP32 ble_comm.cpp 里的定义完全一致）───────────────────

const _serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b'; // 主服务 UUID
const _pressureCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8'; // 压力通知特征
const _eventCharUuid = 'cba1d466-344c-4be3-ab3f-189f80dd7518'; // 事件通知特征
const _settingsCharUuid = 'a1b2c3d4-5678-9abc-def0-123456789abc'; // 设置写入特征
const _fileDataCharUuid =
    'd4e5f607-1829-4a3b-8c9d-0e1f2a3b4c5d'; // WAV 二进制 Notify
const _batteryServiceUuid = '0000180f-0000-1000-8000-00805f9b34fb'; // 标准电量服务
const _batteryCharUuid = '00002a19-0000-1000-8000-00805f9b34fb'; // 电量特征
const _deviceName = 'SymptomTracker'; // 广播的设备名

// ─── BLE 事件类型 ─────────────────────────────────────────────────────────────

enum BleEventType {
  pressureUpdate,
  recordingStart,
  recordingEnd,
  sos,
  recDone,
  fileChunk,
  fileMeta,
  fileEnd,
  fileError,
  fileDone,
  recListBegin,
  recFile,
  recListEnd,
  syncBegin,
  syncMeta,
  syncChunk,
  syncEventDone,
  syncEnd,
}

class BleEvent {
  final BleEventType type;
  final int? pressureRaw;
  final DateTime? timestamp;
  final int? durationMs;
  final int? peakRaw;
  final int? sampleCount;
  final int? deviceStartMs;
  final int? deviceEndMs;
  final int? deviceNowMs;
  final String? recPath;
  final int? recSize;
  final int? fileOffset;
  final int? fileTotal;
  final Uint8List? fileData;
  final bool? fileOk;
  final int? fileCrc;
  final int? filePacketSize;
  final int? fileWindow;
  final String? errorReason;
  final String? syncId;
  final int? syncCount;

  const BleEvent({
    required this.type,
    this.pressureRaw,
    this.timestamp,
    this.durationMs,
    this.peakRaw,
    this.sampleCount,
    this.deviceStartMs,
    this.deviceEndMs,
    this.deviceNowMs,
    this.recPath,
    this.recSize,
    this.fileOffset,
    this.fileTotal,
    this.fileData,
    this.fileOk,
    this.fileCrc,
    this.filePacketSize,
    this.fileWindow,
    this.errorReason,
    this.syncId,
    this.syncCount,
  });
}

class FileDataPacket {
  final int sequence;
  final int payloadLength;
  final int flags;
  final Uint8List payload;

  const FileDataPacket({
    required this.sequence,
    required this.payloadLength,
    required this.flags,
    required this.payload,
  });

  bool get isLast => (flags & 0x01) != 0;
}

// ─── 连接状态枚举 ─────────────────────────────────────────────────────────────

enum BleConnectionState { disconnected, scanning, connecting, connected }

// ─── BleService ──────────────────────────────────────────────────────────────

class BleService {
  BluetoothDevice? _device; // 当前连接的蓝牙设备；? = 未连接时为 null
  // ignore: unused_field
  BluetoothCharacteristic? _pressureChar; // 压力数据特征（已订阅）
  // ignore: unused_field
  BluetoothCharacteristic? _eventChar; // 事件特征（已订阅）
  BluetoothCharacteristic? _settingsChar; // 设置写入特征
  // ignore: unused_field
  BluetoothCharacteristic? _fileDataChar; // WAV 二进制通知

  // StreamController = 可以手动向 Stream 推送数据的控制器；.broadcast() = 允许多个监听者
  final _connectionStateController =
      StreamController<BleConnectionState>.broadcast();
  final _bleEventController = StreamController<BleEvent>.broadcast();
  final _batteryController = StreamController<int>.broadcast();
  final _fileDataController = StreamController<FileDataPacket>.broadcast();

  // Stream = 持续的异步数据流（类比视频流，可以 listen 订阅）
  Stream<BleConnectionState> get connectionState =>
      _connectionStateController.stream;
  Stream<BleEvent> get bleEvents => _bleEventController.stream;
  Stream<int> get batteryLevel => _batteryController.stream;
  Stream<FileDataPacket> get fileDataPackets => _fileDataController.stream;

  BleConnectionState _currentState = BleConnectionState.disconnected;
  BleConnectionState get currentState => _currentState; // 外部只读
  int _negotiatedMtu = 23;
  int get negotiatedMtu => _negotiatedMtu;

  StreamSubscription? _scanSub; // StreamSubscription = 订阅凭证，用于取消监听
  StreamSubscription? _pressureSub;
  StreamSubscription? _eventSub;
  StreamSubscription? _fileDataSub;
  StreamSubscription? _connectionSub;

  // ─── 扫描并连接 ───────────────────────────────────────────────────────────────

  Future<void> startScan() async {
    // Future<void> = 无返回值的异步方法
    if (_currentState != BleConnectionState.disconnected)
      return; // 已在扫描/连接中则直接返回

    _setState(BleConnectionState.scanning);

    // 等待蓝牙适配器开启（最多等 5 秒，否则抛出异常）
    await FlutterBluePlus.adapterState
        .where(
            (s) => s == BluetoothAdapterState.on) // .where() = 过滤流，只让满足条件的事件通过
        .first // .first = 取第一个值（只等一次）
        .timeout(const Duration(seconds: 5), onTimeout: () {
      _setState(BleConnectionState.disconnected);
      throw Exception('Bluetooth is off');
    });

    await FlutterBluePlus.startScan(
      withNames: [_deviceName], // 只扫描设备名为 'SymptomTracker' 的设备
      timeout: const Duration(seconds: 15),
    );

    _scanSub = FlutterBluePlus.scanResults.listen((results) async {
      // .listen() = 订阅流，每次有新数据就执行
      for (final result in results) {
        if (result.device.platformName == _deviceName) {
          await FlutterBluePlus.stopScan();
          await _connectToDevice(result.device);
          break; // break = 找到目标设备后退出循环
        }
      }
    });

    Future.delayed(const Duration(seconds: 15), () {
      // 15秒后自动停止扫描
      if (_currentState == BleConnectionState.scanning) {
        FlutterBluePlus.stopScan();
        _setState(BleConnectionState.disconnected);
      }
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _setState(BleConnectionState.connecting);
    _device = device;

    try {
      // try/catch = 捕获异常，防止程序崩溃
      // 不让插件自动先请求 512；由下面这一次请求完成 MTU 协商。
      await device.connect(autoConnect: false, mtu: null);
      try {
        _negotiatedMtu = await device.requestMtu(247);
      } catch (_) {
        _negotiatedMtu = device.mtuNow;
      }
      _setState(BleConnectionState.connected);

      // 监听连接状态变化（断开时自动通知）
      _connectionSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _onDisconnected();
        }
      });

      await _discoverAndSubscribe(device); // 发现服务并订阅特征
    } catch (e) {
      _setState(BleConnectionState.disconnected);
      _device = null;
    }
  }

  // 遍历 BLE 服务，找到目标特征并订阅 Notify
  Future<void> _discoverAndSubscribe(BluetoothDevice device) async {
    final services = await device.discoverServices(); // 请求设备广播的所有服务列表

    for (final service in services) {
      final sUuid =
          service.serviceUuid.str.toLowerCase(); // .toLowerCase() = 转小写便于比较

      if (sUuid == _serviceUuid.toLowerCase()) {
        // 找到主症状服务
        for (final char in service.characteristics) {
          // 遍历该服务下所有特征
          final cUuid = char.characteristicUuid.str.toLowerCase();

          if (cUuid == _pressureCharUuid.toLowerCase()) {
            _pressureChar = char;
            await char.setNotifyValue(true); // 开启 Notify（订阅推送）
            _pressureSub = char.onValueReceived.listen(_onPressureData);
          } else if (cUuid == _eventCharUuid.toLowerCase()) {
            _eventChar = char;
            await char.setNotifyValue(true);
            _eventSub = char.onValueReceived.listen(_onEventData);
          } else if (cUuid == _settingsCharUuid.toLowerCase()) {
            _settingsChar = char; // 找到写入特征，保存引用供 writeSettings 使用
          } else if (cUuid == _fileDataCharUuid.toLowerCase()) {
            _fileDataChar = char;
            await char.setNotifyValue(true);
            _fileDataSub = char.onValueReceived.listen(_onFileData);
          }
        }
      }

      if (sUuid == _batteryServiceUuid.toLowerCase()) {
        // 找到标准电量服务
        for (final char in service.characteristics) {
          if (char.characteristicUuid.str.toLowerCase() ==
              _batteryCharUuid.toLowerCase()) {
            final val = await char.read(); // 主动读取电量（不用等 Notify）
            if (val.isNotEmpty)
              _batteryController.add(val[0]); // val[0] = 电量百分比（0~100）
          }
        }
      }
    }

    // 必须在事件 Notify 订阅完成后再让 ESP32 推送离线数据。
    if (_eventChar != null && _settingsChar != null) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await writeSyncEvents();
    }
  }

  // ─── 数据解析 ─────────────────────────────────────────────────────────────────

  void _onPressureData(List<int> data) {
    if (data.length < 2) return; // 至少需要 2 个字节（uint16_t）
    final raw = data[0] | (data[1] << 8); // | = 按位或；<< = 左移；组合小端序 uint16
    _bleEventController
        .add(BleEvent(type: BleEventType.pressureUpdate, pressureRaw: raw));
  }

  void _onFileData(List<int> data) {
    if (data.length < 8) return;
    final bd = ByteData.sublistView(Uint8List.fromList(data));
    final seq = bd.getUint32(0, Endian.little);
    final len = bd.getUint16(4, Endian.little);
    final flags = data[6];
    if (len > data.length - 8) return;
    _fileDataController.add(FileDataPacket(
      sequence: seq,
      payloadLength: len,
      flags: flags,
      payload: Uint8List.fromList(data.sublist(8, 8 + len)),
    ));
  }

  void _onEventData(List<int> data) {
    try {
      final json = jsonDecode(utf8.decode(data))
          as Map<String, dynamic>; // 字节 → UTF8 → JSON
      final type = json['type'] as String;

      if (type == 'start') {
        _bleEventController.add(BleEvent(
          type: BleEventType.recordingStart,
          timestamp: DateTime.now(),
          deviceStartMs: json['t'] as int?,
        ));
      } else if (type == 'end') {
        _bleEventController.add(BleEvent(
          type: BleEventType.recordingEnd,
          timestamp: DateTime.now(),
          durationMs: json['dur'] as int?,
          peakRaw: json['peak'] as int?,
          sampleCount: json['n'] as int?,
          deviceStartMs: json['t'] as int?,
        ));
      } else if (type == 'sos') {
        // ESP32 长按 SOS 按钮：{"type":"sos","ts":millis()}
        _bleEventController.add(BleEvent(
          type: BleEventType.sos,
          timestamp: DateTime.now(),
        ));
      } else if (type == 'rec_done') {
        // 设备语音录完：{"type":"rec_done","path":"/rec_x.wav","dur":ms,"size":bytes}
        _bleEventController.add(BleEvent(
          type: BleEventType.recDone,
          timestamp: DateTime.now(),
          durationMs: json['dur'] as int?,
          recPath: json['path'] as String?,
          recSize: json['size'] as int?,
        ));
      } else if (type == 'file_chunk') {
        final b64 = json['data'] as String?;
        Uint8List? bytes;
        if (b64 != null && b64.isNotEmpty) {
          try {
            bytes = Uint8List.fromList(base64Decode(b64));
          } catch (_) {}
        }
        _bleEventController.add(BleEvent(
          type: BleEventType.fileChunk,
          recPath: json['path'] as String?,
          fileOffset: json['off'] as int?,
          fileTotal: json['total'] as int?,
          fileData: bytes,
        ));
      } else if (type == 'file_done') {
        _bleEventController.add(BleEvent(
          type: BleEventType.fileDone,
          recPath: json['path'] as String?,
          fileOk: json['ok'] as bool? ?? false,
        ));
      } else if (type == 'file_meta') {
        _bleEventController.add(BleEvent(
          type: BleEventType.fileMeta,
          recPath: json['path'] as String?,
          recSize: json['size'] as int?,
          fileCrc: json['crc'] as int?,
          filePacketSize: json['packet'] as int?,
          fileWindow: json['window'] as int?,
        ));
      } else if (type == 'file_end') {
        _bleEventController.add(BleEvent(
          type: BleEventType.fileEnd,
          recPath: json['path'] as String?,
          recSize: json['size'] as int?,
          fileCrc: json['crc'] as int?,
        ));
      } else if (type == 'file_error') {
        _bleEventController.add(BleEvent(
          type: BleEventType.fileError,
          recPath: json['path'] as String?,
          errorReason: json['reason'] as String?,
        ));
      } else if (type == 'rec_list_begin') {
        _bleEventController.add(BleEvent(
          type: BleEventType.recListBegin,
          syncCount: json['n'] as int?,
        ));
      } else if (type == 'rec_file') {
        _bleEventController.add(BleEvent(
          type: BleEventType.recFile,
          recPath: json['path'] as String?,
          recSize: json['size'] as int?,
        ));
      } else if (type == 'rec_list_end') {
        _bleEventController.add(const BleEvent(type: BleEventType.recListEnd));
      } else if (type == 'sync_begin') {
        _bleEventController.add(BleEvent(
          type: BleEventType.syncBegin,
          syncCount: json['n'] as int?,
        ));
      } else if (type == 'sync_meta') {
        _bleEventController.add(BleEvent(
          type: BleEventType.syncMeta,
          syncId: json['id'] as String?,
          recPath: json['path'] as String?,
          deviceStartMs: json['t'] as int?,
          deviceEndMs: json['end'] as int?,
          deviceNowMs: json['now'] as int?,
          durationMs: json['dur'] as int?,
          peakRaw: json['peak'] as int?,
          sampleCount: json['n'] as int?,
        ));
      } else if (type == 'sync_chunk') {
        final b64 = json['data'] as String?;
        Uint8List? bytes;
        if (b64 != null && b64.isNotEmpty) {
          try {
            bytes = Uint8List.fromList(base64Decode(b64));
          } catch (_) {}
        }
        _bleEventController.add(BleEvent(
          type: BleEventType.syncChunk,
          syncId: json['id'] as String?,
          fileOffset: json['off'] as int?,
          fileTotal: json['total'] as int?,
          fileData: bytes,
        ));
      } else if (type == 'sync_event_done') {
        _bleEventController.add(BleEvent(
          type: BleEventType.syncEventDone,
          syncId: json['id'] as String?,
          recPath: json['path'] as String?,
          fileOk: json['ok'] as bool? ?? true,
        ));
      } else if (type == 'sync_end') {
        _bleEventController.add(const BleEvent(type: BleEventType.syncEnd));
      }
    } catch (_) {
      // catch 用 _ 忽略异常对象（不需要错误内容时常见写法）
      // JSON 格式不对 → 静默忽略
    }
  }

  // ─── 写回设置到 ESP32 ──────────────────────────────────────────────────────

  Future<bool> writeSettings(DeviceSettings settings) async {
    if (_settingsChar == null ||
        _currentState != BleConnectionState.connected) {
      return false; // 没连接时不发送，返回 false 表示失败
    }
    try {
      final json =
          jsonEncode(settings.toBleCommand()); // jsonEncode = 对象转 JSON 字符串
      await _settingsChar!.write(utf8.encode(json),
          withoutResponse: false); // utf8.encode = 字符串转字节列表
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 向 ESP32 发送录音控制：record_start / record_stop
  Future<bool> writeRecordCommand(String cmd) async {
    if (_settingsChar == null ||
        _currentState != BleConnectionState.connected) {
      return false;
    }
    if (cmd != 'record_start' && cmd != 'record_stop') return false;
    try {
      final json = jsonEncode({'cmd': cmd});
      await _settingsChar!.write(utf8.encode(json), withoutResponse: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> writeFileGet(String path) async {
    if (_settingsChar == null ||
        _currentState != BleConnectionState.connected) {
      return false;
    }
    try {
      // ATT notification 可用长度 = MTU - 3；固件上限 244、下限 20。
      final packetSize = (_negotiatedMtu - 3).clamp(20, 244);
      final json = jsonEncode({
        'cmd': 'file_get',
        'path': path,
        'packet': packetSize,
      });
      await _settingsChar!.write(utf8.encode(json), withoutResponse: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> writeFileAck(int sequence) =>
      _writeFileControl({'cmd': 'file_ack', 'seq': sequence});

  Future<bool> writeFileOk(String path, int crc) =>
      _writeFileControl({'cmd': 'file_ok', 'path': path, 'crc': crc});

  Future<bool> writeFileCancel() => _writeFileControl({'cmd': 'file_cancel'});

  Future<bool> _writeFileControl(Map<String, dynamic> command) async {
    if (_settingsChar == null ||
        _currentState != BleConnectionState.connected) {
      return false;
    }
    try {
      await _settingsChar!.write(
        utf8.encode(jsonEncode(command)),
        withoutResponse: false,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 清空设备上全部录音（腾 SPIFFS 空间；未下载的会丢失）
  Future<bool> writeFileClear() async {
    if (_settingsChar == null ||
        _currentState != BleConnectionState.connected) {
      return false;
    }
    try {
      final json = jsonEncode({'cmd': 'file_clear'});
      await _settingsChar!.write(utf8.encode(json), withoutResponse: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> writeSyncEvents() async {
    if (_settingsChar == null ||
        _currentState != BleConnectionState.connected) {
      return false;
    }
    try {
      final json = jsonEncode({'cmd': 'sync_events'});
      await _settingsChar!.write(utf8.encode(json), withoutResponse: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> writeFileList() => _writeFileControl({'cmd': 'file_list'});

  Future<bool> writeSyncAck({String? path, String? id}) async {
    if (_settingsChar == null ||
        _currentState != BleConnectionState.connected) {
      return false;
    }
    try {
      final map = <String, dynamic>{'cmd': 'sync_ack'};
      if (path != null) map['path'] = path;
      if (id != null) map['id'] = id;
      await _settingsChar!
          .write(utf8.encode(jsonEncode(map)), withoutResponse: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── 断开连接 ─────────────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    await _scanSub?.cancel(); // ?. = 安全调用（为 null 时跳过）；.cancel() = 取消订阅
    await _pressureSub?.cancel();
    await _eventSub?.cancel();
    await _fileDataSub?.cancel();
    await _connectionSub?.cancel();
    await _device?.disconnect();
    _device = null;
    _pressureChar = null;
    _eventChar = null;
    _settingsChar = null;
    _fileDataChar = null;
    _setState(BleConnectionState.disconnected);
  }

  void _onDisconnected() {
    // 连接意外断开时调用
    _pressureSub?.cancel();
    _eventSub?.cancel();
    _fileDataSub?.cancel();
    _connectionSub?.cancel();
    _pressureChar = null;
    _eventChar = null;
    _settingsChar = null;
    _fileDataChar = null;
    _device = null;
    _setState(BleConnectionState.disconnected);
  }

  void _setState(BleConnectionState state) {
    _currentState = state;
    _connectionStateController.add(state); // .add() = 向 Stream 推送新数据
  }

  void dispose() {
    // dispose = 销毁时调用，释放资源（关闭 StreamController）
    _connectionStateController.close();
    _bleEventController.close();
    _batteryController.close();
    _fileDataController.close();
  }
}
