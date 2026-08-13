import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// SettingsScreen：设置根页面，按类别展示各设置子页面入口
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // 每组设置有一个 SectionHeader + 若干 _SettingsTile
          _SectionHeader('Device'),
          _SettingsTile(icon: Icons.vibration,   label: 'Vibration',     path: '/settings/vibration',       desc: 'Feedback mode and intensity'),
          _SettingsTile(icon: Icons.tune,         label: 'Calibration',   path: '/settings/calibration',     desc: '3-step pressure baseline'),
          _SettingsTile(icon: Icons.bluetooth,    label: 'BLE Device',    path: '/settings/ble',             desc: 'Connection & device info'),

          _SectionHeader('Recording'),
          _SettingsTile(icon: Icons.label,        label: 'Labels',        path: '/settings/labels',          desc: 'Manage event tags'),
          _SettingsTile(icon: Icons.mic,          label: 'Voice Notes',   path: '/settings/recording',       desc: 'Recording preferences'),
          _SettingsTile(icon: Icons.notifications,label: 'After Event',   path: '/settings/post-event',      desc: 'Notification and tag prompts'),

          _SectionHeader('Profile'),
          _SettingsTile(icon: Icons.healing,      label: 'Symptom Profile',path: '/settings/symptom-profile',desc: 'Manage conditions'),

          _SectionHeader('Appearance'),
          _SettingsTile(icon: Icons.palette,      label: 'Appearance',    path: '/settings/appearance',      desc: 'Theme, dark mode, font size'),
          _SettingsTile(icon: Icons.accessibility,label: 'Accessibility', path: '/settings/accessibility',   desc: 'Accessible Mode, large buttons, font size'),

          _SectionHeader('Notifications'),
          _SettingsTile(icon: Icons.schedule,     label: 'Reminders',     path: '/settings/reminders',       desc: 'Daily summaries and alerts'),

          _SectionHeader('Privacy & Safety'),
          _SettingsTile(icon: Icons.lock,         label: 'Privacy',       path: '/settings/privacy',         desc: 'Data export and storage'),
          _SettingsTile(icon: Icons.supervisor_account, label: 'Guardian Mode', path: '/settings/guardian', desc: 'Caregiver access and SOS'),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// 段落标题（只是纯文字，不可点）
class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(text,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
            fontSize: 13,
            letterSpacing: 0.5,
          )),
    );
  }
}

// 单条设置入口（点击跳转到对应子页面）
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String path;    // GoRouter 路径（绝对路径）
  final String? desc;   // 副标题；? = 可选

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.path,
    this.desc,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: desc != null ? Text(desc!, style: const TextStyle(fontSize: 12)) : null,  // desc! = 已确认非 null
      trailing: const Icon(Icons.chevron_right),   // 右箭头提示可点击
      onTap: () => context.push(path),             // context.push = 推入新路由（有返回按钮）
    );
  }
}
