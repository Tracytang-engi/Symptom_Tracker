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

