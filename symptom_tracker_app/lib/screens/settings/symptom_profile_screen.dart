import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';

class SymptomProfileScreen extends ConsumerWidget {
  const SymptomProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesProvider);
    final activeId = ref.watch(userSettingsProvider).activeProfileId;
    final color = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('Symptom Profile')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Each profile has its own settings and episode history. '
              'Tap a profile to make it active.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: profiles.length,
              itemBuilder: (_, i) {
                final profile = profiles[i];
                final isActive = profile.id == activeId;
                return ListTile(
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.healing, color: color),
                  ),
                  title: Text(profile.name,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  trailing: isActive
                      ? Icon(Icons.check_circle, color: color)
                      : const Icon(Icons.circle_outlined, color: Colors.grey),
                  onTap: () => ref
                      .read(userSettingsProvider.notifier)
                      .patch((s) => s.copyWith(activeProfileId: profile.id)),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Multiple profiles coming in a future update')),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New Profile'),
      ),
    );
  }
}
