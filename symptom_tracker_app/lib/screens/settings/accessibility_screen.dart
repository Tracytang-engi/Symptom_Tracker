import 'package:flutter/material.dart';

/// P1 stub — Accessibility settings page.
class AccessibilityScreen extends StatelessWidget {
  const AccessibilityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Accessibility')),
      body: const _ComingSoon(
        icon: Icons.accessibility_new,
        title: 'Accessibility Options',
        description:
            'High contrast mode, haptic-only mode, and screen reader '
            'enhancements will be available here in a future update.',
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

// ─── Reusable "coming soon" placeholder ──────────────────────────────────────

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
