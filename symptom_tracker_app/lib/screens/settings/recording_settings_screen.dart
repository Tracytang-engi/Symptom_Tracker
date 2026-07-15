import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';

class RecordingSettingsScreen extends ConsumerWidget {
  const RecordingSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(userSettingsProvider);
    final color = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('Voice Recording')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: Icon(Icons.mic, color: color),
            title: const Text('Enable Voice Recording'),
            subtitle: const Text('Show the microphone button in episode details'),
            value: settings.showRecordingFeature,
            onChanged: (v) => ref.read(userSettingsProvider.notifier)
                .patch((s) => s.copyWith(showRecordingFeature: v)),
          ),
          SwitchListTile(
            secondary: Icon(Icons.save, color: color),
            title: const Text('Auto-save Recordings'),
            subtitle: const Text('Automatically save recording to the episode'),
            value: settings.autoSaveRecording,
            onChanged: (v) => ref.read(userSettingsProvider.notifier)
                .patch((s) => s.copyWith(autoSaveRecording: v)),
          ),
          SwitchListTile(
            secondary: Icon(Icons.storage, color: color),
            title: const Text('Keep Original File'),
            subtitle: const Text('Store raw audio file on device'),
            value: settings.keepOriginalRecording,
            onChanged: (v) => ref.read(userSettingsProvider.notifier)
                .patch((s) => s.copyWith(keepOriginalRecording: v)),
          ),
          SwitchListTile(
            secondary: Icon(Icons.label, color: color),
            title: const Text('Prompt for Tags After Recording'),
            subtitle: const Text('Show tag picker when a voice note is saved'),
            value: settings.promptTagAfterRecording,
            onChanged: (v) => ref.read(userSettingsProvider.notifier)
                .patch((s) => s.copyWith(promptTagAfterRecording: v)),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Voice note upload to cloud is not yet available.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
