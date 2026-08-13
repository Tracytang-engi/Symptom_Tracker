import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../providers/events_provider.dart';
import '../models/pain_event.dart';
import '../widgets/pain_event_card.dart';

// TimelineScreen：事件时间线页面
// 顶部：日期导航（左右切换）
// 中间：当日疼痛强度折线图（x=时刻，y=峰值%）
// 底部：当天事件卡片列表
class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  DateTime _selectedDay = DateTime.now();  // 当前选中的日期（默认今天）

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(selectedDayEventsProvider(_selectedDay));  // Provider.family：传参获取该天事件
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Timeline'),
      ),
      body: Column(
        children: [
          // ─── 日期导航栏 ───────────────────────────────────────────────────
          _DateNavigator(
            selectedDay: _selectedDay,
            onPrev: () => setState(() => _selectedDay = _selectedDay.subtract(const Duration(days: 1))),
            onNext: () {
              final tomorrow = DateTime.now().add(const Duration(days: 1));
              if (_selectedDay.isBefore(tomorrow)) {   // 不允许跳到未来
                setState(() => _selectedDay = _selectedDay.add(const Duration(days: 1)));
              }
            },
          ),
          const Divider(height: 1),

          // ─── 当日疼痛强度折线图 ───────────────────────────────────────────
          if (events.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
              child: _DayIntensityChart(
                key: ValueKey(_selectedDay.toIso8601String().substring(0, 10)),
                events: events,
                color: primary,
              ),
            ),
            const Divider(height: 1),
          ],

          // ─── 事件列表 ─────────────────────────────────────────────────────
          Expanded(   // Expanded = 占满剩余高度（ListView 在 Column 里必须包 Expanded）
            child: events.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_note_outlined, size: 64, color: primary.withOpacity(0.3)),
                        const SizedBox(height: 12),
                        const Text('No episodes this day', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: events.length,
                    itemBuilder: (_, i) => PainEventCard(
                      event: events[i],
                      onTap: () => context.push('/timeline/${events[i].id}', extra: events[i]),  // extra = 路由传递对象
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── 日期导航栏 ───────────────────────────────────────────────────────────────

class _DateNavigator extends StatelessWidget {
  final DateTime selectedDay;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _DateNavigator({required this.selectedDay, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(selectedDay, DateTime.now());  // 是否为今天
    final label = isToday ? 'Today' : DateFormat('MMM d, yyyy').format(selectedDay);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: onPrev),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: isToday ? null : onNext,   // 今天时禁用（不能跳到未来）
          ),
        ],
      ),
    );
  }
}

// ─── 当日疼痛强度折线图（24h ↔ 10min 分档缩放 + 双指捏合）──────────────────

class _DayIntensityChart extends StatefulWidget {
  final List<PainEvent> events;
  final Color color;

  const _DayIntensityChart({super.key, required this.events, required this.color});

  @override
  State<_DayIntensityChart> createState() => _DayIntensityChartState();
}

class _DayIntensityChartState extends State<_DayIntensityChart> {
  /// 可见时间窗宽度档位：一天 → … → 最短 10 分钟
  static const List<double> _windowHoursSteps = [
    24.0,
    6.0,
    2.0,
    0.5,          // 30 min
    10.0 / 60.0,  // 10 min
  ];

  int _stepIndex = 0; // 0 = 全天
  double _windowStart = 0;
  double _pinchBaseHours = 24;

  double get _windowHours => _windowHoursSteps[_stepIndex];
  bool get _zoomed => _stepIndex > 0;

  double _hourOfDay(DateTime t) => t.hour + t.minute / 60.0 + t.second / 3600.0;

  String _fmtHour(double h) {
    final clamped = h.clamp(0.0, 24.0);
    final hour = clamped.floor().clamp(0, 23);
    final min = ((clamped - hour) * 60).round().clamp(0, 59);
    if (clamped >= 24) return '24:00';
    return '${hour.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }

  String _windowLabel(double hours) {
    if (hours >= 23.9) return 'Full day (24h)';
    if (hours >= 1) return '${hours == hours.roundToDouble() ? hours.toInt() : hours}h window';
    final mins = (hours * 60).round();
    return '${mins}min window';
  }

  double _eventCenter() {
    final hours = widget.events.map((e) => _hourOfDay(e.startTime)).toList()..sort();
    if (hours.isEmpty) return 12.0;
    return hours[hours.length ~/ 2];
  }

  void _setWindowHours(double hours, {double? keepCenter}) {
    final center = keepCenter ?? (_windowStart + _windowHours / 2);
    // 落到最近且不超过目标的档位；捏合时选最接近的档
    var best = 0;
    var bestDiff = double.infinity;
    for (var i = 0; i < _windowHoursSteps.length; i++) {
      final d = (_windowHoursSteps[i] - hours).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = i;
      }
    }
    final w = _windowHoursSteps[best];
    setState(() {
      _stepIndex = best;
      _windowStart = (center - w / 2).clamp(0.0, 24.0 - w);
    });
  }

  void _zoomIn() {
    if (_stepIndex >= _windowHoursSteps.length - 1) return;
    final center = _zoomed ? _windowStart + _windowHours / 2 : _eventCenter();
    final next = _stepIndex + 1;
    final w = _windowHoursSteps[next];
    setState(() {
      _stepIndex = next;
      _windowStart = (center - w / 2).clamp(0.0, 24.0 - w);
    });
  }

