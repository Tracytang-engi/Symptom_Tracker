import 'package:flutter/material.dart';
import 'package:intl/intl.dart';            // intl = 国际化/日期格式化库
import '../models/pain_event.dart';
import '../models/symptom_profile.dart';

// PainEventCard：时间线列表里的一张事件卡片
class PainEventCard extends StatelessWidget {
  final PainEvent event;
  final VoidCallback? onTap;  // VoidCallback = 无参无返回值函数；? = 可为 null（不可点）
  final SymptomProfile? profile;
  final bool showProfileTag;

  const PainEventCard({
    super.key,
    required this.event,
    this.onTap,
    this.profile,
    this.showProfileTag = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final timeFormat = DateFormat('HH:mm');  // DateFormat = 日期格式化；'HH:mm' = 24小时制

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(            // InkWell = 给子 Widget 添加点击水波纹效果
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,  // 子 Widget 左对齐
            children: [
              // 顶部行：时间 + 峰值标签
              Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: color),
                  const SizedBox(width: 6),
                  Text(
                    timeFormat.format(event.startTime),  // .format() = 把 DateTime 格式化为字符串
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  if (showProfileTag && profile != null) ...[
                    const SizedBox(width: 8),
                    _ProfileTag(profile: profile!),
                  ],
                  if (event.voiceNotePaths.isNotEmpty ||
                      event.pendingDeviceRecPaths.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.mic, size: 16, color: color),
                  ],
                  const Spacer(),  // Spacer = 占满剩余空间，把峰值推到右边
                  _ForceChip(label: 'Peak ${event.peakForcePercent}', force: event.peakForce, color: color),
                ],
              ),
              const SizedBox(height: 10),

              // 峰值进度条
              ClipRRect(                     // ClipRRect = 把子 Widget 裁剪为圆角矩形
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: event.peakForce,    // 0.0~1.0 对应 0%~100%
                  minHeight: 6,
                  backgroundColor: color.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation(color),  // AlwaysStoppedAnimation = 静止颜色（不动画）
                ),
              ),
              const SizedBox(height: 10),

              // 底部行：时长、平均力、来源徽标
              Row(
                children: [
                  _StatItem(icon: Icons.timer, label: event.formattedDuration),
                  const SizedBox(width: 16),
                  _StatItem(icon: Icons.show_chart, label: 'Avg ${event.meanForcePercent}'),
                  const Spacer(),
                  if (!event.fromDevice)     // 手动录入时显示 "Manual" 标签
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Manual',
                          style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w500)),
                    ),
                ],
              ),

              // 标签芯片（如果有的话）
              if (event.tags.isNotEmpty) ...[   // isNotEmpty = 非空；...[] = 展开多个 Widget
                const SizedBox(height: 8),
                Wrap(                          // Wrap = 自动换行的 Row
                  spacing: 6,
                  children: event.tags
                      .map((t) => Chip(
                            label: Text(t, style: const TextStyle(fontSize: 11)),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,  // compact = 紧凑模式，减小内边距
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileTag extends StatelessWidget {
  final SymptomProfile profile;
  const _ProfileTag({required this.profile});

  Color _parse(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse(cleaned, radix: 16) ?? 0x66BB6A;
    return Color(0xFF000000 | value);
  }

  @override
  Widget build(BuildContext context) {
    final color = _parse(profile.themeColor);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        profile.name,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// 小文字+图标统计项
class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

// 峰值颜色芯片（绿/橙/红根据力度强弱变化）
class _ForceChip extends StatelessWidget {
  final String label;
  final double force;  // 0.0~1.0
  final Color color;

  const _ForceChip({required this.label, required this.force, required this.color});

  Color get _chipColor {    // getter = 每次访问时计算颜色
    if (force < 0.4) return Colors.green;
    if (force < 0.7) return Colors.orange;
    return Colors.red.shade400;  // .shade400 = 取颜色的 400 色阶变体
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: _chipColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(color: _chipColor, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
