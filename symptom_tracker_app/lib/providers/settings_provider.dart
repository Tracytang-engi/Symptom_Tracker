import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_settings.dart';
import '../models/device_settings.dart';
import '../models/tag.dart';
import '../models/symptom_profile.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

// ─── 全局存储服务 ─────────────────────────────────────────────────────────────

// Provider = Riverpod 的基础 Provider，只提供一个值（不可变）
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();  // ref = ProviderScope 的引用，可以读取其他 provider
});

// ─── 用户设置 ─────────────────────────────────────────────────────────────────

// StateNotifier = 可以修改状态的 Notifier；泛型参数 = 它管理的状态类型
class UserSettingsNotifier extends StateNotifier<UserSettings> {
  final StorageService _storage;

  UserSettingsNotifier(this._storage) : super(_storage.loadUserSettings());
  // : super(...) = 调用父类构造函数，把初始状态传进去

  Future<void> update(UserSettings settings) async {
    await _storage.saveUserSettings(settings);  // 先持久化到 Hive
    state = settings;                           // state = 更新 Riverpod 状态，触发 UI 重建
  }

  // patch = 只修改部分字段的便捷方法（不需要传完整对象）
  Future<void> patch(UserSettings Function(UserSettings) updater) async {
    final next = updater(state);
    await update(next);
  }

  /// 进入 / 退出 Accessible Mode（带字号与大按钮快照，持久化）
  Future<void> setAccessibleMode(bool on) async {
    if (on) {
      if (state.accessibleMode) return;
      await update(state.copyWith(
        accessibleMode: true,
        preAccessibleFontSize: state.fontSize.index,
        preAccessibleLargeButtons: state.largeButtons,
        largeButtons: true,
        fontSize: AppFontSize.large,
      ));
    } else {
      if (!state.accessibleMode) return;
      final fontIdx = state.preAccessibleFontSize ?? AppFontSize.standard.index;
      final safeIdx = fontIdx.clamp(0, AppFontSize.values.length - 1);
      await update(state.copyWith(
        accessibleMode: false,
        largeButtons: state.preAccessibleLargeButtons ?? false,
        fontSize: AppFontSize.values[safeIdx],
        clearPreAccessibleSnapshot: true,
      ));
    }
  }
}

// StateNotifierProvider = 暴露一个 StateNotifier 及其 state 的 Provider
final userSettingsProvider =
    StateNotifierProvider<UserSettingsNotifier, UserSettings>((ref) {
  final storage = ref.watch(storageServiceProvider);  // ref.watch = 依赖其他 Provider，并在其变化时重建
  return UserSettingsNotifier(storage);
});

// ─── 设备设置 ─────────────────────────────────────────────────────────────────

class DeviceSettingsNotifier extends StateNotifier<DeviceSettings> {
  final StorageService _storage;

  DeviceSettingsNotifier(this._storage) : super(_storage.loadDeviceSettings());

  Future<void> update(DeviceSettings settings) async {
    await _storage.saveDeviceSettings(settings);
    state = settings;
  }

  Future<void> patch(DeviceSettings Function(DeviceSettings) updater) async {
    final next = updater(state);
    await update(next);
  }
}

final deviceSettingsProvider =
    StateNotifierProvider<DeviceSettingsNotifier, DeviceSettings>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return DeviceSettingsNotifier(storage);
});

// ─── 标签列表 ─────────────────────────────────────────────────────────────────

class TagsNotifier extends StateNotifier<List<Tag>> {
  final StorageService _storage;

  TagsNotifier(this._storage) : super(_storage.getAllTags());

  Future<void> addTag(Tag tag) async {
    final next = [...state, tag];        // ... = 展开运算符，复制旧列表并追加新元素
    await _storage.saveAllTags(next);
    state = next;
  }

  Future<void> removeTag(String id) async {
    final next = state.where((t) => t.id != id).toList();  // 过滤掉要删除的标签
    await _storage.saveAllTags(next);
    state = next;
  }

  Future<void> updateTag(Tag updated) async {
    final next = state.map((t) => t.id == updated.id ? updated : t).toList();  // 找到并替换
    await _storage.saveAllTags(next);
    state = next;
  }

  Future<void> reorder(List<Tag> reordered) async {
    // 重新排序时给每个标签更新 sortOrder（用 .asMap().entries 获取下标）
    final indexed = reordered
        .asMap()                                      // .asMap() = 转为 {index: element} 的 Map
        .entries                                      // .entries = Map 的所有键值对迭代器
        .map((e) => e.value.copyWith(sortOrder: e.key))  // e.key = 新下标，e.value = 标签对象
        .toList();
    await _storage.saveAllTags(indexed);
    state = indexed;
  }
}

final tagsProvider = StateNotifierProvider<TagsNotifier, List<Tag>>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return TagsNotifier(storage);
});

// ─── 症状档案 ─────────────────────────────────────────────────────────────────

class ProfilesNotifier extends StateNotifier<List<SymptomProfile>> {
  final StorageService _storage;

  ProfilesNotifier(this._storage) : super(_storage.getAllProfiles());

  Future<void> save(SymptomProfile profile) async {
    await _storage.saveProfile(profile);
    final exists = state.any((p) => p.id == profile.id);  // .any() = 判断列表中是否存在满足条件的元素
    // 已存在则替换，不存在则追加
    state = exists
        ? state.map((p) => p.id == profile.id ? profile : p).toList()
        : [...state, profile];
  }
}

final profilesProvider =
    StateNotifierProvider<ProfilesNotifier, List<SymptomProfile>>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return ProfilesNotifier(storage);
});

// 派生 Provider：从当前激活的 profileId 查找对应的 SymptomProfile
final activeProfileProvider = Provider<SymptomProfile>((ref) {
  final profiles = ref.watch(profilesProvider);
  final activeId = ref.watch(userSettingsProvider).activeProfileId;
  return profiles.firstWhere(           // .firstWhere() = 找第一个满足条件的元素
    (p) => p.id == activeId,
    orElse: () => SymptomProfile.defaultProfile,  // orElse = 找不到时的兜底值
  );
});
