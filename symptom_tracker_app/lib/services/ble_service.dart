import 'dart:async';                               // async = 异步支持；StreamController 等工具在这里
import 'dart:convert';                             // jsonDecode、utf8 编解码
import 'package:flutter_blue_plus/flutter_blue_plus.dart';  // BLE 通信库
import '../models/device_settings.dart';

// ─── BLE UUID（必须与 ESP32 ble_comm.cpp 里的定义完全一致）───────────────────

const _serviceUuid      = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';  // 主服务 UUID
const _pressureCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';  // 压力通知特征
const _eventCharUuid    = 'cba1d466-344c-4be3-ab3f-189f80dd7518';  // 事件通知特征
const _settingsCharUuid = 'a1b2c3d4-5678-9abc-def0-123456789abc';  // 设置写入特征
const _batteryServiceUuid = '0000180f-0000-1000-8000-00805f9b34fb'; // 标准电量服务
const _batteryCharUuid    = '00002a19-0000-1000-8000-00805f9b34fb'; // 电量特征
const _deviceName       = 'SymptomTracker';                         // 广播的设备名

// ─── BLE 事件类型 ─────────────────────────────────────────────────────────────

enum BleEventType { pressureUpdate, recordingStart, recordingEnd, sos }  // 来自 ESP32 的事件

class BleEvent {           // 对 ESP32 发来的数据进行封装
  final BleEventType type;
  final int? pressureRaw;  // 仅 pressureUpdate 有值；? = 可为 null
  final DateTime? timestamp;
  final int? durationMs;
  final int? peakRaw;
  final int? sampleCount;

  const BleEvent({
    required this.type,
    this.pressureRaw,
    this.timestamp,
    this.durationMs,
    this.peakRaw,
    this.sampleCount,
  });
}

// ─── 连接状态枚举 ─────────────────────────────────────────────────────────────

enum BleConnectionState { disconnected, scanning, connecting, connected }

// ─── BleService ──────────────────────────────────────────────────────────────

class BleService {
  BluetoothDevice? _device;                // 当前连接的蓝牙设备；? = 未连接时为 null
  // ignore: unused_field
  BluetoothCharacteristic? _pressureChar; // 压力数据特征（已订阅）
  // ignore: unused_field
  BluetoothCharacteristic? _eventChar;    // 事件特征（已订阅）
  BluetoothCharacteristic? _settingsChar; // 设置写入特征

  // StreamController = 可以手动向 Stream 推送数据的控制器；.broadcast() = 允许多个监听者
  final _connectionStateController = StreamController<BleConnectionState>.broadcast();
  final _bleEventController        = StreamController<BleEvent>.broadcast();
  final _batteryController         = StreamController<int>.broadcast();

  // Stream = 持续的异步数据流（类比视频流，可以 listen 订阅）
  Stream<BleConnectionState> get connectionState => _connectionStateController.stream;
  Stream<BleEvent> get bleEvents => _bleEventController.stream;
  Stream<int> get batteryLevel    => _batteryController.stream;

  BleConnectionState _currentState = BleConnectionState.disconnected;
  BleConnectionState get currentState => _currentState;  // 外部只读

  StreamSubscription? _scanSub;       // StreamSubscription = 订阅凭证，用于取消监听
  StreamSubscription? _pressureSub;
  StreamSubscription? _eventSub;
  StreamSubscription? _connectionSub;

  // ─── 扫描并连接 ───────────────────────────────────────────────────────────────

