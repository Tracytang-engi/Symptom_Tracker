import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';

// TagSelector：从底部弹出的标签选择面板
// 设计为非强制性（可以直接 dismiss 关闭而不选任何标签）
class TagSelector extends ConsumerStatefulWidget {   // ConsumerStatefulWidget = 有状态 + 可访问 Riverpod
  final List<String> selectedTagIds;                 // 当前已选中的标签 ID 列表
  final void Function(List<String>) onSave;          // 回调函数类型：传入标签 ID 列表，无返回值

  const TagSelector({
    super.key,
    required this.selectedTagIds,
    required this.onSave,
  });

  // static = 不需要实例；直接调用 TagSelector.show() 弹出底部面板
  static Future<List<String>?> show(BuildContext context, List<String> current) {
    return showModalBottomSheet<List<String>>(  // showModalBottomSheet = 从底部弹出半屏面板
      context: context,
      isScrollControlled: true,  // 允许面板根据内容高度自适应（否则固定半屏）
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),  // 只圆上边角
      ),
      builder: (ctx) => TagSelector(
        selectedTagIds: current,
        onSave: (tags) => Navigator.of(ctx).pop(tags),  // pop(value) = 关闭面板并返回值
      ),
    );
  }

  @override
  ConsumerState<TagSelector> createState() => _TagSelectorState();
}

class _TagSelectorState extends ConsumerState<TagSelector> {
  late Set<String> _selected;  // Set = 无重复集合；late = initState 里初始化

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.selectedTagIds);  // Set.from(list) = 把列表转为 Set，去除重复
  }

  @override
  Widget build(BuildContext context) {
    final tags = ref.watch(tagsProvider);        // 获取所有可用标签
    final color = Theme.of(context).colorScheme.primary;

    return DraggableScrollableSheet(              // DraggableScrollableSheet = 可拖动调整高度的滚动面板
      initialChildSize: 0.5,   // 初始占屏幕 50%
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,            // false = 不撑满父容器
      builder: (_, scrollController) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部拖动条（纯装饰）
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Add Tags', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Optional — tap to select, dismiss to skip',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),  // ?. = 安全调用（textSmall 可能为 null）
              const SizedBox(height: 16),
              Expanded(  // Expanded = 占满 Column 剩余空间
                child: SingleChildScrollView(
                  controller: scrollController,  // 把 DraggableScrollableSheet 的 controller 绑定到这里
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,  // runSpacing = 换行间距
                    children: tags.map((tag) {
                      final selected = _selected.contains(tag.id);  // .contains() = 判断 Set 是否包含
                      return FilterChip(                // FilterChip = 可选中/取消的芯片
                        selected: selected,
                        label: Text(tag.name),
                        avatar: Icon(_iconFromName(tag.icon), size: 16, color: selected ? color : Colors.grey),
                        onSelected: (v) {
                          setState(() {
                            if (v) {
                              _selected.add(tag.id);     // .add() = 集合加入元素
                            } else {
                              _selected.remove(tag.id);  // .remove() = 集合移除元素
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(null),  // null = 用户跳过，不选标签
                      child: const Text('Skip'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => widget.onSave(_selected.toList()),  // .toList() = Set 转 List
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // 把字符串图标名转为 IconData（Dart 里图标不能直接用字符串，需要手动映射）
  IconData _iconFromName(String name) {
    const map = {                               // const Map = 编译期常量，查找速度快
      'fitness_center': Icons.fitness_center,
      'restaurant': Icons.restaurant,
      'wb_sunny': Icons.wb_sunny,
      'medication': Icons.medication,
      'check_circle': Icons.check_circle,
      'calendar_month': Icons.calendar_month,
      'sentiment_stressed': Icons.sentiment_very_dissatisfied,
      'light_mode': Icons.light_mode,
      'bedtime': Icons.bedtime,
    };
    return map[name] ?? Icons.label;            // ?? = 找不到时用默认图标
  }
}
