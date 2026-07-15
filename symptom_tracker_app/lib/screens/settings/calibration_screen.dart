import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/ble_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/calibration_service.dart';
import '../../services/ble_service.dart';

// CalibrationScreen：三步引导式力度校准向导
// 用户依次用轻/中/重三种力度按压 FSR，App 记录对应 ADC 中位数，后续映射用
class CalibrationScreen extends ConsumerStatefulWidget {
  const CalibrationScreen({super.key});

  @override
  ConsumerState<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends ConsumerState<CalibrationScreen> {
  final _service = CalibrationService();  // 校准逻辑封装在 CalibrationService 里
  int _step = 0;                          // 当前步骤（0=轻，1=中，2=重）
  bool _collecting = false;               // 是否正在采样
  int _countdown = 3;                     // 倒计时秒数
  Timer? _timer;                          // Timer = 定时器；? = 可为 null（未开始时）
  final _results = <int>[];               // 三步的 ADC 中位数结果

  // 步骤配置：标题、说明、图标
  static const _steps = [
    _StepConfig('Light Touch', 'Apply light pressure, as if gently touching', Icons.touch_app),
    _StepConfig('Medium Press', 'Apply medium pressure',                       Icons.pan_tool),
    _StepConfig('Strong Press', 'Apply firm pressure, as strong as you can',   Icons.fitness_center),
  ];

  @override
  void dispose() {
    _timer?.cancel();  // ?. = 安全调用；.cancel() = 取消定时器
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isConnected = ref.watch(bleConnectionStateProvider).valueOrNull == BleConnectionState.connected;

    return Scaffold(
      appBar: AppBar(title: const Text('Pressure Calibration')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // 进度条（当前步骤 / 总步骤）
            LinearProgressIndicator(
              value: _step / _steps.length,  // 0.0~1.0
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 8),
            Text('Step ${_step + 1} of ${_steps.length}',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 32),

            // 步骤图标
            if (_step < _steps.length) ...[
              Icon(_steps[_step].icon, size: 80, color: primary),
              const SizedBox(height: 24),
              Text(_steps[_step].title,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_steps[_step].description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.grey)),
            ],

            const Spacer(),  // Spacer = 弹性空白，把按钮推到底部

            // 采样/倒计时/结果
            if (_collecting) ...[
              Text('Sampling: $_countdown s',
                  style: TextStyle(fontSize: 24, color: primary, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Keep pressing...', style: TextStyle(color: Colors.grey)),
            ] else if (_step >= _steps.length) ...[
              // 全部完成
              Icon(Icons.check_circle, color: primary, size: 80),
              const SizedBox(height: 16),
              const Text('Calibration Complete!',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Results: ${_results.join(' / ')} ADC',
                  style: const TextStyle(color: Colors.grey)),
            ],

            const SizedBox(height: 32),

            // 按钮
            if (_step < _steps.length && !_collecting)
              FilledButton.icon(
                onPressed: isConnected ? _startSampling : null,
                icon: const Icon(Icons.radio_button_checked),
                label: const Text('Hold & Sample'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),

            if (_step >= _steps.length)
              FilledButton(
                onPressed: _saveCalibration,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: const Text('Save Calibration'),
              ),

            const SizedBox(height: 12),
            if (!isConnected)
              const Text('Connect the device to calibrate',
                  style: TextStyle(color: Colors.orange, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  void _startSampling() {
    _service.startCollecting();
    setState(() { _collecting = true; _countdown = 3; });  // 同时更新多个状态

    // 订阅实时压力数据，把 0.0~1.0 转回原始 ADC（逆向乘以 calibMax）
    StreamSubscription? sub;                               // StreamSubscription = 订阅凭证
    sub = ref.read(bleServiceProvider).bleEvents.listen((ev) {
      if (ev.type == BleEventType.pressureUpdate && ev.pressureRaw != null) {
        _service.addSample(ev.pressureRaw!);
      }
    });

    // 每秒倒计时一次，3 秒后停止采样
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {  // Timer.periodic = 周期定时器
      setState(() => _countdown--);
      if (_countdown <= 0) {
        timer.cancel();         // 取消定时器
        sub?.cancel();          // 取消 BLE 订阅
        final median = _service.stopCollectingAndGetMedian();  // 取中位数
        _results.add(median);

        setState(() {
          _collecting = false;
          _step++;              // 进入下一步
        });
      }
    });
  }

  Future<void> _saveCalibration() async {
    if (_results.length < 3) return;

    // 把三步结果存入设备设置
    await ref.read(deviceSettingsProvider.notifier).patch((s) => s.copyWith(
      calibLight:  _results[0],                         // 轻触 ADC 中位数
      calibMedium: _results[1],
      calibStrong: _results[2],
      calibMax:    (_results[2] * 1.3).round(),         // 满量程 = 重力 × 1.3（留余量）
    ));

    if (mounted) Navigator.of(context).pop();   // 保存后关闭页面
  }
}

// 不可变配置数据类（const = 编译期常量，可以 const 构造）
class _StepConfig {
  final String title;
  final String description;
  final IconData icon;
  const _StepConfig(this.title, this.description, this.icon);  // 位置参数：按顺序传，不写名字
}
