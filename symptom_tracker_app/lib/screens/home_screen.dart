import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';   // GoRouter 的 context.push/go 扩展方法
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/pain_event.dart';
import '../providers/ble_provider.dart';
import '../providers/events_provider.dart';
import '../providers/settings_provider.dart';
import '../services/ble_service.dart';
import '../widgets/ble_status_badge.dart';
import '../widgets/pressure_gauge.dart';

// HomeScreen：App 首页
// - 顶部：BLE 连接状态徽章
// - 中间：实时压力弧形仪表盘
// - 底部：今日摘要 + 手动录入按钮 + SOS 按钮
class HomeScreen extends ConsumerStatefulWidget {  // ConsumerStatefulWidget = 有状态 + Riverpod
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final pressure   = ref.watch(realtimePressureProvider);   // 实时压力值 0.0~1.0
    final isRecording = ref.watch(isRecordingProvider);
    final todayEvents = ref.watch(todayEventsProvider);
    final latest     = ref.watch(latestEventProvider);
    final settings   = ref.watch(userSettingsProvider);
    final primary    = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Symptom Tracker'),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(child: BleStatusBadge()),
          ),
        ],
      ),
      body: SingleChildScrollView(   // SingleChildScrollView = 内容超出时允许滚动
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ─── 实时压力仪表盘 ──────────────────────────────────────────
            PressureGauge(pressure: pressure, isRecording: isRecording),
            const SizedBox(height: 8),
            Text(
              isRecording ? 'Recording in progress...' : 'Press the device to record',
              style: TextStyle(color: primary.withOpacity(0.7), fontSize: 14),
            ),
            const SizedBox(height: 24),

            // ─── 今日摘要卡片 ─────────────────────────────────────────────
            _SummaryCard(
              todayCount: todayEvents.length,
              latest: latest,
              onTap: () => context.go('/timeline'),  // context.go = GoRouter 导航（替换栈）
            ),
            const SizedBox(height: 16),

            // ─── 手机端备用录入按钮（简化 UI 时隐藏） ─────────────────────
            if (!settings.simplifiedUI) ...[    // if (...) ...[] = 条件展开多个 Widget
              _ManualEntryButton(onPressed: () => _addManualEvent(context)),
              const SizedBox(height: 16),
            ],

            // ─── BLE 连接按钮 ─────────────────────────────────────────────
            _BleConnectButton(),
            const SizedBox(height: 16),

            // ─── SOS 按钮（手机端备用；硬件长按也会走同一套告警）───────────
            _SosButton(onPressed: _triggerSos),
          ],
        ),
      ),
    );
  }

  // 手动录入一次持续约 5 秒的中等强度事件（供没有硬件时测试）
  Future<void> _addManualEvent(BuildContext context) async {
    const uuid = Uuid();
    final now = DateTime.now();
    final event = PainEvent(
      id: uuid.v4(),
      profileId: ref.read(userSettingsProvider).activeProfileId,  // ref.read = 只读一次（不监听）
      startTime: now.subtract(const Duration(seconds: 5)),
      endTime: now,
      durationMs: 5000,
      meanForce: 0.4,
      peakForce: 0.6,
      rawSamples: List.generate(250, (i) =>       // List.generate = 生成 250 个模拟采样点
          (400 * (0.6 + 0.3 * (i / 250))).round()),
      fromDevice: false,    // 标记为手机手动输入
    );
    await ref.read(eventsProvider.notifier).addEvent(event);  // 存入状态和 Hive

    if (context.mounted) {  // .mounted = 确保 Widget 还在树上（异步后必须检查）
      ScaffoldMessenger.of(context).showSnackBar(  // showSnackBar = 底部短暂提示条
        const SnackBar(content: Text('Manual event added'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _triggerSos() async {
    // 与硬件 SOS 共用同一条链路：通知 + lastSosAlertProvider（Shell 负责弹窗）
    final location = await ref.read(sosServiceProvider).trigger();
    ref.read(lastSosAlertProvider.notifier).state = SosAlert(
      time: DateTime.now(),
      location: location,
      fromDevice: false,
    );
  }
}

// ─── 子 Widget：今日摘要卡片 ──────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final int todayCount;
  final PainEvent? latest;       // ? = 可能为 null（今天还没有事件）
  final VoidCallback onTap;

  const _SummaryCard({required this.todayCount, this.latest, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final timeStr = latest != null
        ? DateFormat('HH:mm').format(latest!.startTime)  // ! = 非空断言，此处已确认 latest != null
        : '--';

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              // 数字
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Today', style: TextStyle(color: color.withOpacity(0.7), fontSize: 13)),
                  const SizedBox(height: 4),
                  RichText(  // RichText = 混合多种样式的文本（用 TextSpan 组合）
                    text: TextSpan(
                      children: [
                        TextSpan(text: '$todayCount', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: color)),
                        const TextSpan(text: ' episodes', style: TextStyle(fontSize: 14, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // 最近时间
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,  // 右对齐
                children: [
                  const Text('Last episode', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(timeStr, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: color)),
                  if (latest != null)
                    Text(latest!.peakForcePercent, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 手动录入按钮 ──────────────────────────────────────────────────────────────

class _ManualEntryButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _ManualEntryButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add_circle_outline),
      label: const Text('Manual Entry'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),  // Size.fromHeight = 固定高度，宽度自适应
      ),
    );
  }
}

// ─── BLE 连接按钮 ──────────────────────────────────────────────────────────────

class _BleConnectButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connAsync = ref.watch(bleConnectionStateProvider);
    final state = connAsync.valueOrNull ?? BleConnectionState.disconnected;  // ?? 兜底

    if (state == BleConnectionState.connected) return const SizedBox.shrink();  // 已连接时隐藏按钮

    return OutlinedButton.icon(
      onPressed: state == BleConnectionState.disconnected
          ? () => ref.read(bleServiceProvider).startScan()   // 断开状态才允许点击
          : null,   // null = 禁用按钮（变灰不可点）
      icon: Icon(state == BleConnectionState.scanning ? Icons.bluetooth_searching : Icons.bluetooth),
      label: Text(state == BleConnectionState.scanning ? 'Scanning...' : 'Connect Device'),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
    );
  }
}

// ─── SOS 按钮 ─────────────────────────────────────────────────────────────────

class _SosButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _SosButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.sos),
      label: const Text('SOS'),
      style: FilledButton.styleFrom(
        backgroundColor: Colors.red.shade400,
        minimumSize: const Size.fromHeight(52),
      ),
    );
  }
}
