import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/user_settings.dart';

/// 每日摘要、断连、低电量通知。低电量只在设备真的上报百分比时触发。
class ReminderService {
  final FlutterLocalNotificationsPlugin _notif = FlutterLocalNotificationsPlugin();
  bool _tzReady = false;
  bool _inited = false;
  bool _lowBatteryLatched = false;

  /// 通知被点开时回调。每日摘要的 payload 是 [timelinePayload]。
  void Function(String payload)? onOpenPayload;

  static const timelinePayload = 'timeline';
  static const _dailyId = 7101;
  static const _disconnectId = 7102;
  static const _lowBatteryId = 7103;

  Future<void> init() async {
    if (_inited) return;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _notif.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onResponse,
    );
    _inited = true;
    if (_tzReady) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.local);
    _tzReady = true;
  }

  void _onResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    onOpenPayload?.call(payload);
  }

  /// 应用被通知从关闭状态拉起时，补一次跳转。
  Future<void> consumeLaunchNotification() async {
    await init();
    final details = await _notif.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return;
    final payload = details.notificationResponse?.payload;
    if (payload == null || payload.isEmpty) return;
    onOpenPayload?.call(payload);
  }

  Future<void> _ensureTz() async {
    await init();
  }

  Future<void> syncDaily(UserSettings settings) async {
    await _ensureTz();
    if (!settings.dailySummaryReminder) {
      await _notif.cancel(_dailyId);
      return;
    }

    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, 20);
    if (!when.isAfter(now)) {
      when = when.add(const Duration(days: 1));
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'reminders',
        'Reminders',
        channelDescription: 'Daily episode summary',
        importance: Importance.defaultImportance,
      ),
      iOS: DarwinNotificationDetails(),
    );

    await _notif.zonedSchedule(
      _dailyId,
      'Daily summary',
      'Open Symptom Tracker to review today\'s episodes.',
      when,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: timelinePayload,
    );
  }

  Future<void> notifyDisconnected() async {
    await _ensureTz();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'device_status',
        'Device status',
        channelDescription: 'Device connection and battery',
        importance: Importance.defaultImportance,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _notif.show(
      _disconnectId,
      'Device disconnected',
      'Symptom Tracker is no longer connected.',
      details,
    );
  }

  /// [percent] 来自设备电量服务。没有读数时不要调用。
  Future<void> notifyLowBattery(int percent) async {
    await _ensureTz();
    if (percent > 20) {
      _lowBatteryLatched = false;
      return;
    }
    if (percent > 15 || _lowBatteryLatched) return;
    _lowBatteryLatched = true;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'device_status',
        'Device status',
        channelDescription: 'Device connection and battery',
        importance: Importance.defaultImportance,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _notif.show(
      _lowBatteryId,
      'Device battery low',
      'About $percent% remaining.',
      details,
    );
  }
}