  void _zoomOut() {
    if (_stepIndex <= 0) return;
    final center = _windowStart + _windowHours / 2;
    final next = _stepIndex - 1;
    final w = _windowHoursSteps[next];
    setState(() {
      _stepIndex = next;
      _windowStart = next == 0 ? 0.0 : (center - w / 2).clamp(0.0, 24.0 - w);
    });
  }

  void _pan(double deltaHours) {
    if (!_zoomed) return;
    setState(() {
      _windowStart = (_windowStart + deltaHours).clamp(0.0, 24.0 - _windowHours);
    });
  }

  double _xInterval(double span) {
    if (span >= 20) return 6;
    if (span >= 5) return 1;
    if (span >= 1.5) return 0.5;
    if (span >= 0.4) return 10 / 60; // 10 min ticks
    return 5 / 60; // 5 min ticks for 10min window
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    // 按时间排序，直接 (时刻 → 峰值%) plot，不做曲线插值（曲线贝塞尔会在 x 上走回头）
    final sorted = [...widget.events]..sort((a, b) => a.startTime.compareTo(b.startTime));
    final spots = <FlSpot>[];
    for (final e in sorted) {
      var x = _hourOfDay(e.startTime);
      // 同一时刻多个点：略微右移，保证 x 严格递增，折线不会叠回去
      if (spots.isNotEmpty && x <= spots.last.x) {
        x = spots.last.x + 1e-4;
      }
      spots.add(FlSpot(x, (e.peakForce * 100).clamp(0.0, 100.0)));
    }

    final minX = _zoomed ? _windowStart : 0.0;
    final maxX = _zoomed ? _windowStart + _windowHours : 24.0;
    final span = maxX - minX;
    final xInterval = _xInterval(span);
    final panStep = (span / 3).clamp(5 / 60, 2.0);

    final rangeLabel = _zoomed
        ? '${_fmtHour(minX)} – ${_fmtHour(maxX)} · ${_windowLabel(_windowHours)}'
        : 'Full day (24h)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Peak intensity',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(rangeLabel,
                        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
                    const Text('Pinch or use + / − to zoom (min 10 min)',
                        style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
              if (_zoomed) ...[
                IconButton(
                  tooltip: 'Earlier',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _windowStart <= 0 ? null : () => _pan(-panStep),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: 'Later',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _windowStart >= 24.0 - _windowHours
                      ? null
                      : () => _pan(panStep),
                  visualDensity: VisualDensity.compact,
                ),
              ],
              IconButton(
                tooltip: 'Zoom in (down to 10 min)',
                icon: const Icon(Icons.zoom_in),
                onPressed:
                    _stepIndex >= _windowHoursSteps.length - 1 ? null : _zoomIn,
                visualDensity: VisualDensity.compact,
                color: color,
              ),
              IconButton(
                tooltip: 'Zoom out (up to full day)',
                icon: const Icon(Icons.zoom_out),
                onPressed: _stepIndex <= 0 ? null : _zoomOut,
                visualDensity: VisualDensity.compact,
                color: color,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 180,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onScaleStart: (_) => _pinchBaseHours = _windowHours,
            onScaleUpdate: (details) {
              // scale > 1 = 双指张开放大时间分辨率（窗口变短）
              if ((details.scale - 1.0).abs() < 0.03) return;
              final target = (_pinchBaseHours / details.scale).clamp(
                _windowHoursSteps.last,
                _windowHoursSteps.first,
              );
              _setWindowHours(target);
            },
            child: LineChart(
              LineChartData(
                minX: minX,
                maxX: maxX,
                minY: 0,
                maxY: 100,
                clipData: const FlClipData.all(),
                gridData: FlGridData(
                  drawVerticalLine: true,
                  drawHorizontalLine: true,
                  horizontalInterval: 25,
                  verticalInterval: xInterval,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: color.withOpacity(0.08),
                    strokeWidth: 1,
                  ),
                  getDrawingVerticalLine: (_) => FlLine(
                    color: color.withOpacity(0.08),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 25,
                      reservedSize: 36,
                      getTitlesWidget: (val, _) => Text(
                        '${val.round()}%',
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: xInterval,
                      reservedSize: 22,
                      getTitlesWidget: (val, _) {
                        if (val < minX - 0.01 || val > maxX + 0.01) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          span <= 6 ? _fmtHour(val) : '${val.round()}:00',
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touched) => touched.map((t) {
                      return LineTooltipItem(
                        '${_fmtHour(t.x)}\nPeak ${t.y.round()}%',
                        const TextStyle(
                            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      );
                    }).toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: false, // 直线连接数据点，避免平滑曲线在时间轴上回头
                    color: color,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                        radius: _zoomed ? 5 : 4,
                        color: color,
                        strokeWidth: 2,
                        strokeColor: Colors.white,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [color.withOpacity(0.25), color.withOpacity(0.0)],
                      ),
                    ),
                  ),
                ],
              ),
              duration: const Duration(milliseconds: 220),
            ),
          ),
        ),
      ],
    );
  }
}
