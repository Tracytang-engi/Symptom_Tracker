// PainEvent：一次完整的疼痛发作记录（从按下 FSR 到松手）

class PainEvent {
  final String id;             // 唯一标识，用 UUID 生成
  final String profileId;      // 所属症状档案的 ID
  final DateTime startTime;    // DateTime = Dart 内置日期时间类型
  final DateTime endTime;
  final int durationMs;        // 持续时长，单位毫秒
  final double meanForce;      // double = 浮点数；校准后的平均力度 0.0~1.0
  final double peakForce;      // 峰值力度 0.0~1.0
  final List<int> rawSamples;  // List<int> = 整数列表；原始 ADC 采样序列
  final List<String> tags;     // 贴在这次事件上的标签 ID 列表
  /// 本地语音文件路径（手机录 + 从设备下载后）
  final List<String> voiceNotePaths;
  final String? textNote;      // 文字备注
  final bool fromDevice;       // true = 硬件按压，false = 手机手动输入
  /// ESP32 疼痛开始 millis，对应设备文件名如 /rec_12345_0.wav
  final String? deviceEventKey;
  /// 尚未下载到手机的 SPIFFS 路径
  final List<String> pendingDeviceRecPaths;

  const PainEvent({
    required this.id,
    required this.profileId,
    required this.startTime,
    required this.endTime,
    required this.durationMs,
    required this.meanForce,
    required this.peakForce,
    this.rawSamples = const [],
    this.tags = const [],
    this.voiceNotePaths = const [],
    this.textNote,
    this.fromDevice = true,
    this.deviceEventKey,
    this.pendingDeviceRecPaths = const [],
  });

  /// 兼容旧字段：取第一条本地语音路径
  String? get voiceNotePath =>
      voiceNotePaths.isEmpty ? null : voiceNotePaths.first;

  PainEvent copyWith({
    String? id,
    String? profileId,
    DateTime? startTime,
    DateTime? endTime,
    int? durationMs,
    double? meanForce,
    double? peakForce,
    List<int>? rawSamples,
    List<String>? tags,
    List<String>? voiceNotePaths,
    String? textNote,
    bool? fromDevice,
    String? deviceEventKey,
    List<String>? pendingDeviceRecPaths,
    bool clearTextNote = false,
  }) {
    return PainEvent(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationMs: durationMs ?? this.durationMs,
      meanForce: meanForce ?? this.meanForce,
      peakForce: peakForce ?? this.peakForce,
      rawSamples: rawSamples ?? this.rawSamples,
      tags: tags ?? this.tags,
      voiceNotePaths: voiceNotePaths ?? this.voiceNotePaths,
      textNote: clearTextNote ? null : (textNote ?? this.textNote),
      fromDevice: fromDevice ?? this.fromDevice,
      deviceEventKey: deviceEventKey ?? this.deviceEventKey,
      pendingDeviceRecPaths:
          pendingDeviceRecPaths ?? this.pendingDeviceRecPaths,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'profileId': profileId,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'durationMs': durationMs,
        'meanForce': meanForce,
        'peakForce': peakForce,
        'rawSamples': rawSamples,
        'tags': tags,
        'voiceNotePaths': voiceNotePaths,
        // 旧字段：保留第一条，兼容旧版读盘
        if (voiceNotePath != null) 'voiceNotePath': voiceNotePath,
        'textNote': textNote,
        'fromDevice': fromDevice,
        'deviceEventKey': deviceEventKey,
        'pendingDeviceRecPaths': pendingDeviceRecPaths,
      };

  factory PainEvent.fromJson(Map<dynamic, dynamic> json) {
    final paths = <String>[];
    final list = json['voiceNotePaths'] as List?;
    if (list != null) {
      for (final e in list) {
        if (e is String && e.isNotEmpty) paths.add(e);
      }
    }
    final legacy = json['voiceNotePath'] as String?;
    if (legacy != null && legacy.isNotEmpty && !paths.contains(legacy)) {
      paths.insert(0, legacy);
    }

    return PainEvent(
      id: json['id'] as String,
      profileId: json['profileId'] as String? ?? 'default',
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: DateTime.parse(json['endTime'] as String),
      durationMs: json['durationMs'] as int,
      meanForce: (json['meanForce'] as num).toDouble(),
      peakForce: (json['peakForce'] as num).toDouble(),
      rawSamples: (json['rawSamples'] as List?)
              ?.map((e) => e as int)
              .toList() ??
          [],
      tags: (json['tags'] as List?)?.map((e) => e as String).toList() ?? [],
      voiceNotePaths: paths,
      textNote: json['textNote'] as String?,
      fromDevice: json['fromDevice'] as bool? ?? true,
      deviceEventKey: json['deviceEventKey'] as String?,
      pendingDeviceRecPaths: (json['pendingDeviceRecPaths'] as List?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  String get formattedDuration {
    final s = durationMs ~/ 1000;
    if (s < 60) return '${s}s';
    return '${s ~/ 60}m ${s % 60}s';
  }

  String get peakForcePercent => '${(peakForce * 100).round()}%';
  String get meanForcePercent => '${(meanForce * 100).round()}%';

  bool get isSameDay {
    final now = DateTime.now();
    return startTime.year == now.year &&
        startTime.month == now.month &&
        startTime.day == now.day;
  }
}
