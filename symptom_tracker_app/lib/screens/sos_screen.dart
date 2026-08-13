import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/ble_provider.dart';
import '../theme/app_theme.dart';

/// Accessible Mode 底部导航的 SOS 页：大按钮一键求助
class SosScreen extends ConsumerWidget {
  const SosScreen({super.key});

  Future<void> _trigger(WidgetRef ref) async {
    final location = await ref.read(sosServiceProvider).trigger();
    ref.read(lastSosAlertProvider.notifier).state = SosAlert(
      time: DateTime.now(),
      location: location,
      fromDevice: false,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('SOS')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              const Text('🚑', style: TextStyle(fontSize: 88)),
              const SizedBox(height: 16),
              Text(
                'Need help?',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Tap the big button below.\nA notification will be sent with your location if available.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey, height: 1.4),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 72,
                child: FilledButton(
                  onPressed: () => _trigger(ref),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.sosRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('🚑', style: TextStyle(fontSize: 32)),
                      SizedBox(width: 12),
                      Text('SOS', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
