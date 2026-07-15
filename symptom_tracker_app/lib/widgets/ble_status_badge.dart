import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/ble_provider.dart';
import '../services/ble_service.dart';

// BleStatusBadge：显示 BLE 连接状态 + 电量的小徽章 Widget
class BleStatusBadge extends ConsumerWidget {  // ConsumerWidget = 可以 ref.watch Provider 的无状态 Widget
  const BleStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connAsync = ref.watch(bleConnectionStateProvider);  // StreamProvider 返回 AsyncValue<T>
    final battAsync = ref.watch(bleBatteryProvider);

    return connAsync.when(             // AsyncValue.when() = 根据加载/成功/错误三种状态分别处理
      data: (state) => _Badge(state: state, battery: battAsync.valueOrNull),  // .valueOrNull = 有数据就取，否则 null
      loading: () => const _Badge(state: BleConnectionState.disconnected),
      error: (_, __) => const _Badge(state: BleConnectionState.disconnected),
    );
  }
}

class _Badge extends StatelessWidget {
  final BleConnectionState state;
  final int? battery;

  const _Badge({required this.state, this.battery});

  @override
  Widget build(BuildContext context) {
    // switch 表达式（Dart 3.0）：根据状态选颜色
    final color = switch (state) {
      BleConnectionState.connected    => Colors.green,
      BleConnectionState.connecting ||
      BleConnectionState.scanning     => Colors.orange,   // || = 或，合并多个 case
      BleConnectionState.disconnected => Colors.grey,
    };

    final icon = switch (state) {
      BleConnectionState.connected    => Icons.bluetooth_connected,
      BleConnectionState.connecting ||
      BleConnectionState.scanning     => Icons.bluetooth_searching,
      BleConnectionState.disconnected => Icons.bluetooth_disabled,
    };

    final label = switch (state) {
      BleConnectionState.connected    => 'Connected',
      BleConnectionState.connecting   => 'Connecting...',
      BleConnectionState.scanning     => 'Scanning...',
      BleConnectionState.disconnected => 'Disconnected',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),  // 圆角 20 = 胶囊形状
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,  // Row 只占内容宽度
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500)),
          if (battery != null) ...[     // if (...) ...[] = 条件展开多个 Widget
            const SizedBox(width: 8),
            Icon(_batteryIcon(battery!), size: 16, color: color),  // ! = 非空断言（此处已确认非 null）
            const SizedBox(width: 2),
            Text('$battery%', style: TextStyle(color: color, fontSize: 13)),
          ]
        ],
      ),
    );
  }

  IconData _batteryIcon(int pct) {     // 根据电量百分比返回对应的电池图标
    if (pct > 80) return Icons.battery_full;
    if (pct > 50) return Icons.battery_5_bar;
    if (pct > 20) return Icons.battery_3_bar;
    return Icons.battery_1_bar;
  }
}
