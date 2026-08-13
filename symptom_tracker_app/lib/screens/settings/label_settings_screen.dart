import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../models/tag.dart';
import '../../providers/settings_provider.dart';

// LabelSettingsScreen：标签管理页
// 支持新增、重命名、删除、拖拽排序
class LabelSettingsScreen extends ConsumerWidget {
  const LabelSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags    = ref.watch(tagsProvider);         // 当前所有标签列表
    final notifier = ref.read(tagsProvider.notifier); // 用于调用增删改排序方法

    return Scaffold(
      appBar: AppBar(
        title: const Text('Labels'),
        actions: [
          // 右上角添加按钮
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddDialog(context, notifier),
          ),
        ],
      ),
      body: ReorderableListView.builder(  // ReorderableListView = 可拖动排序的 ListView
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: tags.length,
        itemBuilder: (_, i) {
          final tag = tags[i];
          return ListTile(
            key: ValueKey(tag.id),   // key = 拖动时 Flutter 用 key 追踪每个 ListTile 的身份
            leading: Icon(_icon(tag.icon)),
            title: Text(tag.name),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 编辑按钮
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _showEditDialog(context, tag, notifier),
                ),
                // 删除按钮
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  onPressed: () => _confirmDelete(context, tag, notifier),
                ),
                // 拖动手柄（ReorderableListView 会自动添加，这里是视觉提示）
                const Icon(Icons.drag_handle, color: Colors.grey),
              ],
            ),
          );
        },
        onReorder: (oldIndex, newIndex) {   // onReorder = 拖动完成时的回调
          if (newIndex > oldIndex) newIndex--;  // 修正 Flutter 拖动的偏移量（官方惯例）
          final reordered = List<Tag>.from(tags);  // 复制一份，不改原来的（不可变模式）
          final item = reordered.removeAt(oldIndex);  // .removeAt() = 取出并移除
          reordered.insert(newIndex, item);            // .insert() = 插入到新位置
          notifier.reorder(reordered);
        },
      ),
    );
  }

  // 新增标签对话框
  void _showAddDialog(BuildContext context, TagsNotifier notifier) {
    final controller = TextEditingController();  // TextEditingController = 控制输入框文字
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Label'),
        content: TextField(
          controller: controller,
          autofocus: true,             // autofocus = 打开对话框时自动弹出键盘
          decoration: const InputDecoration(hintText: 'Label name'),  // hintText = 占位文字
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();  // .trim() = 去掉首尾空格
              if (name.isNotEmpty) {
                notifier.addTag(Tag(
                  id: const Uuid().v4(),  // const Uuid() = 编译期常量实例
                  name: name,
                ));
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // 编辑标签名对话框
  void _showEditDialog(BuildContext context, Tag tag, TagsNotifier notifier) {
    final controller = TextEditingController(text: tag.name);  // 预填现有名称
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Label'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                notifier.updateTag(tag.copyWith(name: name));  // 只修改 name，其余不变
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // 删除前确认对话框（防止误删）
  void _confirmDelete(BuildContext context, Tag tag, TagsNotifier notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Label'),
        content: Text('Delete "${tag.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () { notifier.removeTag(tag.id); Navigator.of(ctx).pop(); },
            style: TextButton.styleFrom(foregroundColor: Colors.red),  // 危险操作用红色
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // 图标名字符串 → IconData（Flutter 不能直接把字符串当图标用）
  IconData _icon(String name) {
    const m = {
      'fitness_center': Icons.fitness_center,
      'directions_run': Icons.directions_run,
      'restaurant': Icons.restaurant,
      'wb_sunny': Icons.wb_sunny,
      'medication': Icons.medication,
      'check_circle': Icons.check_circle,
      'calendar_month': Icons.calendar_month,
      'sentiment_stressed': Icons.sentiment_very_dissatisfied,
      'light_mode': Icons.light_mode,
      'bedtime': Icons.bedtime,
    };
    return m[name] ?? Icons.label;
  }
}
