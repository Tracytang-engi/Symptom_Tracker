import '../theme/app_theme.dart';  // import = 引入其他文件；.. 表示上一级目录

// 枚举：深色模式选项
enum DarkModeOption { system, light, dark }

// 枚举：事件结束后的行为
enum PostEventAction { nothing, silentNotification, promptTags, promptIfAbnormal }

// 枚举：数据平滑程度
enum DataSmoothingLevel { none, low, medium, high }

// UserSettings：App 界面与行为的所有用户偏好设置
class UserSettings {
  final AppThemeVariant themeVariant;      // 主题颜色变体（teal / sage）
  final DarkModeOption darkMode;           // 深色模式
  final AppFontSize fontSize;             // 字体大小等级
  final bool simplifiedUI;               // 简化界面（适合不识字患者）
  final bool largeButtons;               // 大按钮模式
  final bool leftHandMode;               // 左手模式（镜像导航栏）
  final bool showRecordingFeature;       // 是否显示语音录音按钮
  final bool autoSaveRecording;          // 录音后自动保存
  final bool keepOriginalRecording;      // 保留原始音频文件
  final bool promptTagAfterRecording;    // 录音完成后提示选标签
  final bool enableContinuousPressure;   // 持续发送实时压力数据
  final DataSmoothingLevel dataSmoothing; // 压力曲线平滑程度
  final PostEventAction postEventAction;  // 事件结束后触发什么
  final bool dailySummaryReminder;       // 每日统计提醒
  final bool deviceLowBatteryReminder;   // 设备低电量提醒
  final bool deviceDisconnectedReminder; // 设备断开提醒
  final bool allowDataExport;            // 允许导出数据
  final String activeProfileId;          // 当前激活的症状档案 ID

  const UserSettings({                   // const 构造函数，所有默认值编译期确定
    this.themeVariant = AppThemeVariant.teal,
    this.darkMode = DarkModeOption.system,
    this.fontSize = AppFontSize.standard,
    this.simplifiedUI = false,
    this.largeButtons = false,
    this.leftHandMode = false,
    this.showRecordingFeature = true,
    this.autoSaveRecording = true,
    this.keepOriginalRecording = true,
    this.promptTagAfterRecording = false,
    this.enableContinuousPressure = true,
    this.dataSmoothing = DataSmoothingLevel.low,
    this.postEventAction = PostEventAction.silentNotification,
    this.dailySummaryReminder = false,
    this.deviceLowBatteryReminder = true,
    this.deviceDisconnectedReminder = true,
    this.allowDataExport = true,
    this.activeProfileId = 'default',
  });

  UserSettings copyWith({                // 返回修改了指定字段的新对象
    AppThemeVariant? themeVariant,
    DarkModeOption? darkMode,
    AppFontSize? fontSize,
    bool? simplifiedUI,
    bool? largeButtons,
    bool? leftHandMode,
    bool? showRecordingFeature,
    bool? autoSaveRecording,
    bool? keepOriginalRecording,
    bool? promptTagAfterRecording,
    bool? enableContinuousPressure,
    DataSmoothingLevel? dataSmoothing,
    PostEventAction? postEventAction,
    bool? dailySummaryReminder,
    bool? deviceLowBatteryReminder,
    bool? deviceDisconnectedReminder,
    bool? allowDataExport,
    String? activeProfileId,
  }) {
    return UserSettings(
      themeVariant: themeVariant ?? this.themeVariant,
      darkMode: darkMode ?? this.darkMode,
      fontSize: fontSize ?? this.fontSize,
      simplifiedUI: simplifiedUI ?? this.simplifiedUI,
      largeButtons: largeButtons ?? this.largeButtons,
      leftHandMode: leftHandMode ?? this.leftHandMode,
      showRecordingFeature: showRecordingFeature ?? this.showRecordingFeature,
      autoSaveRecording: autoSaveRecording ?? this.autoSaveRecording,
      keepOriginalRecording: keepOriginalRecording ?? this.keepOriginalRecording,
      promptTagAfterRecording: promptTagAfterRecording ?? this.promptTagAfterRecording,
      enableContinuousPressure: enableContinuousPressure ?? this.enableContinuousPressure,
      dataSmoothing: dataSmoothing ?? this.dataSmoothing,
      postEventAction: postEventAction ?? this.postEventAction,
      dailySummaryReminder: dailySummaryReminder ?? this.dailySummaryReminder,
      deviceLowBatteryReminder: deviceLowBatteryReminder ?? this.deviceLowBatteryReminder,
      deviceDisconnectedReminder: deviceDisconnectedReminder ?? this.deviceDisconnectedReminder,
      allowDataExport: allowDataExport ?? this.allowDataExport,
      activeProfileId: activeProfileId ?? this.activeProfileId,
    );
  }

  Map<String, dynamic> toJson() => {    // 序列化为 Map，用于 Hive 持久化
    'themeVariant': themeVariant.index,  // .index = 枚举转整数（0,1,2...）
    'darkMode': darkMode.index,
    'fontSize': fontSize.index,
    'simplifiedUI': simplifiedUI,
    'largeButtons': largeButtons,
    'leftHandMode': leftHandMode,
    'showRecordingFeature': showRecordingFeature,
    'autoSaveRecording': autoSaveRecording,
    'keepOriginalRecording': keepOriginalRecording,
    'promptTagAfterRecording': promptTagAfterRecording,
    'enableContinuousPressure': enableContinuousPressure,
    'dataSmoothing': dataSmoothing.index,
    'postEventAction': postEventAction.index,
    'dailySummaryReminder': dailySummaryReminder,
    'deviceLowBatteryReminder': deviceLowBatteryReminder,
    'deviceDisconnectedReminder': deviceDisconnectedReminder,
    'allowDataExport': allowDataExport,
    'activeProfileId': activeProfileId,
  };

  factory UserSettings.fromJson(Map<dynamic, dynamic> json) => UserSettings(  // 从 Map 还原
    themeVariant: AppThemeVariant.values[json['themeVariant'] as int? ?? 0],   // .values[i] = 取第 i 个枚举值
    darkMode: DarkModeOption.values[json['darkMode'] as int? ?? 0],
    fontSize: AppFontSize.values[json['fontSize'] as int? ?? 1],
    simplifiedUI: json['simplifiedUI'] as bool? ?? false,
    largeButtons: json['largeButtons'] as bool? ?? false,
    leftHandMode: json['leftHandMode'] as bool? ?? false,
    showRecordingFeature: json['showRecordingFeature'] as bool? ?? true,
    autoSaveRecording: json['autoSaveRecording'] as bool? ?? true,
    keepOriginalRecording: json['keepOriginalRecording'] as bool? ?? true,
    promptTagAfterRecording: json['promptTagAfterRecording'] as bool? ?? false,
    enableContinuousPressure: json['enableContinuousPressure'] as bool? ?? true,
    dataSmoothing: DataSmoothingLevel.values[json['dataSmoothing'] as int? ?? 1],
    postEventAction: PostEventAction.values[json['postEventAction'] as int? ?? 1],
    dailySummaryReminder: json['dailySummaryReminder'] as bool? ?? false,
    deviceLowBatteryReminder: json['deviceLowBatteryReminder'] as bool? ?? true,
    deviceDisconnectedReminder: json['deviceDisconnectedReminder'] as bool? ?? true,
    allowDataExport: json['allowDataExport'] as bool? ?? true,
    activeProfileId: json['activeProfileId'] as String? ?? 'default',
  );
}
