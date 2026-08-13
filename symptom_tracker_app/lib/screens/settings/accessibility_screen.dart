import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';

/// Accessible Mode 设置页（主开关 + 大按钮 / 字号）
class AccessibilityScreen extends ConsumerWidget {
  const AccessibilityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(userSettingsProvider);
    final notifier = ref.read(userSettingsProvider.notifier);
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('Accessibility')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              'Accessible Mode',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: primary,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
          ),
          SwitchListTile(
            secondary: Icon(
              settings.accessibleMode ? Icons.accessibility_new : Icons.accessibility,
              color: primary,
              size: 32,
            ),
            title: const Text('Accessible Mode'),
            subtitle: const Text(
              'Larger buttons and text, simpler navigation (Home / Timeline). '
              'Home actions use a 2×2 grid; SOS is long-press.',
            ),
            value: settings.accessibleMode,
            onChanged: (v) => notifier.setAccessibleMode(v),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Touch & Text',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: primary,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Large Buttons'),
            subtitle: const Text('Taller tap targets (56–64px)'),
            value: settings.largeButtons,
            onChanged: (v) => notifier.patch((s) => s.copyWith(largeButtons: v)),
          ),
          ListTile(
            title: const Text('Font Size'),
            subtitle: Text(settings.fontSize.label),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Slider(
                  value: settings.fontSize.index.toDouble(),
                  min: 0,
                  max: (AppFontSize.values.length - 1).toDouble(),
                  divisions: AppFontSize.values.length - 1,
                  label: settings.fontSize.label,
                  onChanged: (v) {
                    final size = AppFontSize.values[v.round()];
                    notifier.patch((s) => s.copyWith(fontSize: size));
                  },
                ),
                Text(
                  'Preview: ${settings.fontSize.label}',
                  style: TextStyle(fontSize: 14 * settings.fontSize.scale),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
          if (settings.accessibleMode)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Text(
                'Tip: Turn off Accessible Mode from the Home screen button. '
                'Your previous font size and button size will be restored.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

/// P1 stub — Reminders page.
class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: const _ComingSoon(
        icon: Icons.alarm,
        title: 'Reminders',
        description:
            'Set a daily summary reminder and device low-battery alerts. '
            'Coming in a future update.',
      ),
    );
  }
}

/// P1 stub — Privacy & Export page.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & Export')),
      body: const _ComingSoon(
        icon: Icons.security,
        title: 'Privacy & Export',
        description:
            'Export episodes as CSV, delete all data, and configure '
            'privacy options. Coming in a future update.',
      ),
    );
  }
}

/// P2 stub — Guardian Mode page.
class GuardianModeScreen extends StatelessWidget {
  const GuardianModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guardian Mode')),
      body: const _ComingSoon(
        icon: Icons.family_restroom,
        title: 'Guardian Mode',
        description:
            'Share episode data with a caregiver and configure emergency '
            'contact alerts. Coming in a future update.',
      ),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _ComingSoon({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: color.withOpacity(0.4)),
            const SizedBox(height: 20),
            Text(title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(description,
                style: const TextStyle(color: Colors.grey),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
