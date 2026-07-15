// DeviceSettings：ESP32 硬件设备的配置参数（震动模式、校准值等）

enum VibrationMode { quiet, confirm, realtime }  // enum = 枚举：只能取这几个固定值之一

extension VibrationModeExt on VibrationMode {    // extension = 给已有类型添加新方法，不修改源码
  String get label {                             // get = 只读属性
    switch (this) {                              // this = 当前枚举值本身
      case VibrationMode.quiet:
        return 'Quiet';
      case VibrationMode.confirm:
        return 'Simple Confirm';
      case VibrationMode.realtime:
        return 'Realtime Force Feedback';
    }
  }

  String get description {                       // 每种模式的说明文字
    switch (this) {
      case VibrationMode.quiet:
        return 'No vibration feedback';
      case VibrationMode.confirm:
        return 'One buzz on start, two on end';
      case VibrationMode.realtime:
        return 'Vibration intensity follows pressure';
    }
  }
}

class DeviceSettings {
  final bool startVibration;        // 是否在开始记录时震动
  final bool endVibration;          // 是否在结束记录时震动
  final bool realtimeFeedback;      // 是否开启实时压力强度反馈
  final double maxVibrationPower;   // 最大震动功率 0.0~1.0
  final VibrationMode vibrationMode; // 当前所选震动模式（枚举值）
  final int samplingRateHz;         // 采样频率（默认 50Hz）
  final int pressThreshold;         // 按压检测阈值（ADC 原始值）

  // 三步校准的基准 ADC 值；0 表示尚未校准
  final int calibLight;
  final int calibMedium;
  final int calibStrong;
  final int calibMax;               // 力度映射上限（超过此值视为 100%）

  const DeviceSettings({           // const 构造函数：所有默认值在编译期确定
    this.startVibration = true,
    this.endVibration = true,
    this.realtimeFeedback = true,
    this.maxVibrationPower = 0.8,
    this.vibrationMode = VibrationMode.confirm,
    this.samplingRateHz = 50,
    this.pressThreshold = 200,
    this.calibLight = 0,
    this.calibMedium = 0,
    this.calibStrong = 0,
    this.calibMax = 2000,
  });

  bool get isCalibrated => calibLight > 0 && calibMax > 0;  // 判断是否已完成校准

  DeviceSettings copyWith({         // 复制并修改部分字段（不可变模式标准写法）
    bool? startVibration,
    bool? endVibration,
    bool? realtimeFeedback,
    double? maxVibrationPower,
    VibrationMode? vibrationMode,
    int? samplingRateHz,
    int? pressThreshold,
    int? calibLight,
    int? calibMedium,
    int? calibStrong,
    int? calibMax,
  }) {
    return DeviceSettings(
      startVibration: startVibration ?? this.startVibration,
      endVibration: endVibration ?? this.endVibration,
      realtimeFeedback: realtimeFeedback ?? this.realtimeFeedback,
      maxVibrationPower: maxVibrationPower ?? this.maxVibrationPower,
      vibrationMode: vibrationMode ?? this.vibrationMode,
      samplingRateHz: samplingRateHz ?? this.samplingRateHz,
      pressThreshold: pressThreshold ?? this.pressThreshold,
      calibLight: calibLight ?? this.calibLight,
      calibMedium: calibMedium ?? this.calibMedium,
      calibStrong: calibStrong ?? this.calibStrong,
      calibMax: calibMax ?? this.calibMax,
    );
  }

  Map<String, dynamic> toJson() => {    // 转 Map 用于 Hive 存储
    'startVibration': startVibration,
    'endVibration': endVibration,
    'realtimeFeedback': realtimeFeedback,
    'maxVibrationPower': maxVibrationPower,
    'vibrationMode': vibrationMode.index,  // .index = 枚举的整数编号（0/1/2）
    'samplingRateHz': samplingRateHz,
    'pressThreshold': pressThreshold,
    'calibLight': calibLight,
    'calibMedium': calibMedium,
    'calibStrong': calibStrong,
    'calibMax': calibMax,
  };

  factory DeviceSettings.fromJson(Map<dynamic, dynamic> json) => DeviceSettings(  // 从 Map 还原
    startVibration: json['startVibration'] as bool? ?? true,
    endVibration: json['endVibration'] as bool? ?? true,
    realtimeFeedback: json['realtimeFeedback'] as bool? ?? true,
    maxVibrationPower: (json['maxVibrationPower'] as num?)?.toDouble() ?? 0.8,  // ?. = 安全调用，为 null 就跳过
    vibrationMode: VibrationMode.values[json['vibrationMode'] as int? ?? 1],    // .values[] = 用下标取枚举值
    samplingRateHz: json['samplingRateHz'] as int? ?? 50,
    pressThreshold: json['pressThreshold'] as int? ?? 200,
    calibLight: json['calibLight'] as int? ?? 0,
    calibMedium: json['calibMedium'] as int? ?? 0,
    calibStrong: json['calibStrong'] as int? ?? 0,
    calibMax: json['calibMax'] as int? ?? 2000,
  );

  // 生成发送给 ESP32 的 BLE JSON 命令（maxVibrationPower 转为 PWM 值 0~255）
  Map<String, dynamic> toBleCommand() => {
    'cmd': 'update_settings',
    'startVibration': startVibration,
    'endVibration': endVibration,
    'realtimeFeedback': realtimeFeedback,
    'maxVibrationPower': (maxVibrationPower * 255).round(),  // 0.0~1.0 → 0~255
    'pressThreshold': pressThreshold,
    'samplingRateHz': samplingRateHz,
  };
}
