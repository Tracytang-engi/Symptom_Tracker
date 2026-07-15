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
  final String? voiceNotePath; // ? 表示可为 null；语音备注文件路径
  final String? textNote;      // 文字备注
  final bool fromDevice;       // true = 硬件按压，false = 手机手动输入

  const PainEvent({            // const 构造函数：对象在编译期即可确定，提升性能
    required this.id,
    required this.profileId,
    required this.startTime,
    required this.endTime,
    required this.durationMs,
    required this.meanForce,
    required this.peakForce,
    this.rawSamples = const [],  // const [] = 编译期常量空列表，节省内存
    this.tags = const [],
    this.voiceNotePath,          // 可空字段不传时默认 null
    this.textNote,
    this.fromDevice = true,
  });

  PainEvent copyWith({           // 产生"修改了部分字段"的新对象，原对象不变（不可变模式）
    String? id,
    String? profileId,
    DateTime? startTime,
    DateTime? endTime,
    int? durationMs,
    double? meanForce,
    double? peakForce,
    List<int>? rawSamples,
    List<String>? tags,
    String? voiceNotePath,
    String? textNote,
    bool? fromDevice,
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
      voiceNotePath: voiceNotePath ?? this.voiceNotePath,  // 注意：null 也会被 ?? 跳过，保留旧值
      textNote: textNote ?? this.textNote,
      fromDevice: fromDevice ?? this.fromDevice,
    );
  }

  Map<String, dynamic> toJson() => {   // 序列化：把对象转为 Map，存入 Hive
    'id': id,
    'profileId': profileId,
    'startTime': startTime.toIso8601String(),  // DateTime → 标准 ISO 字符串（可存储）
    'endTime': endTime.toIso8601String(),
    'durationMs': durationMs,
    'meanForce': meanForce,
    'peakForce': peakForce,
    'rawSamples': rawSamples,
    'tags': tags,
    'voiceNotePath': voiceNotePath,
    'textNote': textNote,
    'fromDevice': fromDevice,
  };

  factory PainEvent.fromJson(Map<dynamic, dynamic> json) => PainEvent(  // 反序列化：从 Map 还原对象
    id: json['id'] as String,
    profileId: json['profileId'] as String? ?? 'default',
    startTime: DateTime.parse(json['startTime'] as String),  // ISO 字符串 → DateTime
    endTime: DateTime.parse(json['endTime'] as String),
    durationMs: json['durationMs'] as int,
    meanForce: (json['meanForce'] as num).toDouble(),        // num = int 或 double 的父类
    peakForce: (json['peakForce'] as num).toDouble(),
    rawSamples: (json['rawSamples'] as List?)                // List? = 可能为 null 的列表
        ?.map((e) => e as int)                               // .map() = 逐元素转换
        .toList() ?? [],                                     // .toList() 转为 List；为 null 则用 []
    tags: (json['tags'] as List?)?.map((e) => e as String).toList() ?? [],
    voiceNotePath: json['voiceNotePath'] as String?,
    textNote: json['textNote'] as String?,
    fromDevice: json['fromDevice'] as bool? ?? true,
  );

  // get = 只读计算属性，每次访问时动态计算，不存储
  String get formattedDuration {         // 把毫秒格式化为"48s"或"2m 5s"
    final s = durationMs ~/ 1000;        // ~/ = 整除（取整数部分）
    if (s < 60) return '${s}s';          // $变量 = 字符串插值
    return '${s ~/ 60}m ${s % 60}s';    // % = 取余
  }

  String get peakForcePercent => '${(peakForce * 100).round()}%';   // .round() = 四舍五入
  String get meanForcePercent => '${(meanForce * 100).round()}%';

  bool get isSameDay {                   // 判断事件是否发生在今天
    final now = DateTime.now();          // DateTime.now() = 当前时间
    return startTime.year == now.year &&
        startTime.month == now.month &&
        startTime.day == now.day;        // && = 逻辑与（全部为真才为真）
  }
}