  Future<void> startScan() async {           // Future<void> = 无返回值的异步方法
    if (_currentState != BleConnectionState.disconnected) return;  // 已在扫描/连接中则直接返回

    _setState(BleConnectionState.scanning);

    // 等待蓝牙适配器开启（最多等 5 秒，否则抛出异常）
    await FlutterBluePlus.adapterState
        .where((s) => s == BluetoothAdapterState.on)   // .where() = 过滤流，只让满足条件的事件通过
        .first                                          // .first = 取第一个值（只等一次）
        .timeout(const Duration(seconds: 5), onTimeout: () {
      _setState(BleConnectionState.disconnected);
      throw Exception('Bluetooth is off');
    });

    await FlutterBluePlus.startScan(
      withNames: [_deviceName],       // 只扫描设备名为 'SymptomTracker' 的设备
      timeout: const Duration(seconds: 15),
    );

    _scanSub = FlutterBluePlus.scanResults.listen((results) async {  // .listen() = 订阅流，每次有新数据就执行
      for (final result in results) {
        if (result.device.platformName == _deviceName) {
          await FlutterBluePlus.stopScan();
          await _connectToDevice(result.device);
          break;                      // break = 找到目标设备后退出循环
        }
      }
    });

    Future.delayed(const Duration(seconds: 15), () {  // 15秒后自动停止扫描
      if (_currentState == BleConnectionState.scanning) {
        FlutterBluePlus.stopScan();
        _setState(BleConnectionState.disconnected);
      }
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _setState(BleConnectionState.connecting);
    _device = device;

    try {                             // try/catch = 捕获异常，防止程序崩溃
      await device.connect(autoConnect: false);
      _setState(BleConnectionState.connected);

      // 监听连接状态变化（断开时自动通知）
      _connectionSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _onDisconnected();
        }
      });

      await _discoverAndSubscribe(device);  // 发现服务并订阅特征
    } catch (e) {
      _setState(BleConnectionState.disconnected);
      _device = null;
    }
  }

  // 遍历 BLE 服务，找到目标特征并订阅 Notify
  Future<void> _discoverAndSubscribe(BluetoothDevice device) async {
    final services = await device.discoverServices();  // 请求设备广播的所有服务列表

    for (final service in services) {
      final sUuid = service.serviceUuid.str.toLowerCase();  // .toLowerCase() = 转小写便于比较

      if (sUuid == _serviceUuid.toLowerCase()) {            // 找到主症状服务
        for (final char in service.characteristics) {       // 遍历该服务下所有特征
          final cUuid = char.characteristicUuid.str.toLowerCase();

          if (cUuid == _pressureCharUuid.toLowerCase()) {
            _pressureChar = char;
            await char.setNotifyValue(true);                // 开启 Notify（订阅推送）
            _pressureSub = char.onValueReceived.listen(_onPressureData);
          } else if (cUuid == _eventCharUuid.toLowerCase()) {
            _eventChar = char;
            await char.setNotifyValue(true);
            _eventSub = char.onValueReceived.listen(_onEventData);
          } else if (cUuid == _settingsCharUuid.toLowerCase()) {
            _settingsChar = char;  // 找到写入特征，保存引用供 writeSettings 使用
          }
        }
      }

      if (sUuid == _batteryServiceUuid.toLowerCase()) {     // 找到标准电量服务
        for (final char in service.characteristics) {
          if (char.characteristicUuid.str.toLowerCase() == _batteryCharUuid.toLowerCase()) {
            final val = await char.read();                  // 主动读取电量（不用等 Notify）
            if (val.isNotEmpty) _batteryController.add(val[0]);  // val[0] = 电量百分比（0~100）
          }
        }
      }
    }
  }

  // ─── 数据解析 ─────────────────────────────────────────────────────────────────

  void _onPressureData(List<int> data) {
    if (data.length < 2) return;            // 至少需要 2 个字节（uint16_t）
    final raw = data[0] | (data[1] << 8);  // | = 按位或；<< = 左移；组合小端序 uint16
    _bleEventController.add(BleEvent(type: BleEventType.pressureUpdate, pressureRaw: raw));
  }

  void _onEventData(List<int> data) {
    try {
      final json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;  // 字节 → UTF8 → JSON
      final type = json['type'] as String;

      if (type == 'start') {
        _bleEventController.add(BleEvent(
          type: BleEventType.recordingStart,
          timestamp: DateTime.now(),
        ));
      } else if (type == 'end') {
        _bleEventController.add(BleEvent(
          type: BleEventType.recordingEnd,
          timestamp: DateTime.now(),
          durationMs: json['dur'] as int?,
          peakRaw: json['peak'] as int?,
          sampleCount: json['n'] as int?,
        ));
      } else if (type == 'sos') {
        // ESP32 长按 SOS 按钮：{"type":"sos","ts":millis()}
        _bleEventController.add(BleEvent(
          type: BleEventType.sos,
          timestamp: DateTime.now(),
        ));
      }
    } catch (_) {       // catch 用 _ 忽略异常对象（不需要错误内容时常见写法）
      // JSON 格式不对 → 静默忽略
    }
  }

  // ─── 写回设置到 ESP32 ──────────────────────────────────────────────────────

  Future<bool> writeSettings(DeviceSettings settings) async {
    if (_settingsChar == null || _currentState != BleConnectionState.connected) {
      return false;  // 没连接时不发送，返回 false 表示失败
    }
    try {
      final json = jsonEncode(settings.toBleCommand());  // jsonEncode = 对象转 JSON 字符串
      await _settingsChar!.write(utf8.encode(json), withoutResponse: false);  // utf8.encode = 字符串转字节列表
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── 断开连接 ─────────────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    await _scanSub?.cancel();        // ?. = 安全调用（为 null 时跳过）；.cancel() = 取消订阅
    await _pressureSub?.cancel();
    await _eventSub?.cancel();
    await _connectionSub?.cancel();
    await _device?.disconnect();
    _device = null;
    _pressureChar = null;
    _eventChar = null;
    _settingsChar = null;
    _setState(BleConnectionState.disconnected);
  }

  void _onDisconnected() {          // 连接意外断开时调用
    _pressureSub?.cancel();
    _eventSub?.cancel();
    _connectionSub?.cancel();
    _pressureChar = null;
    _eventChar = null;
    _settingsChar = null;
    _device = null;
    _setState(BleConnectionState.disconnected);
  }

  void _setState(BleConnectionState state) {
    _currentState = state;
    _connectionStateController.add(state);  // .add() = 向 Stream 推送新数据
  }

  void dispose() {               // dispose = 销毁时调用，释放资源（关闭 StreamController）
    _connectionStateController.close();
    _bleEventController.close();
    _batteryController.close();
  }
}
