import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symptom_tracker_app/widgets/duration_chart.dart';

void main() {
  for (final duration in [0, 1, 1234, 5000, 125000]) {
    testWidgets('Duration $duration renders time without pressure',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body:
              SizedBox(width: 288, child: DurationChart(durationMs: duration)),
        ),
      ));
      final data = tester.widget<LineChart>(find.byType(LineChart)).data;
      expect(data.titlesData.show, isFalse);
      expect(data.lineTouchData.enabled, isFalse);
      final spots = data.lineBarsData.single.spots;
      expect(spots.first.x, 0);
      expect(spots.last.x, duration / 1000);
      expect(spots.every((spot) => spot.y == 0.5), isTrue);
      expect(find.text('Time (seconds)'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(tester.takeException(), isNull);
      if (duration == 1234) expect(find.text('1.234s'), findsOneWidget);
    });
  }
}
