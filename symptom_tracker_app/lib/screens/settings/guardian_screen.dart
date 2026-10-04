import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';

class GuardianModeScreen extends ConsumerStatefulWidget {
  const GuardianModeScreen({super.key});

  @override
  ConsumerState<GuardianModeScreen> createState() => _GuardianModeScreenState();
}

class _GuardianModeScreenState extends ConsumerState<GuardianModeScreen> {
  late final TextEditingController _name;
  late final TextEditingController _phone;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(userSettingsProvider);
    _name = TextEditingController(text: settings.guardianName);
    _phone = TextEditingController(text: settings.guardianPhone);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _save() {
    ref.read(userSettingsProvider.notifier).patch(
          (s) => s.copyWith(
            guardianName: _name.text.trim(),
            guardianPhone: _phone.text.trim(),
          ),
        );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Guardian saved')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guardian Mode')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Experimental. In an emergency, call emergency services or contact your guardian directly. Do not rely on this app.',
            style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 8),
          const Text(
            'Saving a number only opens a text with your location. The message is not sent until you tap Send.',
            style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            decoration: const InputDecoration(
              labelText: 'Phone number',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
