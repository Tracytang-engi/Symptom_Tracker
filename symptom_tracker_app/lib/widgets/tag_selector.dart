import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tag.dart';
import '../providers/settings_provider.dart';

// TagSelector：从底部弹出的标签选择面板
// 设计为非强制性（可以直接 dismiss 关闭而不选任何标签）
class TagSelector extends ConsumerStatefulWidget {
  final List<String> selectedTagIds;
  final void Function(List<String>) onSave;

  const TagSelector({
    super.key,
    required this.selectedTagIds,
    required this.onSave,
  });

  static Future<List<String>?> show(BuildContext context, List<String> current) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => TagSelector(
        selectedTagIds: current,
        onSave: (tags) => Navigator.of(ctx).pop(tags),
      ),
    );
  }

  @override
  ConsumerState<TagSelector> createState() => _TagSelectorState();
}

class _TagSelectorState extends ConsumerState<TagSelector> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.selectedTagIds);
    // 旧版 poor_sleep 视为睡眠时选中
    if (_selected.contains('poor_sleep')) {
      _selected.add('during_sleep');
    }
  }

  void _toggle(String id, bool selected) {
    setState(() {
      if (selected) {
        _selected.add(id);
        if (id == 'during_sleep') _selected.remove('poor_sleep');
      } else {
        _selected.remove(id);
        if (id == 'during_sleep') _selected.remove('poor_sleep');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tags = ref.watch(tagsProvider);
    final accessible = ref.watch(userSettingsProvider).accessibleMode;
    final color = Theme.of(context).colorScheme.primary;

    return DraggableScrollableSheet(
      initialChildSize: accessible ? 0.42 : 0.5,
      minChildSize: 0.3,
      maxChildSize: accessible ? 0.55 : 0.85,
      expand: false,
      builder: (_, scrollController) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Add Tags', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                accessible
                    ? 'Optional — tap a square to select'
                    : 'Optional — tap to select, dismiss to skip',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: accessible
                    ? _buildAccessibleGrid(color)
                    : SingleChildScrollView(
                        controller: scrollController,
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: tags.map((tag) {
                            final selected = _selected.contains(tag.id);
                            return FilterChip(
                              selected: selected,
                              label: Text(tag.name),
                              avatar: Icon(
                                iconFromName(tag.icon),
                                size: 16,
                                color: selected ? color : Colors.grey,
                              ),
                              onSelected: (v) => _toggle(tag.id, v),
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
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text('Skip'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => widget.onSave(_selected.toList()),
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

  Widget _buildAccessibleGrid(Color color) {
    final quick = Tag.accessibleQuickTags;
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = 10.0;
        final cell = (constraints.maxWidth - gap * 3) / 4;
        final size = cell.clamp(64.0, 120.0);
        return Center(
          child: SizedBox(
            height: size,
            child: Row(
              children: [
                for (var i = 0; i < quick.length; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: _AccessibleTagTile(
                        tag: quick[i],
                        selected: _selected.contains(quick[i].id) ||
                            (quick[i].id == 'during_sleep' &&
                                _selected.contains('poor_sleep')),
                        color: color,
                        onTap: () {
                          final id = quick[i].id;
                          final on = _selected.contains(id) ||
                              (id == 'during_sleep' &&
                                  _selected.contains('poor_sleep'));
                          _toggle(id, !on);
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AccessibleTagTile extends StatelessWidget {
  final Tag tag;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _AccessibleTagTile({
    required this.tag,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? color.withOpacity(0.18) : color.withOpacity(0.08);
    final fg = selected ? color : Colors.grey.shade800;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? color : color.withOpacity(0.25),
              width: selected ? 3 : 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(iconFromName(tag.icon), size: 36, color: fg),
                const SizedBox(height: 4),
                Text(
                  tag.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: fg,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 标签 icon 字符串 → IconData（多处共用）
IconData iconFromName(String name) {
  const map = {
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
  return map[name] ?? Icons.label;
}
