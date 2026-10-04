import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../providers/events_provider.dart';
import '../../providers/settings_provider.dart';

/// 导出本机事件 CSV，或清空全部事件。
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(userSettingsProvider);
    final events = ref.watch(eventsProvider);
    final allow = settings.allowDataExport;

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & Export')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.ios_share),
            title: const Text('Allow export'),
            subtitle: const Text('Share a CSV of episodes stored on this phone'),
            value: allow,
            onChanged: (v) => ref
                .read(userSettingsProvider.notifier)
                .patch((s) => s.copyWith(allowDataExport: v)),
          ),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('Export episodes (CSV)'),
            subtitle: Text('${events.length} episodes on this phone'),
            enabled: allow,
            onTap: allow ? () => _export(context, ref) : null,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Delete all episodes'),
            subtitle: const Text('Removes every episode and its voice files'),
            onTap: () => _confirmDeleteAll(context, ref),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Episodes stay on this phone. Export only shares a file you choose to send.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final csv = ref.read(storageServiceProvider).exportToCsv();
    final dir = await getTemporaryDirectory();
    final name = 'symptom_tracker_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';
    final file = File('${dir.path}/$name');
    await file.writeAsString(csv);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Symptom Tracker episodes',
    );
  }

  Future<void> _confirmDeleteAll(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all episodes?'),
        content: const Text('This removes every episode and voice file on this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final events = ref.read(eventsProvider);
    for (final event in events) {
      for (final path in event.voiceNotePaths) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
    }
    await ref.read(eventsProvider.notifier).deleteAll();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All episodes deleted')),
    );
  }
}
