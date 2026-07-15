import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../providers/events_provider.dart';
import '../models/pain_event.dart';
import '../widgets/pain_event_card.dart';

// TimelineScreen：事件时间线页面
// 顶部：日期导航（左右切换）
// 中间：时间轴条（今天发作的每次在时间上标点）
// 底部：当天事件卡片列表
class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  DateTime _selectedDay = DateTime.now();  // 当前选中的日期（默认今天）

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(selectedDayEventsProvider(_selectedDay));  // Provider.family：传参获取该天事件
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Timeline'),
      ),
      body: Column(
        children: [
          // ─── 日期导航栏 ───────────────────────────────────────────────────
          _DateNavigator(
            selectedDay: _selectedDay,
            onPrev: () => setState(() => _selectedDay = _selectedDay.subtract(const Duration(days: 1))),
            onNext: () {
              final tomorrow = DateTime.now().add(const Duration(days: 1));
              if (_selectedDay.isBefore(tomorrow)) {   // 不允许跳到未来
                setState(() => _selectedDay = _selectedDay.add(const Duration(days: 1)));
              }
            },
          ),
          const Divider(height: 1),

          // ─── 时间轴条 ─────────────────────────────────────────────────────
          if (events.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _TimelineBar(events: events, color: primary),
            ),
            const Divider(height: 1),
          ],

          // ─── 事件列表 ─────────────────────────────────────────────────────
          Expanded(   // Expanded = 占满剩余高度（ListView 在 Column 里必须包 Expanded）
            child: events.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_note_outlined, size: 64, color: primary.withOpacity(0.3)),
                        const SizedBox(height: 12),
                        const Text('No episodes this day', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: events.length,
                    itemBuilder: (_, i) => PainEventCard(
                      event: events[i],
                      onTap: () => context.push('/timeline/${events[i].id}', extra: events[i]),  // extra = 路由传递对象
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── 日期导航栏 ───────────────────────────────────────────────────────────────

class _DateNavigator extends StatelessWidget {
  final DateTime selectedDay;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _DateNavigator({required this.selectedDay, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(selectedDay, DateTime.now());  // 是否为今天
    final label = isToday ? 'Today' : DateFormat('MMM d, yyyy').format(selectedDay);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: onPrev),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: isToday ? null : onNext,   // 今天时禁用（不能跳到未来）
          ),
        ],
      ),
    );
  }
}

// ─── 时间轴条（24 小时条，发作时打点）───────────────────────────────────────────

class _TimelineBar extends StatelessWidget {
  final List<PainEvent> events;
  final Color color;

  const _TimelineBar({required this.events, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Episodes in 24h', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 6),
        LayoutBuilder(   // LayoutBuilder = 获取父 Widget 的实际宽度，用于精确计算位置
          builder: (_, constraints) {
            final width = constraints.maxWidth;   // 父容器最大宽度
            return SizedBox(
              height: 24,
              child: Stack(   // Stack = 子 Widget 叠加在同一层（绝对定位）
                children: [
                  // 灰色背景轨道
                  Positioned.fill(    // Positioned.fill = 撑满 Stack 的全部空间
                    child: Container(
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  // 每次发作一个小圆点
                  for (final e in events) ...[   // for...in 在 Widget 列表里展开多个子 Widget
                    Positioned(
                      left: (e.startTime.hour * 60 + e.startTime.minute) / (24 * 60) * width - 6,  // 计算横向位置
                      top: 4,
                      child: Tooltip(   // Tooltip = 长按时显示说明文字
                        message: DateFormat('HH:mm').format(e.startTime),
                        child: Container(
                          width: 16, height: 16,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,       // 圆形
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        // x 轴刻度（0 6 12 18 24）
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,   // 均匀分布
          children: ['0', '6', '12', '18', '24']
              .map((t) => Text(t, style: const TextStyle(fontSize: 9, color: Colors.grey)))
              .toList(),
        ),
      ],
    );
  }
}
