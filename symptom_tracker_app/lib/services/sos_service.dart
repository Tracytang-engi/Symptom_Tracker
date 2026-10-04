import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

/// SosService：SOS 紧急求助
///
/// 本机高优先级通知 + GPS。若保存了监护人号码，再打开短信并带上坐标。
class SosService {
  final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestSoundPermission: true,
    );
    await _notif.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    // Android 13+ 需要运行时通知权限
    await Permission.notification.request();
    _initialized = true;
  }

  /// 触发 SOS：获取位置（若未传入）并发送本地紧急通知。
  /// 返回实际使用的位置字符串（可能为 null）。
  Future<String?> trigger({String? location, String? guardianPhone}) async {
    await init();
    final loc = location ?? await getCurrentLocation();
    await _sendSosNotification(loc);
    final phone = guardianPhone?.trim() ?? '';
    if (phone.isNotEmpty) {
      await _openGuardianSms(phone, loc);
    }
    return loc;
  }

  Future<void> _openGuardianSms(String phone, String? location) async {
    final body = location != null
        ? 'SOS from Symptom Tracker. Location: $location'
        : 'SOS from Symptom Tracker. Location unavailable.';
    final uri = Uri.parse('sms:$phone?body=${Uri.encodeComponent(body)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  /// 获取当前 GPS 坐标，返回 "纬度,经度"；无权限或失败时返回 null
  Future<String?> getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return '${position.latitude.toStringAsFixed(5)},'
          '${position.longitude.toStringAsFixed(5)}';
    } catch (_) {
      return null;
    }
  }

  Future<void> _sendSosNotification(String? location) async {
    const androidDetails = AndroidNotificationDetails(
      'sos_alerts',
      'SOS Alerts',
      channelDescription: 'Emergency SOS alerts from the Symptom Tracker device',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.alarm,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );

    final body = location != null
        ? 'Emergency SOS triggered. Location: $location'
        : 'Emergency SOS triggered. Location unavailable.';

    await _notif.show(
      9001, // 固定 ID：连续 SOS 会覆盖上一条，避免堆叠
      'SOS Emergency',
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }
}
