import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/ble_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/ble_service.dart';

// BleSettingsScreen：BLE 设备连接信息页
// 显示当前连接状态、电量，以及连接/断开操作
class BleSettingsScreen extends ConsumerWidget {
  const BleSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // AsyncValue<T> = Riverpod 对异步状态的封装（loading/data/error 三态）
    final connAsync    = ref.watch(bleConnectionStateProvider);
    final battAsync    = ref.watch(bleBatteryProvider);
    final deviceSettings = ref.watch(deviceSettingsProvider);
    final bleService   = ref.read(bleServiceProvider);  // ref.read = 只读一次，不监听

    final connState = connAsync.valueOrNull ?? BleConnectionState.disconnected;
    final battery   = battAsync.valueOrNull;   // 可能为 null（未连接时没有电量数据）

    return Scaffold(
      appBar: AppBar(title: const Text('BLE Device')),
      body: ListView(
        children: [

          // ─── 连接状态 ──────────────────────────────────────────────────────
          const _SectionHeader('Connection'),
          _InfoTile(
            label: 'Status',
            value: switch (connState) {   // switch 表达式（Dart 3.0）
              BleConnectionState.connected    => 'Connected',
              BleConnectionState.connecting   => 'Connecting...',
              BleConnectionState.scanning     => 'Scanning...',
              BleConnectionState.disconnected => 'Disconnected',
            },
            icon: switch (connState) {
              BleConnectionState.connected    => Icons.bluetooth_connected,
              BleConnectionState.connecting ||
              BleConnectionState.scanning     => Icons.bluetooth_searching,
              BleConnectionState.disconnected => Icons.bluetooth_disabled,
            },
          ),

          if (battery != null)
            _InfoTile(label: 'Battery', value: '$battery%', icon: Icons.battery_5_bar),

          // ─── 操作按钮 ──────────────────────────────────────────────────────
          const _SectionHeader('Actions'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                // 扫描/连接按钮（只在断开时显示）
                if (connState == BleConnectionState.disconnected)
                  FilledButton.icon(
                    onPressed: bleService.startScan,  // 传方法引用（不用写 ()）
                    icon: const Icon(Icons.bluetooth_searching),
                    label: const Text('Scan & Connect'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  ),

                // 断开按钮（只在已连接时显示）
                if (connState == BleConnectionState.connected) ...[
                  OutlinedButton.icon(
                    onPressed: bleService.disconnect,
                    icon: const Icon(Icons.bluetooth_disabled),
                    label: const Text('Disconnect'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  ),
                ],
              ],
            ),
          ),

          // ─── 设备配置摘要 ──────────────────────────────────────────────────
          const _SectionHeader('Device Config'),
          _InfoTile(label: 'Sampling Rate', value: '${deviceSettings.samplingRateHz} Hz'),
          _InfoTile(label: 'Press Threshold', value: '${deviceSettings.pressThreshold} (ADC)'),
          _InfoTile(label: 'Calibrated', value: deviceSettings.isCalibrated ? 'Yes' : 'Not yet'),
        ],
      ),
    );
  }
}

// 信息展示行（只读，不可交互）
class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;   // ? = 可选图标

  const _InfoTile({required this.label, required this.value, this.icon});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: icon != null ? Icon(icon, color: Theme.of(context).colorScheme.primary) : null,
      title: Text(label),
      trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),  // 右侧显示值
    );
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
