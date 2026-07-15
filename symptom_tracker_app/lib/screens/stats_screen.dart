import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/events_provider.dart';

// StatsScreen：统计页
// 显示：7 天柱状图 + 今日/周数量 + 时段分布（0~6/6~12/12~18/18~24）
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weeklyCounts = ref.watch(weeklyCountProvider);     // 每天发作次数列表（7个DayCount）
    final last7 = ref.watch(last7DaysEventsProvider);        // 近7天所有事件
    final todayEvents = ref.watch(todayEventsProvider);      // 今日事件

    final primary = Theme.of(context).colorScheme.primary;
    final maxCount = weeklyCounts.map((d) => d.count).fold(1, (a, b) => a > b ? a : b);  // .fold = 累进计算最大值

    // 24 小时按时段统计（每 6 小时一段）
    final hourBuckets = List.filled(4, 0);                   // List.filled(n, v) = 生成 n 个初始值为 v 的列表
    for (final e in last7) {
      final bucket = e.startTime.hour ~/ 6;                  // ~/ = 整除：0-5→0, 6-11→1, ...
      if (bucket < 4) hourBuckets[bucket]++;
    }
    final bucketLabels = ['0–6', '6–12', '12–18', '18–24'];

    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── 数字摘要 ────────────────────────────────────────────────────
            Row(
              children: [
                Expanded(child: _StatCard(label: 'Today', value: '${todayEvents.length}',  unit: 'episodes', color: primary)),
                const SizedBox(width: 12),
                Expanded(child: _StatCard(label: '7-Day Total', value: '${last7.length}', unit: 'episodes', color: primary)),
              ],
            ),
            const SizedBox(height: 12),

            // 平均峰值
            if (last7.isNotEmpty) ...[
              _StatCard(
                label: 'Avg Peak (7d)',
                value: '${(last7.map((e) => e.peakForce).reduce((a, b) => a + b) / last7.length * 100).round()}%',  // reduce 累加求平均
                unit: 'peak force',
                color: primary,
              ),
              const SizedBox(height: 16),
            ],

            // ─── 7 天柱状图 ──────────────────────────────────────────────────
            Text('7-Day Trend', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: BarChart(               // BarChart = fl_chart 柱状图
                BarChartData(
                  maxY: maxCount.toDouble() + 1,   // y 轴最大值（稍微留余量）
                  barGroups: weeklyCounts.asMap().entries.map((e) {  // .asMap() = 获取 {下标: 值}
                    return BarChartGroupData(
                      x: e.key,              // 第几天（0~6）
                      barRods: [
                        BarChartRodData(
                          toY: e.value.count.toDouble(),
                          color: primary,
                          width: 18,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ],
                    );
                  }).toList(),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (x, _) {
                          final day = weeklyCounts[x.toInt()].date;
                          return Text(DateFormat('E').format(day), style: const TextStyle(fontSize: 11));  // 'E' = 星期缩写（Mon/Tue…）
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        interval: 1,                          // 每 1 次一条网格线
                        getTitlesWidget: (v, _) => v == v.roundToDouble()   // 只显示整数
                            ? Text('${v.round()}', style: const TextStyle(fontSize: 10))
                            : const SizedBox.shrink(),
                      ),
                    ),
                    topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(drawVerticalLine: false),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ─── 时段分布 ────────────────────────────────────────────────────
            Text('Time of Day (7d)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...List.generate(4, (i) {                         // 生成 4 个时段进度条
              final frac = last7.isEmpty ? 0.0 : hourBuckets[i] / last7.length;  // 占比
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 48, child: Text(bucketLabels[i], style: const TextStyle(fontSize: 12))),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: frac,                        // 0.0~1.0 对应 0%~100%
                          minHeight: 16,
                          backgroundColor: primary.withOpacity(0.1),
                          valueColor: AlwaysStoppedAnimation(primary),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text(' ${hourBuckets[i]}', textAlign: TextAlign.right),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// 单个统计数字卡片
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _StatCard({required this.label, required this.value, required this.unit, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            RichText(                    // RichText = 混合多种字体样式的文本
              text: TextSpan(
                children: [
                  TextSpan(text: value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
                  const TextSpan(text: ' '),
                  TextSpan(text: unit, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
