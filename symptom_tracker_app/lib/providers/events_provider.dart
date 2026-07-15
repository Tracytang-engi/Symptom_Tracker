import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pain_event.dart';
import '../services/storage_service.dart';
import 'settings_provider.dart';  // 引入 storageServiceProvider

// ─── 事件列表 ─────────────────────────────────────────────────────────────────

class EventsNotifier extends StateNotifier<List<PainEvent>> {
  final StorageService _storage;

  EventsNotifier(this._storage) : super(_storage.getAllEvents());  // 启动时从 Hive 加载所有事件

  Future<void> addEvent(PainEvent event) async {
    await _storage.saveEvent(event);
    state = [event, ...state];  // 把新事件放到列表最前面（时间倒序）
  }

  Future<void> updateEvent(PainEvent event) async {
    await _storage.updateEvent(event);
    state = state.map((e) => e.id == event.id ? event : e).toList();  // 找到旧事件并替换
  }

  Future<void> deleteEvent(String id) async {
    await _storage.deleteEvent(id);
    state = state.where((e) => e.id != id).toList();  // 过滤掉已删除的事件
  }

  Future<void> deleteAll() async {
    await _storage.deleteAllEvents();
    state = [];  // 状态置空，触发 UI 刷新
  }

  void reload() {
    state = _storage.getAllEvents();  // 手动从 Hive 重新加载（用于外部修改了数据库时）
  }
}

final eventsProvider =
    StateNotifierProvider<EventsNotifier, List<PainEvent>>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return EventsNotifier(storage);
});

// ─── 派生 Provider（从事件列表中提取子集）────────────────────────────────────

// 今日事件列表
final todayEventsProvider = Provider<List<PainEvent>>((ref) {
  final events = ref.watch(eventsProvider);  // ref.watch = 监听 eventsProvider，事件增删时自动重算
  final today = DateTime.now();
  return events.where((e) {
    return e.startTime.year == today.year &&
        e.startTime.month == today.month &&
        e.startTime.day == today.day;
  }).toList();
});

// 最近一条事件（用于首页"最后一次发作"摘要）
final latestEventProvider = Provider<PainEvent?>((ref) {   // PainEvent? = 可能为 null（没有记录时）
  final events = ref.watch(eventsProvider);
  return events.isEmpty ? null : events.first;
});

// Provider.family = 带参数的 Provider；参数是日期，返回该日期的事件
final selectedDayEventsProvider =
    Provider.family<List<PainEvent>, DateTime>((ref, day) {
  final events = ref.watch(eventsProvider);
  return events.where((e) {
    return e.startTime.year == day.year &&
        e.startTime.month == day.month &&
        e.startTime.day == day.day;
  }).toList();
});

// 过去 7 天的事件（统计页用）
final last7DaysEventsProvider = Provider<List<PainEvent>>((ref) {
  final events = ref.watch(eventsProvider);
  final cutoff = DateTime.now().subtract(const Duration(days: 7));  // .subtract() = 日期减法
  return events.where((e) => e.startTime.isAfter(cutoff)).toList();
});

// 过去 7 天每天的发作次数（用于柱状图）
final weeklyCountProvider = Provider<List<DayCount>>((ref) {
  final events = ref.watch(last7DaysEventsProvider);
  final today = DateTime.now();
  return List.generate(7, (i) {                  // List.generate(n, fn) = 生成 n 个元素的列表
    final day = today.subtract(Duration(days: 6 - i));  // 从 6 天前到今天
    final count = events.where((e) {
      return e.startTime.year == day.year &&
          e.startTime.month == day.month &&
          e.startTime.day == day.day;
    }).length;                                           // .length = 符合条件的事件数量
    return DayCount(day, count);
  });
});

// 简单数据类：一天的日期 + 发作次数
class DayCount {
  final DateTime date;
  final int count;
  const DayCount(this.date, this.count);
}
