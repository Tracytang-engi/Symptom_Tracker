import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/user_settings.dart';
import '../../providers/settings_provider.dart';

class PostEventSettingsScreen extends ConsumerWidget {
  const PostEventSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(userSettingsProvider);

    const options = {
      PostEventAction.nothing: (
        'Quiet',
        'Do nothing after an episode ends',
        Icons.notifications_off,
      ),
      PostEventAction.silentNotification: (
        'Silent Notification',
        'Show a summary notification',
        Icons.notifications,
      ),
      PostEventAction.promptTags: (
        'Ask for Tags',
        'Show tag picker when episode ends',
        Icons.label,
      ),
      PostEventAction.promptIfAbnormal: (
        'Ask if Unusual',
        'Prompt only if episode is longer or stronger than usual',
        Icons.warning_amber,
      ),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('After Episode')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Choose what happens automatically when a pain recording ends.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
          ),
          ...options.entries.map((e) {
            final (label, desc, icon) = e.value;
            return RadioListTile<PostEventAction>(
              value: e.key,
              groupValue: settings.postEventAction,
              title: Text(label),
              subtitle: Text(desc, style: const TextStyle(fontSize: 12)),
              secondary: Icon(icon),
              onChanged: (v) {
                if (v != null) {
                  ref.read(userSettingsProvider.notifier)
                      .patch((s) => s.copyWith(postEventAction: v));
                }
              },
            );
          }),
        ],
      ),
    );
  }
}
