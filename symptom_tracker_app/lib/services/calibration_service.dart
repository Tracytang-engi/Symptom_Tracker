import '../models/device_settings.dart';

// CalibrationService：三步个人力度校准
// 采集三种力度的中位数 ADC 值，用分段线性插值把原始 ADC 映射到 0.0~1.0
class CalibrationService {
  final List<int> _currentSamples = [];   // 当前步骤正在采集的样本
  bool _isCollecting = false;

  bool get isCollecting => _isCollecting;

  // ─── 采样控制 ──────────────────────────────────────────────────────────────

  void addSample(int rawValue) {
    if (_isCollecting) {                  // 只有正在采集时才收集
      _currentSamples.add(rawValue);
    }
  }

  void startCollecting() {
    _currentSamples.clear();             // .clear() = 清空列表
    _isCollecting = true;
  }

  int stopCollectingAndGetMedian() {     // 停止采集并返回中位数（比平均数更抗噪声干扰）
    _isCollecting = false;
    if (_currentSamples.isEmpty) return 0;

    final sorted = List<int>.from(_currentSamples)..sort();  // ..sort() = 原地排序（级联）
    final mid = sorted.length ~/ 2;                          // ~/ = 整除，取中间索引
    return sorted.length.isOdd                               // .isOdd = 判断是否为奇数
        ? sorted[mid]                                        // 奇数个 → 直接取中间
        : ((sorted[mid - 1] + sorted[mid]) / 2).round();    // 偶数个 → 取两中间值的均值
  }

  // ─── 力度映射 ──────────────────────────────────────────────────────────────

  // static = 不需要实例，直接 CalibrationService.mapToRelative() 调用
  static double mapToRelative(int raw, DeviceSettings settings) {
    if (!settings.isCalibrated) {
      // 未校准时：直接线性映射（用 calibMax 作为满量程）
      return (raw / settings.calibMax).clamp(0.0, 1.0);  // .clamp(a,b) = 限制在 [a,b] 范围内
    }

    // 超过「最大认为力度」→ 直接 100%
    if (raw >= settings.calibMax) return 1.0;

    // Strong 对应相对力度 ≈ strong/calibMax（默认 calibMax=1.1*strong → ≈0.91）
    // 若 ADC 已顶满导致 calibMax≈strong，则 Strong 视为 100%
    final strongRel = settings.calibMax <= settings.calibStrong
        ? 1.0
        : (settings.calibStrong / settings.calibMax).clamp(0.5, 1.0);

    // 校准后：分段线性插值
    final segments = [
      _Segment(0,                   0.0,  settings.calibLight,  0.25),
      _Segment(settings.calibLight,  0.25, settings.calibMedium, 0.5),
      _Segment(settings.calibMedium, 0.5,  settings.calibStrong, strongRel),
      _Segment(settings.calibStrong, strongRel, settings.calibMax, 1.0),
    ];

    for (final seg in segments) {
      if (raw <= seg.rawMax) {
        return seg.interpolate(raw).clamp(0.0, 1.0);
      }
    }

    return 1.0;
  }

  static List<double> mapSamples(List<int> raws, DeviceSettings settings) {
    return raws.map((r) => mapToRelative(r, settings)).toList();  // 批量映射整个采样序列
  }

  static double computeMean(List<int> raws, DeviceSettings settings) {
    if (raws.isEmpty) return 0;
    final relatives = mapSamples(raws, settings);
    return relatives.reduce((a, b) => a + b) / relatives.length;  // .reduce() = 累加求和
  }

  static double computePeak(List<int> raws, DeviceSettings settings) {
    if (raws.isEmpty) return 0;
    final relatives = mapSamples(raws, settings);
    return relatives.reduce((a, b) => a > b ? a : b);  // 取最大值
  }
}

// 私有辅助类（_ 开头），描述一段线性区间
class _Segment {
  final int rawMin;
  final double relMin;
  final int rawMax;
  final double relMax;

  const _Segment(this.rawMin, this.relMin, this.rawMax, this.relMax);

  double interpolate(int raw) {
    if (rawMax == rawMin) return relMin;  // 防止除以零
    final t = (raw - rawMin) / (rawMax - rawMin);  // t = 在本段内的相对位置（0.0~1.0）
    return relMin + t * (relMax - relMin);           // 线性插值公式：start + t * (end - start)
  }
}
