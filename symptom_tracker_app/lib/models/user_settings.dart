import '../theme/app_theme.dart';

enum DarkModeOption { system, light, dark }

enum PostEventAction { nothing, silentNotification, promptTags, promptIfAbnormal }

enum DataSmoothingLevel { none, low, medium, high }

// UserSettings：App 界面与行为的所有用户偏好设置
class UserSettings {
  final AppThemeVariant themeVariant;
  final DarkModeOption darkMode;
  final AppFontSize fontSize;
  final bool accessibleMode;             // Accessible Mode（学习障碍友好）
  final bool largeButtons;
  final bool leftHandMode;
  final bool showRecordingFeature;
  final bool autoSaveRecording;
  final bool keepOriginalRecording;
  final bool promptTagAfterRecording;
  final bool enableContinuousPressure;
  final DataSmoothingLevel dataSmoothing;
  final PostEventAction postEventAction;
  final bool dailySummaryReminder;
  final bool deviceLowBatteryReminder;
  final bool deviceDisconnectedReminder;
  final bool allowDataExport;
  final String activeProfileId;
  final bool multiProfileEnabled;
  final String guardianName;
  final String guardianPhone;

  /// 进入 Accessible Mode 前的字号（index），退出时恢复
  final int? preAccessibleFontSize;

  /// 进入 Accessible Mode 前的大按钮开关，退出时恢复
  final bool? preAccessibleLargeButtons;

  const UserSettings({
    this.themeVariant = AppThemeVariant.teal,
    this.darkMode = DarkModeOption.system,
    this.fontSize = AppFontSize.standard,
    this.accessibleMode = false,
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
    this.multiProfileEnabled = false,
    this.guardianName = '',
    this.guardianPhone = '',
    this.preAccessibleFontSize,
    this.preAccessibleLargeButtons,
  });

  /// 旧代码兼容别名
  bool get simplifiedUI => accessibleMode;

  UserSettings copyWith({
    AppThemeVariant? themeVariant,
    DarkModeOption? darkMode,
    AppFontSize? fontSize,
    bool? accessibleMode,
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
    bool? multiProfileEnabled,
    String? guardianName,
    String? guardianPhone,
    int? preAccessibleFontSize,
    bool? preAccessibleLargeButtons,
    bool clearPreAccessibleSnapshot = false,
  }) {
    return UserSettings(
      themeVariant: themeVariant ?? this.themeVariant,
      darkMode: darkMode ?? this.darkMode,
      fontSize: fontSize ?? this.fontSize,
      accessibleMode: accessibleMode ?? this.accessibleMode,
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
      multiProfileEnabled: multiProfileEnabled ?? this.multiProfileEnabled,
      guardianName: guardianName ?? this.guardianName,
      guardianPhone: guardianPhone ?? this.guardianPhone,
      preAccessibleFontSize: clearPreAccessibleSnapshot
          ? null
          : (preAccessibleFontSize ?? this.preAccessibleFontSize),
      preAccessibleLargeButtons: clearPreAccessibleSnapshot
          ? null
          : (preAccessibleLargeButtons ?? this.preAccessibleLargeButtons),
    );
  }

  Map<String, dynamic> toJson() => {
    'themeVariant': themeVariant.index,
    'darkMode': darkMode.index,
    'fontSize': fontSize.index,
    'accessibleMode': accessibleMode,
    'simplifiedUI': accessibleMode, // 兼容旧键
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
    'multiProfileEnabled': multiProfileEnabled,
    'guardianName': guardianName,
    'guardianPhone': guardianPhone,
    'preAccessibleFontSize': preAccessibleFontSize,
    'preAccessibleLargeButtons': preAccessibleLargeButtons,
  };

  factory UserSettings.fromJson(Map<dynamic, dynamic> json) => UserSettings(
    themeVariant: AppThemeVariant.values[json['themeVariant'] as int? ?? 0],
    darkMode: DarkModeOption.values[json['darkMode'] as int? ?? 0],
    fontSize: AppFontSize.values[json['fontSize'] as int? ?? 1],
    accessibleMode: json['accessibleMode'] as bool? ??
        json['simplifiedUI'] as bool? ??
        false,
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
    multiProfileEnabled: json['multiProfileEnabled'] as bool? ?? false,
    guardianName: json['guardianName'] as String? ?? '',
    guardianPhone: json['guardianPhone'] as String? ?? '',
    preAccessibleFontSize: json['preAccessibleFontSize'] as int?,
    preAccessibleLargeButtons: json['preAccessibleLargeButtons'] as bool?,
  );
}
