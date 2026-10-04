import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../models/symptom_profile.dart';
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
          SwitchListTile(
            title: const Text('Multiple symptoms'),
            subtitle: const Text('Show a profile tag on the timeline and choose one per episode'),
            value: ref.watch(userSettingsProvider).multiProfileEnabled,
            onChanged: (v) => ref
                .read(userSettingsProvider.notifier)
                .patch((s) => s.copyWith(multiProfileEnabled: v)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Each profile has its own episode history. '
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
                  subtitle: Text(profile.themeColor, style: const TextStyle(fontSize: 12)),
                  trailing: isActive
                      ? Icon(Icons.check_circle, color: color)
                      : const Icon(Icons.circle_outlined, color: Colors.grey),
                  onTap: () => ref
                      .read(userSettingsProvider.notifier)
                      .patch((s) => s.copyWith(activeProfileId: profile.id)),
                  onLongPress: profiles.length <= 1
                      ? null
                      : () => _confirmDelete(context, ref, profile),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createProfile(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New Profile'),
      ),
    );
  }

  Future<void> _createProfile(BuildContext context, WidgetRef ref) async {
    if (ref.read(profilesProvider).length >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can keep up to 10 profiles.')),
      );
      return;
    }
    final created = await _askNameAndColor(context);
    if (created == null) return;
    final profile = SymptomProfile(
      id: const Uuid().v4(),
      name: created.$1,
      themeColor: created.$2,
    );
    await ref.read(profilesProvider.notifier).save(profile);
    await ref
        .read(userSettingsProvider.notifier)
        .patch((s) => s.copyWith(activeProfileId: profile.id));
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    SymptomProfile profile,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${profile.name}?'),
        content: const Text('Episodes in this profile stay on the phone, but this list will hide them.'),
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
    if (ok != true) return;
    await ref.read(profilesProvider.notifier).delete(profile.id);
    final active = ref.read(userSettingsProvider).activeProfileId;
    if (active == profile.id) {
      final remaining = ref.read(profilesProvider);
      if (remaining.isNotEmpty) {
        await ref
            .read(userSettingsProvider.notifier)
            .patch((s) => s.copyWith(activeProfileId: remaining.first.id));
      }
    }
  }

  Future<(String, String)?> _askNameAndColor(BuildContext context) {
    final ctrl = TextEditingController();
    var color = '#66BB6A';
    const colors = [
      '#66BB6A',
      '#42A5F5',
      '#AB47BC',
      '#EF5350',
      '#FFA726',
      '#26A69A',
      '#8D6E63',
      '#5C6BC0',
      '#EC407A',
      '#78909C',
    ];
    return showDialog<(String, String)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('New profile'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Name'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final hex in colors)
                    GestureDetector(
                      onTap: () => setLocal(() => color = hex),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Color(0xFF000000 | int.parse(hex.substring(1), radix: 16)),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color == hex ? Colors.black : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                final name = ctrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx, (name, color));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
