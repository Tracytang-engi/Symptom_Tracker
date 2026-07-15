import 'package:hive_flutter/hive_flutter.dart';  // Hive = 轻量本地 NoSQL 数据库
import '../models/pain_event.dart';
import '../models/user_settings.dart';
import '../models/device_settings.dart';
import '../models/symptom_profile.dart';
import '../models/tag.dart';

// StorageService：封装所有 Hive 读写操作
// 数据库布局（每种数据一个 Box，类比"表"）：
//   'events'   → Map，键=事件 ID，值=事件 JSON
//   'settings' → Map，键='user'，值=用户设置 JSON
//   'device'   → Map，键='device'，值=设备设置 JSON
//   'profiles' → Map，键=档案 ID，值=档案 JSON
//   'tags'     → List，每项为标签 JSON
class StorageService {
  // private static 常量（_ 开头 = 私有，文件外不可访问）
  static const _eventsBox   = 'events';
  static const _settingsBox = 'settings';
  static const _deviceBox   = 'device';
  static const _profilesBox = 'profiles';
  static const _tagsBox     = 'tags';
  static const _settingsKey = 'user';    // 用户设置在 Box 里的键名
  static const _deviceKey   = 'device';

  // ─── 初始化 ─────────────────────────────────────────────────────────────────

  // static async 方法：在 main() 里 await 调用，确保 Hive 就绪后再启动 App
  static Future<void> init() async {
    await Hive.initFlutter();            // 初始化 Hive，设置存储路径
    await Future.wait([                  // Future.wait = 并行等待多个异步操作完成
      Hive.openBox<Map>(_eventsBox),     // openBox<Map> = 打开存 Map 类型的盒子
      Hive.openBox<Map>(_settingsBox),
      Hive.openBox<Map>(_deviceBox),
      Hive.openBox<Map>(_profilesBox),
      Hive.openBox(_tagsBox),            // 不指定类型 = 存任意类型
    ]);
    await _seedDefaultsIfEmpty();        // 首次启动时写入默认数据
  }

  static Future<void> _seedDefaultsIfEmpty() async {
    final profilesBox = Hive.box<Map>(_profilesBox);
    if (profilesBox.isEmpty) {           // .isEmpty = 盒子是否为空
      final defaultProfile = SymptomProfile.defaultProfile;
      await profilesBox.put(defaultProfile.id, defaultProfile.toJson());  // put(key, value) = 存入
    }

    final tagsBox = Hive.box(_tagsBox);
    if (tagsBox.isEmpty) {
      for (final tag in Tag.defaults) {  // for...in = 遍历列表中每个元素
        await tagsBox.add(tag.toJson()); // .add() = 追加到末尾（自动生成整数 key）
      }
    }
  }

  // ─── 事件 CRUD ──────────────────────────────────────────────────────────────

  Box<Map> get _events => Hive.box<Map>(_eventsBox);  // get = 每次访问时重新获取 Box 引用

  Future<void> saveEvent(PainEvent event) async {
    await _events.put(event.id, event.toJson());   // 以事件 ID 为 key 存入
  }

  Future<void> updateEvent(PainEvent event) async {
    await _events.put(event.id, event.toJson());   // put 已存在的 key = 覆盖（更新）
  }

  Future<void> deleteEvent(String id) async {
    await _events.delete(id);                      // .delete(key) = 删除指定 key
  }

  List<PainEvent> getAllEvents() {
    return _events.values                          // .values = 取所有值（只取值，不要 key）
        .map((m) => PainEvent.fromJson(m))         // .map() = 将每个 Map 转为 PainEvent 对象
        .toList()                                  // .toList() = 把惰性迭代器转为实际列表
      ..sort((a, b) => b.startTime.compareTo(a.startTime));  // .. = 级联操作，在同一对象上继续调用；按时间倒序排
  }

  List<PainEvent> getEventsForDay(DateTime day) {
    return getAllEvents().where((e) {              // .where() = 过滤，只保留满足条件的元素
      return e.startTime.year == day.year &&
          e.startTime.month == day.month &&
          e.startTime.day == day.day;
    }).toList();
  }

  List<PainEvent> getEventsInRange(DateTime from, DateTime to) {
    return getAllEvents()
        .where((e) => e.startTime.isAfter(from) && e.startTime.isBefore(to))  // .isAfter/.isBefore = 时间比较
        .toList();
  }

  Future<void> deleteAllEvents() async {
    await _events.clear();  // .clear() = 清空整个 Box
  }

  // ─── 用户设置 ────────────────────────────────────────────────────────────────

  Box<Map> get _settingsBoxRef => Hive.box<Map>(_settingsBox);

  UserSettings loadUserSettings() {
    final raw = _settingsBoxRef.get(_settingsKey);  // .get(key) = 取值，不存在返回 null
    if (raw == null) return const UserSettings();   // 第一次启动没有存过，返回默认设置
    return UserSettings.fromJson(raw);
  }

  Future<void> saveUserSettings(UserSettings s) async {
    await _settingsBoxRef.put(_settingsKey, s.toJson());
  }

  // ─── 设备设置 ────────────────────────────────────────────────────────────────

  Box<Map> get _deviceBoxRef => Hive.box<Map>(_deviceBox);

  DeviceSettings loadDeviceSettings() {
    final raw = _deviceBoxRef.get(_deviceKey);
    if (raw == null) return const DeviceSettings();
    return DeviceSettings.fromJson(raw);
  }

  Future<void> saveDeviceSettings(DeviceSettings s) async {
    await _deviceBoxRef.put(_deviceKey, s.toJson());
  }

  // ─── 症状档案 ────────────────────────────────────────────────────────────────

  Box<Map> get _profilesBoxRef => Hive.box<Map>(_profilesBox);

  List<SymptomProfile> getAllProfiles() {
    return _profilesBoxRef.values.map((m) => SymptomProfile.fromJson(m)).toList();
  }

  Future<void> saveProfile(SymptomProfile profile) async {
    await _profilesBoxRef.put(profile.id, profile.toJson());
  }

  // ─── 标签 ────────────────────────────────────────────────────────────────────

  Box get _tagsBoxRef => Hive.box(_tagsBox);

  List<Tag> getAllTags() {
    return _tagsBoxRef.values
        .map((m) => Tag.fromJson(m as Map))    // m as Map = 强制类型转换（告诉编译器类型）
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));  // 按排序序号升序
  }

  Future<void> saveAllTags(List<Tag> tags) async {
    await _tagsBoxRef.clear();               // 清空再重写（简单粗暴但可靠）
    for (final tag in tags) {
      await _tagsBoxRef.add(tag.toJson());
    }
  }

  // ─── 导出 ────────────────────────────────────────────────────────────────────

  String exportToCsv() {                     // 把所有事件导出为 CSV 文本
    final events = getAllEvents();
    final sb = StringBuffer();               // StringBuffer = 高效字符串拼接工具
    sb.writeln('id,startTime,endTime,durationMs,meanForce,peakForce,tags,textNote,fromDevice');
    for (final e in events) {
      sb.writeln(
          '${e.id},${e.startTime.toIso8601String()},${e.endTime.toIso8601String()},'
          '${e.durationMs},${e.meanForce.toStringAsFixed(3)},${e.peakForce.toStringAsFixed(3)},'  // .toStringAsFixed(3) = 保留3位小数
          '"${e.tags.join(';')}","${e.textNote ?? ''}",${e.fromDevice}');  // .join(';') = 列表元素用分号连接
    }
    return sb.toString();
  }
}
