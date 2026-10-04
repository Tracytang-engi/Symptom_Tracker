import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/user_settings.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';

// AppearanceSettingsScreen：外观设置页
// 包括主题颜色、深色模式、字体大小、简化 UI 等
class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(userSettingsProvider);  // 监听设置，变化时重建 UI
    final notifier = ref.read(userSettingsProvider.notifier);  // .notifier = 获取 Notifier 对象来调用方法

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        children: [

          // ─── 主题颜色 ───────────────────────────────────────────────────────
          _SectionHeader('Theme Color'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: AppThemeVariant.values.map((variant) {  // .map() 遍历所有枚举值
                final isSelected = settings.themeVariant == variant;
                final color = variant == AppThemeVariant.teal
                    ? const Color(0xFF66BB6A)
                    : const Color(0xFF87A878);
                return Expanded(    // Expanded = 平分父 Row 宽度
                  child: GestureDetector(   // GestureDetector = 手势监听（比 InkWell 更底层）
                    onTap: () => notifier.patch((s) => s.copyWith(themeVariant: variant)),
                    child: AnimatedContainer(   // AnimatedContainer = 属性变化时自动动画过渡
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.all(8),
                      height: 80,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? color : Colors.transparent,  // 选中时显示边框
                          width: 2.5,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(backgroundColor: color, radius: 20),  // 颜色圆圈预览
                          const SizedBox(height: 8),
                          Text(
                            variant == AppThemeVariant.teal ? 'Teal' : 'Sage',
                            style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // ─── 深色模式 ───────────────────────────────────────────────────────
          _SectionHeader('Dark Mode'),
          ...DarkModeOption.values.map((opt) {   // ... = 展开 map 结果（把 Iterable 铺平到列表）
            final label = switch (opt) {
              DarkModeOption.system => 'Follow System',
              DarkModeOption.light  => 'Always Light',
              DarkModeOption.dark   => 'Always Dark',
            };
            return RadioListTile<DarkModeOption>(   // RadioListTile = 带单选框的列表项
              title: Text(label),
              value: opt,                           // 本项的值
              groupValue: settings.darkMode,        // 当前选中的值
              onChanged: (v) {
                if (v != null) notifier.patch((s) => s.copyWith(darkMode: v));  // v != null 防止空选
              },
            );
          }),

          // ─── 字体大小 ───────────────────────────────────────────────────────
          _SectionHeader('Font Size'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Slider(                           // Slider = 滑动条
                  value: settings.fontSize.index.toDouble(),   // .index = 枚举序号（0/1/2/3）
                  min: 0,
                  max: (AppFontSize.values.length - 1).toDouble(),
                  divisions: AppFontSize.values.length - 1,    // divisions = 分成几段
                  label: settings.fontSize.label,
                  onChanged: (v) {
                    final size = AppFontSize.values[v.round()];   // .round() 对应枚举序号
                    notifier.patch((s) => s.copyWith(fontSize: size));
                  },
                ),
                Center(
                  child: Text(
                    'Preview: ${settings.fontSize.label}',
                    style: TextStyle(fontSize: 14 * settings.fontSize.scale),  // 实时预览字体
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),

          _SectionHeader('Layout'),
          SwitchListTile(
            title: const Text('Left-hand Mode'),
            subtitle: const Text('Mirror the navigation bar and home actions'),
            value: settings.leftHandMode,
            onChanged: (v) => notifier.patch((s) => s.copyWith(leftHandMode: v)),
          ),
          SwitchListTile(
            title: const Text('Live pressure'),
            subtitle: const Text('Show the gauge while the device is connected'),
            value: settings.enableContinuousPressure,
            onChanged: (v) => notifier.patch((s) => s.copyWith(enableContinuousPressure: v)),
          ),
          ListTile(
            title: const Text('Curve smoothing'),
            subtitle: Text(switch (settings.dataSmoothing) {
              DataSmoothingLevel.none => 'Off',
              DataSmoothingLevel.low => 'Low',
              DataSmoothingLevel.medium => 'Medium',
              DataSmoothingLevel.high => 'High',
            }),
            trailing: DropdownButton<DataSmoothingLevel>(
              value: settings.dataSmoothing,
              onChanged: (v) {
                if (v == null) return;
                notifier.patch((s) => s.copyWith(dataSmoothing: v));
              },
              items: const [
                DropdownMenuItem(value: DataSmoothingLevel.none, child: Text('Off')),
                DropdownMenuItem(value: DataSmoothingLevel.low, child: Text('Low')),
                DropdownMenuItem(value: DataSmoothingLevel.medium, child: Text('Medium')),
                DropdownMenuItem(value: DataSmoothingLevel.high, child: Text('High')),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.accessibility_new),
            title: const Text('Accessible Mode'),
            subtitle: const Text('Open Accessibility settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/accessibility'),
          ),
        ],
      ),
    );
  }
}

// 小段落标题
class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);  // 位置参数（不用命名）

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(text,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
            fontSize: 13,
            letterSpacing: 0.5,   // letterSpacing = 字间距
          )),
    );
  }
}
