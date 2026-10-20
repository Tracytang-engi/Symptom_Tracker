import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symptom_tracker_app/models/pain_event.dart';
import 'package:symptom_tracker_app/widgets/press_timer_dialog.dart';
import 'package:symptom_tracker_app/widgets/pain_event_card.dart';

void main() {
  Future<void> open(
      WidgetTester tester, void Function(PressTiming?) result) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () async => result(await showDialog<PressTiming>(
                    context: context,
                    builder: (_) => const PressTimerDialog())),
                child: const Text('Open')))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Hold and release returns actual duration once', (tester) async {
    PressTiming? timing;
    var saves = 0;
    await open(tester, (value) {
      timing = value;
      saves++;
    });
    final press = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('press-timer-pad'))));
    await tester.pump();
    expect(find.text('Release to save'), findsOneWidget);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)));
    await press.up();
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(timing!.duration.inMilliseconds, greaterThanOrEqualTo(100));
    expect(timing!.duration.inMilliseconds, lessThan(5000));
  });

  testWidgets('Cancelled gesture does not save', (tester) async {
    PressTiming? timing;
    await open(tester, (value) => timing = value);
    final press = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('press-timer-pad'))));
    await tester.pump();
    await press.cancel();
    await tester.pump();
    expect(find.text('Recording cancelled. No entry saved.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(timing, isNull);
  });

  testWidgets('Backgrounding cancels the active press', (tester) async {
    var saved = false;
    await open(tester, (value) => saved = value != null);
    final press = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('press-timer-pad'))));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await press.up();
    await tester.pump();
    expect(saved, isFalse);
    expect(find.text('Hold to record'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('Duration-only entry round-trips and shows no fake pressure',
      (tester) async {
    final start = DateTime(2026, 10, 20, 9);
    final event = PainEvent.fromJson(PainEvent(
      id: 'test',
      profileId: 'default',
      startTime: start,
      endTime: start.add(const Duration(milliseconds: 1234)),
      durationMs: 1234,
      meanForce: 0,
      peakForce: 0,
      fromDevice: false,
    ).toJson());
    expect(event.durationMs, 1234);
    expect(event.formattedDuration, '1.2s');
    expect(event.hasPressureData, isFalse);
    expect(event.rawSamples, isEmpty);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: PainEventCard(event: event))));
    expect(find.text('1.2s'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('Peak'), findsNothing);
    expect(event.copyWith(fromDevice: true).hasPressureData, isTrue);
  });
}
