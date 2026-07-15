import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/pain_event.dart';
import '../providers/events_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/pressure_curve_chart.dart';
import '../widgets/tag_selector.dart';

// EventDetailScreen：单次事件详情页
// 包括：压力曲线图、统计数字、标签编辑、文字备注
class EventDetailScreen extends ConsumerStatefulWidget {
  final PainEvent event;   // 要查看的事件（从时间线页面传入）
  const EventDetailScreen({super.key, required this.event});

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  late PainEvent _event;              // late = 在 initState 里赋值
  late TextEditingController _noteCtrl; // TextEditingController = 控制文字输入框

  @override
  void initState() {
    super.initState();
    _event = widget.event;            // widget.event = 访问父 Widget 传来的参数
    _noteCtrl = TextEditingController(text: _event.textNote);
  }

  @override
  void dispose() {
    _noteCtrl.dispose();             // 必须释放 controller，防止内存泄漏
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deviceSettings = ref.watch(deviceSettingsProvider);
    final primary = Theme.of(context).colorScheme.primary;
    final dateStr = DateFormat('MMM d, yyyy  HH:mm').format(_event.startTime);  // 格式化日期

    return Scaffold(
      appBar: AppBar(
        title: const Text('Episode Detail'),
        actions: [
          // 删除按钮
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── 时间头部 ─────────────────────────────────────────────────────
            Text(dateStr, style: TextStyle(color: primary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Duration: ${_event.formattedDuration}',
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),

            // ─── 压力曲线图 ───────────────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pressure Curve',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 12),
                    PressureCurveChart(event: _event, deviceSettings: deviceSettings),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ─── 统计数字 ─────────────────────────────────────────────────────
            Row(
              children: [
                Expanded(child: _Stat(label: 'Peak',    value: _event.peakForcePercent,  icon: Icons.arrow_upward)),
                const SizedBox(width: 8),
                Expanded(child: _Stat(label: 'Average', value: _event.meanForcePercent,  icon: Icons.show_chart)),
                const SizedBox(width: 8),
                Expanded(child: _Stat(label: 'Samples', value: '${_event.rawSamples.length}', icon: Icons.data_array)),
              ],
            ),
            const SizedBox(height: 16),

            // ─── 标签 ─────────────────────────────────────────────────────────
            _Section(
              title: 'Tags',
              trailing: TextButton(
                onPressed: _editTags,
                child: const Text('Edit'),
              ),
              child: _event.tags.isEmpty
                  ? const Text('No tags yet', style: TextStyle(color: Colors.grey))
                  : Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: _event.tags.map((t) => Chip(label: Text(t))).toList(),
                    ),
            ),
            const SizedBox(height: 12),

            // ─── 文字备注 ─────────────────────────────────────────────────────
            _Section(
              title: 'Notes',
              child: TextField(
                controller: _noteCtrl,
                maxLines: 3,         // 允许 3 行
                decoration: const InputDecoration(
                  hintText: 'Add a note...',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _saveNote(),   // 每次字符变化都自动保存
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editTags() async {
    // 打开标签选择底部面板，等待用户完成
    final result = await TagSelector.show(context, _event.tags);  // await = 等待 Future 完成
    if (result == null || !mounted) return;  // 用户 dismiss 则 result = null，直接返回

    final updated = _event.copyWith(tags: result);     // 只修改 tags 字段
    await ref.read(eventsProvider.notifier).updateEvent(updated);
    setState(() => _event = updated);                  // setState 触发 UI 重建
  }

  Future<void> _saveNote() async {
    final text = _noteCtrl.text;                       // 取输入框当前文字
    final updated = _event.copyWith(textNote: text.isEmpty ? null : text);  // 空字符串存为 null
    await ref.read(eventsProvider.notifier).updateEvent(updated);
    _event = updated;  // 不需要 setState（不影响 UI 布局，只保存数据）
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(   // showDialog<bool> = 返回 bool 的对话框
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Episode'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),  // pop(true) = 确认删除
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await ref.read(eventsProvider.notifier).deleteEvent(_event.id);
      Navigator.of(context).pop();   // 关闭详情页，回到时间线
    }
  }
}

// 小统计格（图标 + 数值 + 说明）
class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _Stat({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

// 带标题的内容区块
class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;  // 右侧可选操作按钮

  const _Section({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                if (trailing != null) trailing!,    // trailing! = 已确认非 null，直接使用
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
