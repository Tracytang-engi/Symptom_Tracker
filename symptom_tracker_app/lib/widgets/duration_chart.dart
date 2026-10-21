import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class DurationChart extends StatelessWidget {
  final int durationMs;

  const DurationChart({super.key, required this.durationMs});

  @override
  Widget build(BuildContext context) {
    final seconds = durationMs.clamp(0, 0x7fffffffffffffff) / 1000.0;
    final color = Theme.of(context).colorScheme.primary;
    String label(double value) =>
        '${value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '')}s';

    return Semantics(
      label: 'Press duration: ${label(seconds)}',
      child: Column(
        children: [
          SizedBox(
            height: 120,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: seconds > 0 ? seconds : 1,
                minY: 0,
                maxY: 1,
                titlesData: const FlTitlesData(show: false),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                // The fixed vertical position conveys duration, not force.
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      FlSpot(0, 0.5),
                      if (seconds > 0) FlSpot(seconds, 0.5)
                    ],
                    color: color,
                    barWidth: 3,
                    isCurved: false,
                    dotData: const FlDotData(show: true),
                  ),
                ],
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('0s'),
              if (seconds > 0) Text(label(seconds / 2)),
              if (seconds > 0) Text(label(seconds)),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Time (seconds)'),
        ],
      ),
    );
  }
}
