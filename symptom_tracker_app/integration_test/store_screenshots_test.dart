import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:symptom_tracker_app/app.dart';
import 'package:symptom_tracker_app/models/pain_event.dart';
import 'package:symptom_tracker_app/models/user_settings.dart';
import 'package:symptom_tracker_app/providers/ble_provider.dart';
import 'package:symptom_tracker_app/screens/home_screen.dart';
import 'package:symptom_tracker_app/screens/timeline_screen.dart';
import 'package:symptom_tracker_app/screens/event_detail_screen.dart';
import 'package:symptom_tracker_app/screens/settings/settings_screen.dart';
import 'package:symptom_tracker_app/services/reminder_service.dart';
import 'package:symptom_tracker_app/services/storage_service.dart';

// Only suppress background notifications in this test entry point, not app UI.
class ScreenshotReminders extends ReminderService {
  @override
  Future<void> consumeLaunchNotification() async {}

  @override
  Future<void> syncDaily(UserSettings settings) async {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetsApp.debugAllowBannerOverride = false;

  testWidgets('Capture real iPad screens with fictional local records',
      (tester) async {
    await StorageService.init();
    final storage = StorageService();
    await storage.deleteAllEvents();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 9);
    final event = PainEvent(
      id: 'store-demo-episode',
      profileId: 'default',
      startTime: start,
      endTime: start.add(const Duration(seconds: 30)),
      durationMs: 30000,
      meanForce: 0.25,
      peakForce: 0.4,
      textNote: 'Example entry for demonstration only.',
      fromDevice: false,
    );
    await storage.saveEvent(event);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        bleEventListenerProvider.overrideWith((ref) {}),
        reminderServiceProvider.overrideWithValue(ScreenshotReminders()),
      ],
      child: const SymptomTrackerApp(),
    ));

    Future<void> capture(String name, Type screen) async {
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.byType(screen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot(name);
    }

    await capture('01-home', HomeScreen);
    final router = GoRouter.of(tester.element(find.byType(HomeScreen)));
    router.go('/timeline');
    await capture('02-timeline', TimelineScreen);
    router.go('/timeline/${event.id}', extra: event);
    await capture('03-episode-detail', EventDetailScreen);
    router.go('/settings');
    await capture('04-settings', SettingsScreen);
  });
}
