import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../backup_config.dart';
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
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Privacy Policy',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ),
          const _PolicySection(
            title: 'Data on your device',
            body:
                'Episode records, notes, and voice recordings stay on your phone by default. '
                'The app does not read a server when it opens.',
          ),
          const _PolicySection(
            title: 'Optional account and backup',
            body:
                'Backup is optional and manual. If you create or use a backup account, your '
                'account email is sent to the backup service. When you choose Back up now, episode '
                'records and their voice recordings are uploaded and linked to your account. This '
                'information is used only to provide account, backup, and recovery features. It is '
                'not used for tracking. SOS location is not included in backups.',
          ),
          const _PolicySection(
            title: 'SOS messages',
            body:
                'The SOS feature only opens a text-message draft. You must review it and press '
                'Send yourself. If location permission is granted, your location may be placed in '
                'that draft for the recipient. Symptom Tracker is not an emergency service. In an '
                'emergency, call emergency services first or contact your guardian directly.',
          ),
          const _PolicySection(
            title: 'Health statement',
            body:
                'Symptom Tracker is a recording tool. It does not diagnose or treat any condition.',
          ),
          const _PolicySection(
            title: 'Deleting your account',
            body:
                'Go to Settings > Account & backup > Delete account. This deletes your account '
                'and backup from the server. Episode records stored on your phone are kept unless '
                'you separately delete them below.',
          ),
          if (backupApiBaseUrl.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('View privacy policy online'),
              subtitle: Text('$backupApiBaseUrl/privacy'),
              onTap: () => _openPrivacyPolicy(context),
            ),
          const Divider(height: 32),
          SwitchListTile(
            secondary: const Icon(Icons.ios_share),
            title: const Text('Allow export'),
            subtitle:
                const Text('Share a CSV of episodes stored on this phone'),
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

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    final opened = await launchUrl(
      Uri.parse('$backupApiBaseUrl/privacy'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the privacy policy.')),
      );
    }
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final csv = ref.read(storageServiceProvider).exportToCsv();
    final dir = await getTemporaryDirectory();
    final name =
        'symptom_tracker_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';
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
        content: const Text(
            'This removes every episode and voice file on this phone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
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

class _PolicySection extends StatelessWidget {
  final String title;
  final String body;

  const _PolicySection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(body),
        ],
      ),
    );
  }
}
