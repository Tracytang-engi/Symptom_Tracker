import 'dart:math';                   // math 库提供 pi（圆周率）
import 'package:flutter/material.dart';

// PressureGauge：实时压力弧形仪表盘（用 CustomPainter 手绘）
// pressure = 0.0~1.0，recording 时有脉冲扩张动画
class PressureGauge extends StatefulWidget {  // StatefulWidget = 有自己内部状态的 Widget
  final double pressure;
  final bool isRecording;
  final double size;

  const PressureGauge({
    super.key,
    required this.pressure,
    this.isRecording = false,
    this.size = 220,
  });

  @override
  State<PressureGauge> createState() => _PressureGaugeState();  // 创建对应的 State 对象
}

// State<PressureGauge> = 与 PressureGauge 配对的状态类
// TickerProviderStateMixin = 提供 vsync（动画时钟）的 mixin；mixin = 混入，给类添加功能
class _PressureGaugeState extends State<PressureGauge>
    with TickerProviderStateMixin {
  late AnimationController _pressureAnim;  // late = 延迟初始化（initState 里赋值）
  late AnimationController _pulseAnim;
  late Animation<double> _pressureValue;   // Animation<double> = 在两个 double 之间插值的动画

  @override
  void initState() {                       // initState = Widget 第一次挂载时调用（只调一次）
    super.initState();
    _pressureAnim = AnimationController(
      vsync: this,                         // vsync = 把动画绑定到屏幕刷新率（省电）；this = 当前 State 提供 vsync
      duration: const Duration(milliseconds: 150),
    );
    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);             // .. = 级联；.repeat(reverse) = 来回循环播放

    _pressureValue = Tween<double>(begin: 0, end: 0).animate(  // Tween = 起止值之间的插值器
      CurvedAnimation(parent: _pressureAnim, curve: Curves.easeOut),  // CurvedAnimation = 加缓动曲线
    );
  }

  @override
  void didUpdateWidget(PressureGauge old) {  // didUpdateWidget = 父 Widget 重建、传入新参数时调用
    super.didUpdateWidget(old);
    if (old.pressure != widget.pressure) {   // widget = 当前最新的 Widget 属性（区别于 old）
      // 从当前动画值出发，平滑过渡到新压力值
      _pressureValue = Tween<double>(
        begin: _pressureValue.value,         // .value = 动画当前插值
        end: widget.pressure,
      ).animate(CurvedAnimation(parent: _pressureAnim, curve: Curves.easeOut));
      _pressureAnim.forward(from: 0);        // .forward(from: 0) = 从头开始播放动画
    }
  }

  @override
  void dispose() {      // dispose = Widget 从树上移除时调用，必须释放 AnimationController
    _pressureAnim.dispose();
    _pulseAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;  // 从主题取主色
    return AnimatedBuilder(
      animation: Listenable.merge([_pressureAnim, _pulseAnim]),  // 同时监听两个动画
      builder: (_, __) {       // builder 每帧都调用，__ = 不需要 child 参数
        final pulse = widget.isRecording ? 1.0 + _pulseAnim.value * 0.04 : 1.0;  // 记录时轻微缩放
        return SizedBox(
          width: widget.size * pulse,
          height: widget.size * pulse,
          child: CustomPaint(             // CustomPaint = 手动调用 paint() 在画布上绘制
            painter: _GaugePainter(
              pressure: _pressureValue.value,
              color: color,
              isRecording: widget.isRecording,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,  // mainAxisSize.min = Column 只占内容高度
                children: [
                  Text(
                    '${(_pressureValue.value * 100).round()}%',
                    style: TextStyle(
                      fontSize: widget.size * 0.16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  if (widget.isRecording)        // if(...) 在 Widget 列表里 = 条件显示
                    Text(
                      'Recording...',
                      style: TextStyle(fontSize: widget.size * 0.07, color: color),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// CustomPainter = 自定义绘制类，重写 paint() 方法描述怎么画
class _GaugePainter extends CustomPainter {
  final double pressure;
  final Color color;
  final bool isRecording;

  _GaugePainter({required this.pressure, required this.color, required this.isRecording});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);  // Offset = 2D 坐标点
    final radius = size.width / 2 - 12;
    const startAngle = -pi * 0.75;  // 从 7 点钟方向开始（-135°，pi 是弧度制）
    const sweepMax  =  pi * 1.5;    // 扫过 270° 的弧

    // 绘制灰色背景轨道
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),  // drawArc 的矩形边界框
      startAngle,
      sweepMax,
      false,         // false = 不填充扇形，只画弧线
      Paint()        // Paint = 画笔配置（颜色、粗细、样式）
        ..color = color.withOpacity(0.12)
        ..style = PaintingStyle.stroke  // stroke = 只画轮廓
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round,  // strokeCap.round = 端点为圆弧
    );

    // 绘制绿色压力弧（按压力大小扫不同角度）
    if (pressure > 0) {
      final gradient = SweepGradient(    // SweepGradient = 沿角度方向的渐变
        startAngle: startAngle,
        endAngle: startAngle + sweepMax,
        colors: [color.withOpacity(0.6), color],
      );
      final paint = Paint()
        ..shader = gradient.createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepMax * pressure,  // 弧长 = 最大弧 × 当前压力比例
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>   // shouldRepaint = 返回 true 时才重绘（优化性能）
      old.pressure != pressure || old.isRecording != isRecording;
}
