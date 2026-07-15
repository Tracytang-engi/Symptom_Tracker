// SymptomProfile：症状档案，不同病症可以建不同档案（如头痛、胃痛）

class SymptomProfile {
  final String id;
  final String name;                       // 档案名称
  final String icon;                       // 图标名
  final String themeColor;                 // 十六进制颜色字符串，如 '#66BB6A'
  final bool voiceRecordingEnabled;        // 是否开启语音备注功能
  final bool tagsEnabled;                  // 是否开启标签功能
  final bool medicationTrackingEnabled;    // 是否追踪用药（预留）
  final bool cycleTrackingEnabled;         // 是否关联生理周期（预留）
  final bool isActive;                     // 档案是否处于激活状态

  const SymptomProfile({
    required this.id,
    required this.name,
    this.icon = 'healing',
    this.themeColor = '#66BB6A',
    this.voiceRecordingEnabled = false,
    this.tagsEnabled = true,
    this.medicationTrackingEnabled = false,
    this.cycleTrackingEnabled = false,
    this.isActive = true,
  });

  SymptomProfile copyWith({
    String? id,
    String? name,
    String? icon,
    String? themeColor,
    bool? voiceRecordingEnabled,
    bool? tagsEnabled,
    bool? medicationTrackingEnabled,
    bool? cycleTrackingEnabled,
    bool? isActive,
  }) {
    return SymptomProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      themeColor: themeColor ?? this.themeColor,
      voiceRecordingEnabled: voiceRecordingEnabled ?? this.voiceRecordingEnabled,
      tagsEnabled: tagsEnabled ?? this.tagsEnabled,
      medicationTrackingEnabled: medicationTrackingEnabled ?? this.medicationTrackingEnabled,
      cycleTrackingEnabled: cycleTrackingEnabled ?? this.cycleTrackingEnabled,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'themeColor': themeColor,
    'voiceRecordingEnabled': voiceRecordingEnabled,
    'tagsEnabled': tagsEnabled,
    'medicationTrackingEnabled': medicationTrackingEnabled,
    'cycleTrackingEnabled': cycleTrackingEnabled,
    'isActive': isActive,
  };

  factory SymptomProfile.fromJson(Map<dynamic, dynamic> json) => SymptomProfile(
    id: json['id'] as String,
    name: json['name'] as String,
    icon: json['icon'] as String? ?? 'healing',
    themeColor: json['themeColor'] as String? ?? '#66BB6A',
    voiceRecordingEnabled: json['voiceRecordingEnabled'] as bool? ?? false,
    tagsEnabled: json['tagsEnabled'] as bool? ?? true,
    medicationTrackingEnabled: json['medicationTrackingEnabled'] as bool? ?? false,
    cycleTrackingEnabled: json['cycleTrackingEnabled'] as bool? ?? false,
    isActive: json['isActive'] as bool? ?? true,
  );

  // static get = 静态只读属性；返回内置的默认档案（首次启动使用）
  static SymptomProfile get defaultProfile => const SymptomProfile(
    id: 'default',
    name: 'My Symptoms',
    icon: 'healing',
    tagsEnabled: true,
  );
}
