import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/device_settings.dart';
import '../../providers/ble_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/ble_service.dart';

// VibrationSettingsScreen：震动设置页
// 修改完成后点 "Send to Device" 把参数写回 ESP32
class VibrationSettingsScreen extends ConsumerWidget {
  const VibrationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device  = ref.watch(deviceSettingsProvider);   // 监听设备设置
    final notifier = ref.read(deviceSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Vibration Settings')),
      body: ListView(
        children: [
          // ─── 震动模式选择 ──────────────────────────────────────────────────
          const _SectionHeader('Vibration Mode'),
          ...VibrationMode.values.map((mode) {   // ... = 展开多个 ListTile
            return RadioListTile<VibrationMode>(
              title: Text(mode.label),            // .label = 来自 extension 的 getter
              subtitle: Text(mode.description, style: const TextStyle(fontSize: 12)),
              value: mode,
              groupValue: device.vibrationMode,   // 当前选中的枚举值
              onChanged: (v) {
                if (v == null) return;
                // 根据所选模式自动设置对应的开关
                notifier.patch((s) => s.copyWith(
                  vibrationMode: v,
                  startVibration: v != VibrationMode.quiet,    // quiet 模式全关
                  endVibration:   v != VibrationMode.quiet,
                  realtimeFeedback: v == VibrationMode.realtime,  // 只有 realtime 开实时反馈
                ));
              },
            );
          }),

          // ─── 最大震动强度 ──────────────────────────────────────────────────
          const _SectionHeader('Max Vibration Power'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Slider(
                  value: device.maxVibrationPower,     // 当前值 0.0~1.0
                  onChanged: (v) => notifier.patch((s) => s.copyWith(maxVibrationPower: v)),
                  divisions: 10,                       // 分 10 格
                  label: '${(device.maxVibrationPower * 100).round()}%',
                ),
                Text('${(device.maxVibrationPower * 100).round()}%',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),

          // ─── 按压阈值 ──────────────────────────────────────────────────────
          const _SectionHeader('Press Detection Threshold'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Slider(
                  value: device.pressThreshold.toDouble(),  // int → double 供 Slider 使用
                  min: 50,
                  max: 600,
                  divisions: 55,
                  label: '${device.pressThreshold}',
                  onChanged: (v) => notifier.patch((s) => s.copyWith(pressThreshold: v.round())),
                ),
                Text('Threshold: ${device.pressThreshold}  (raw ADC)',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                const Text('Lower = more sensitive. Raise if accidental triggers.',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 12),
              ],
            ),
          ),

          // ─── 发送给设备 ────────────────────────────────────────────────────
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _SendButton(settings: device),
          ),
        ],
      ),
    );
  }
}

// 发送设置到 ESP32 的按钮（带状态反馈）
class _SendButton extends ConsumerStatefulWidget {
  final DeviceSettings settings;
  const _SendButton({required this.settings});

  @override
  ConsumerState<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends ConsumerState<_SendButton> {
  bool _sending = false;    // 正在发送中
  bool? _success;           // null = 未发送；true/false = 结果

  @override
  Widget build(BuildContext context) {
    final connAsync = ref.watch(bleConnectionStateProvider);
    final isConnected = connAsync.valueOrNull == BleConnectionState.connected;

    // 根据状态决定按钮文字
    String label = 'Send to Device';
    if (_sending)        label = 'Sending...';
    else if (_success == true)  label = 'Sent ✓';
    else if (_success == false) label = 'Failed — Retry';

    return FilledButton.icon(
      onPressed: isConnected && !_sending ? _send : null,  // 未连接或发送中则禁用
      icon: Icon(_sending ? Icons.hourglass_empty : Icons.send),
      label: Text(label),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
    );
  }

  Future<void> _send() async {
    setState(() { _sending = true; _success = null; });  // 更新状态触发 UI 重建

    final ok = await ref.read(bleServiceProvider).writeSettings(widget.settings);  // 写入 BLE
    if (mounted) {    // mounted = 异步后确认 Widget 还在树上
      setState(() { _sending = false; _success = ok; });
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(text,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
            fontSize: 13,
          )),
    );
  }
}
