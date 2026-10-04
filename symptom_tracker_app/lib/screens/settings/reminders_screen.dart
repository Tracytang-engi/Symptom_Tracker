import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';

class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(userSettingsProvider);
    final notifier = ref.read(userSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.today),
            title: const Text('Daily summary'),
            subtitle: const Text('A reminder each day at 20:00'),
            value: settings.dailySummaryReminder,
            onChanged: (v) => notifier.patch((s) => s.copyWith(dailySummaryReminder: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.bluetooth_disabled),
            title: const Text('Device disconnected'),
            subtitle: const Text('Notify when the device drops Bluetooth'),
            value: settings.deviceDisconnectedReminder,
            onChanged: (v) =>
                notifier.patch((s) => s.copyWith(deviceDisconnectedReminder: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.battery_alert),
            title: const Text('Low battery'),
            subtitle: const Text(
              'Only if the device reports a percentage. This board has no battery sense pin.',
            ),
            value: settings.deviceLowBatteryReminder,
            onChanged: (v) =>
                notifier.patch((s) => s.copyWith(deviceLowBatteryReminder: v)),
          ),
        ],
      ),
    );
  }
}
