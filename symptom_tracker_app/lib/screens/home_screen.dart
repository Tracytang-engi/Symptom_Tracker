import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/pain_event.dart';
import '../providers/ble_provider.dart';
import '../providers/events_provider.dart';
import '../providers/settings_provider.dart';
import '../services/ble_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ble_status_badge.dart';
import '../widgets/pressure_gauge.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final pressure = ref.watch(realtimePressureProvider);
    final isRecording = ref.watch(isRecordingProvider);
    final todayEvents = ref.watch(todayEventsProvider);
    final latest = ref.watch(latestEventProvider);
    final settings = ref.watch(userSettingsProvider);
    final primary = Theme.of(context).colorScheme.primary;
    final accessible = settings.accessibleMode;
    final conn = ref.watch(bleConnectionStateProvider).valueOrNull ??
        BleConnectionState.disconnected;

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
      body: SingleChildScrollView(
        padding: EdgeInsets.all(accessible ? 20 : 20),
        child: Column(
          children: [
            PressureGauge(
              pressure: pressure,
              isRecording: isRecording,
              size: accessible ? 220 : 200,
            ),
            const SizedBox(height: 8),
            Text(
              isRecording ? 'Recording in progress...' : 'Press the device to record',
              style: TextStyle(
                color: primary.withOpacity(0.7),
                fontSize: accessible ? 16 : 14,
              ),
            ),
            const SizedBox(height: 20),
            _SummaryCard(
              todayCount: todayEvents.length,
              latest: latest,
              onTap: () => context.go('/timeline'),
              large: accessible,
            ),
            const SizedBox(height: 20),

            if (accessible)
              _AccessibleActionGrid(
                accessibleOn: settings.accessibleMode,
                bleState: conn,
                onToggleAccessible: () => ref
                    .read(userSettingsProvider.notifier)
                    .setAccessibleMode(!settings.accessibleMode),
                onManualEntry: () => _addManualEvent(context),
                onConnect: conn == BleConnectionState.disconnected
                    ? () => ref.read(bleServiceProvider).startScan()
                    : null,
                onSosLongPress: _triggerSos,
              )
            else ...[
              _AccessibleModeButton(
                enabled: false,
                onPressed: () =>
                    ref.read(userSettingsProvider.notifier).setAccessibleMode(true),
              ),
              const SizedBox(height: 16),
              _ManualEntryButton(onPressed: () => _addManualEvent(context)),
              const SizedBox(height: 16),
              _BleConnectButton(),
              const SizedBox(height: 16),
              _SosButton(onLongPress: _triggerSos),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _addManualEvent(BuildContext context) async {
    const uuid = Uuid();
    final now = DateTime.now();
    final event = PainEvent(
      id: uuid.v4(),
      profileId: ref.read(userSettingsProvider).activeProfileId,
      startTime: now.subtract(const Duration(seconds: 5)),
      endTime: now,
      durationMs: 5000,
      meanForce: 0.4,
      peakForce: 0.6,
      rawSamples: List.generate(
          250, (i) => (400 * (0.6 + 0.3 * (i / 250))).round()),
      fromDevice: false,
    );
    await ref.read(eventsProvider.notifier).addEvent(event);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Manual event added'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _triggerSos() async {
    HapticFeedback.heavyImpact();
    final location = await ref.read(sosServiceProvider).trigger();
    ref.read(lastSosAlertProvider.notifier).state = SosAlert(
      time: DateTime.now(),
      location: location,
      fromDevice: false,
    );
  }
}

/// Accessible：2×2 正方形动作格
class _AccessibleActionGrid extends StatelessWidget {
  final bool accessibleOn;
  final BleConnectionState bleState;
  final VoidCallback onToggleAccessible;
  final VoidCallback onManualEntry;
  final VoidCallback? onConnect;
  final VoidCallback onSosLongPress;

  const _AccessibleActionGrid({
    required this.accessibleOn,
    required this.bleState,
    required this.onToggleAccessible,
    required this.onManualEntry,
    required this.onConnect,
    required this.onSosLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scanning = bleState == BleConnectionState.scanning ||
        bleState == BleConnectionState.connecting;
    final connected = bleState == BleConnectionState.connected;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: 1,
      children: [
        _SquareTile(
          icon: Icons.accessibility_new,
          label: accessibleOn ? 'Accessible\nON' : 'Accessible',
          color: AppColors.navHome,
          filled: accessibleOn,
          onTap: onToggleAccessible,
        ),
        _SquareTile(
          icon: Icons.edit_note,
          label: 'Manual\nEntry',
          color: const Color(0xFFEF6C00),
          onTap: onManualEntry,
        ),
        _SquareTile(
          icon: scanning
              ? Icons.bluetooth_searching
              : (connected ? Icons.bluetooth_connected : Icons.bluetooth),
          label: scanning
              ? 'Scanning…'
              : (connected ? 'Connected' : 'Connect\nDevice'),
          color: AppColors.navTimeline,
          onTap: connected ? null : onConnect,
        ),
        _SquareTile(
          // Material Icons.ambulance/emergency 在 release 字体裁剪后会显示成 *
          emoji: '🚑',
          label: 'SOS\nHold',
          color: AppColors.sosRed,
          filled: true,
          onTap: null,
          onLongPress: onSosLongPress,
          hint: 'Long press',
        ),
      ],
    );
  }
}

class _SquareTile extends StatelessWidget {
  final IconData? icon;
  final String? emoji;
  final String label;
  final Color color;
  final bool filled;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? hint;

  const _SquareTile({
    this.icon,
    this.emoji,
    required this.label,
    required this.color,
    this.filled = false,
    this.onTap,
    this.onLongPress,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null || onLongPress != null;
    final bg = filled ? color : color.withOpacity(0.12);
    final fg = filled ? Colors.white : color;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                onLongPress!();
              },
        borderRadius: BorderRadius.circular(20),
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (emoji != null)
                  Text(emoji!, style: const TextStyle(fontSize: 48))
                else
                  Icon(icon, size: 52, color: fg),
                const SizedBox(height: 10),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: fg,
                    height: 1.15,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    hint!,
                    style: TextStyle(
                      fontSize: 12,
                      color: fg.withOpacity(0.85),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int todayCount;
  final PainEvent? latest;
  final VoidCallback onTap;
  final bool large;

  const _SummaryCard({
    required this.todayCount,
    this.latest,
    required this.onTap,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final timeStr = latest != null
        ? DateFormat('HH:mm').format(latest!.startTime)
        : '--';

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.all(large ? 24 : 20),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Today',
                      style: TextStyle(
                          color: color.withOpacity(0.7),
                          fontSize: large ? 16 : 13)),
                  const SizedBox(height: 4),
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '$todayCount',
                          style: TextStyle(
                            fontSize: large ? 44 : 36,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        TextSpan(
                          text: ' episodes',
                          style: TextStyle(
                            fontSize: large ? 16 : 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Last episode',
                      style: TextStyle(
                          color: Colors.grey, fontSize: large ? 14 : 12)),
                  const SizedBox(height: 4),
                  Text(timeStr,
                      style: TextStyle(
                          fontSize: large ? 24 : 20,
                          fontWeight: FontWeight.w600,
                          color: color)),
                  if (latest != null)
                    Text(latest!.peakForcePercent,
                        style: TextStyle(
                            fontSize: large ? 14 : 12, color: Colors.grey)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccessibleModeButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const _AccessibleModeButton({required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(enabled ? Icons.accessibility_new : Icons.accessibility, size: 28),
      label: Text(enabled ? 'Accessible Mode: ON' : 'Accessible Mode'),
      style: OutlinedButton.styleFrom(
        foregroundColor: enabled ? primary : null,
        side: BorderSide(
          color: enabled ? primary : Theme.of(context).dividerColor,
          width: enabled ? 2.5 : 1,
        ),
        backgroundColor: enabled ? primary.withOpacity(0.1) : null,
      ),
    );
  }
}

class _ManualEntryButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _ManualEntryButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add_circle_outline),
      label: const Text('Manual Entry'),
    );
  }
}

class _BleConnectButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connAsync = ref.watch(bleConnectionStateProvider);
    final state = connAsync.valueOrNull ?? BleConnectionState.disconnected;
    final scanning = state == BleConnectionState.scanning ||
        state == BleConnectionState.connecting;
    final connected = state == BleConnectionState.connected;

    return OutlinedButton.icon(
      onPressed: state == BleConnectionState.disconnected
          ? () => ref.read(bleServiceProvider).startScan()
          : null,
      icon: Icon(
        scanning
            ? Icons.bluetooth_searching
            : (connected ? Icons.bluetooth_connected : Icons.bluetooth),
        color: AppColors.navTimeline,
      ),
      label: Text(
        scanning
            ? 'Scanning...'
            : (connected ? 'Connected' : 'Connect Device'),
      ),
    );
  }
}

/// 普通模式 SOS：短按无效提示，长按触发（与 Accessible 一致）
class _SosButton extends StatelessWidget {
  final VoidCallback onLongPress;
  const _SosButton({required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hold the SOS button to trigger'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      onLongPress: () {
        HapticFeedback.heavyImpact();
        onLongPress();
      },
      icon: const Text('🚨', style: TextStyle(fontSize: 22)),
      label: const Text('SOS (hold)'),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.sosRed,
        foregroundColor: Colors.white,
      ),
    );
  }
}
