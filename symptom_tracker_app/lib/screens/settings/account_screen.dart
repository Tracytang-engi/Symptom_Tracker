import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/events_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/backup_service.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _backingUp = false;
  String _backupStep = 'Waking the server…';

  @override
  void initState() {
    super.initState();
    _email.text = ref.read(storageServiceProvider).accountEmail ?? '';
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  BackupService get _backup => BackupService(ref.read(storageServiceProvider));

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on BackupException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Could not reach the backup server.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _backupNow() async {
    setState(() {
      _backingUp = true;
      _backupStep = 'Preparing the backup…';
    });
    try {
      await _backup.uploadAfterWake(onStep: (step) {
        if (mounted) setState(() => _backupStep = step);
      });
      _snack('Backup saved.');
    } on BackupException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Could not reach the backup server.');
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  Future<void> _restore() async {
    final emailCtrl = TextEditingController(text: _email.text.trim());
    final passwordCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recover data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Enter your password again. The app will merge the backup into this phone.'),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            TextField(
              controller: passwordCtrl,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Recover')),
        ],
      ),
    );
    final email = emailCtrl.text.trim();
    final password = passwordCtrl.text;
    emailCtrl.dispose();
    passwordCtrl.dispose();
    if (ok != true || password.isEmpty) return;

    await _run(() async {
      await _backup.restore(email: email, password: password);
      ref.read(eventsProvider.notifier).reload();
      ref.invalidate(profilesProvider);
      ref.invalidate(tagsProvider);
      _email.text = email;
      _snack('Backup merged into this phone.');
    });
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your account and backup from the server. '
          'Episodes stored on this phone will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _run(() async {
      await _backup.deleteAccount();
      await ref.read(storageServiceProvider).clearAccount();
      _password.clear();
      if (mounted) {
        setState(() {});
        _snack(
            'Account and server backup deleted. Episodes on this phone were kept.');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final storage = ref.watch(storageServiceProvider);
    final loggedIn = (storage.accountToken ?? '').isNotEmpty;

    return PopScope(
      canPop: !_backingUp,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_backingUp ? 'Backing up' : 'Account & backup'),
          automaticallyImplyLeading: !_backingUp,
        ),
        body: _backingUp
            ? _backupLoading()
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Episodes stay on this phone. The server is only a backup. '
                    'Nothing is downloaded unless you use Recover data.',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  if (!loggedIn) ...[
                    TextField(
                      controller: _email,
                      decoration: const InputDecoration(
                          labelText: 'Email', border: OutlineInputBorder()),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      decoration: const InputDecoration(
                          labelText: 'Password', border: OutlineInputBorder()),
                      obscureText: true,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                                await _backup.register(
                                    _email.text, _password.text);
                                _password.clear();
                                _snack(
                                    'Account created. You can back up when you want.');
                              }),
                      child: const Text('Create account'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                                await _backup.login(
                                    _email.text, _password.text);
                                _password.clear();
                                _snack('Logged in.');
                              }),
                      child: const Text('Log in'),
                    ),
                  ] else ...[
                    Text('Logged in as ${storage.accountEmail ?? ''}'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy ? null : _backupNow,
                      child: const Text('Back up now'),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Backup takes about 2 minutes. The server may be asleep. '
                      'The app wakes it, then uploads again after 1 minute and after 2 minutes. '
                      'Keep this screen open until it finishes.',
                      style: TextStyle(color: Colors.grey),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                                await ref
                                    .read(storageServiceProvider)
                                    .clearAccount();
                              }),
                      child: const Text('Log out'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _deleteAccount,
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Delete account'),
                    ),
                  ],
                  const Divider(height: 32),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.restore),
                    title: const Text('Recover data'),
                    subtitle: const Text(
                        'Asks for your password again, then merges the backup'),
                    onTap: _busy ? null : _restore,
                  ),
                  if (_busy) const LinearProgressIndicator(),
                ],
              ),
      ),
    );
  }

  Widget _backupLoading() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This takes about 2 minutes. The server may be asleep. '
            'The app has sent a wake-up, then uploads again after 1 minute and after 2 minutes.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Keep this screen open.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 16),
          Center(child: Text(_backupStep)),
        ],
      ),
    );
  }
}
