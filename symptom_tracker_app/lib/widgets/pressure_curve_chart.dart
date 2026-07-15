import 'package:fl_chart/fl_chart.dart';    // fl_chart = 图表库
import 'package:flutter/material.dart';
import '../models/pain_event.dart';
import '../services/calibration_service.dart';
import '../models/device_settings.dart';

// PressureCurveChart：把一次事件的原始 ADC 采样序列画成折线图
// x 轴 = 时间（秒），y 轴 = 相对力度（0~100%）
class PressureCurveChart extends StatelessWidget {
  final PainEvent event;
  final DeviceSettings deviceSettings;
  final double height;

  const PressureCurveChart({
    super.key,
    required this.event,
    required this.deviceSettings,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;

    if (event.rawSamples.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('No curve data', style: TextStyle(color: color.withOpacity(0.5))),
        ),
      );
    }

    // 把原始 ADC 列表映射为 0.0~1.0 的相对力度列表
    final relatives = CalibrationService.mapSamples(event.rawSamples, deviceSettings);

    // 50Hz 采样 → 每个点间隔 20ms
    const intervalMs = 20.0;
    // .asMap() = 转为 {下标: 值} 的 Map；.entries = 所有键值对
    final spots = relatives.asMap().entries.map((e) {
      final xSec = e.key * intervalMs / 1000.0;          // 下标 × 间隔 = 时间（秒）
      final y    = (e.value * 100).clamp(0.0, 100.0);    // 转为百分比，限制在 0~100
      return FlSpot(xSec, y);                            // FlSpot = fl_chart 的坐标点
    }).toList();

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 100,
          gridData: FlGridData(
            drawHorizontalLine: true,
            drawVerticalLine: false,
            horizontalInterval: 25,   // 网格线每 25% 一条
            getDrawingHorizontalLine: (_) => FlLine(
              color: color.withOpacity(0.1),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),   // 不显示外边框
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 25,
                reservedSize: 36,    // 留给坐标文字的宽度（像素）
                getTitlesWidget: (val, _) => Text('${val.round()}%', style: const TextStyle(fontSize: 10)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (val, _) => Text('${val.toStringAsFixed(1)}s', style: const TextStyle(fontSize: 10)),
              ),
            ),
            topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,             // 平滑曲线（贝塞尔插值）
              curveSmoothness: 0.35,      // 平滑程度（0=折线，1=最圆润）
              color: color,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),   // 不在每个点上画圆点
              belowBarData: BarAreaData(               // 曲线下方填充渐变
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [color.withOpacity(0.3), color.withOpacity(0.0)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
