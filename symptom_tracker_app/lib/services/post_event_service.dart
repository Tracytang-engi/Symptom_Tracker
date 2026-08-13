import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';  // 本地通知库
import '../models/pain_event.dart';
import '../models/user_settings.dart';

// PostEventService：事件结束后根据用户设置决定做什么
// 对应 UserSettings.postEventAction 的四种选项
class PostEventService {
  // FlutterLocalNotificationsPlugin = 发送本地通知的插件实例
  final FlutterLocalNotificationsPlugin _notif = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;            // 防止重复初始化

    // Android/iOS 各自的初始化配置
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');  // 通知图标
    const iosSettings = DarwinInitializationSettings();
    await _notif.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );
    _initialized = true;
  }

  // ─── 主入口 ──────────────────────────────────────────────────────────────────

  // required = 必传命名参数；BuildContext? = 可为 null（App 在后台时没有 context）
  Future<void> onEventEnd({
    required PainEvent event,
    required UserSettings settings,
    required BuildContext? context,
    required List<PainEvent> recentEvents,
    VoidCallback? onTagsRequested,       // VoidCallback = 无参无返回值的函数类型；? = 可不传
  }) async {
    switch (settings.postEventAction) {  // 根据设置分支处理
      case PostEventAction.nothing:
        break;                           // break = 不做任何事，直接退出 switch

      case PostEventAction.silentNotification:
        await _sendNotification(event);  // 直接发通知
        break;

      case PostEventAction.promptTags:
        // 有回调则弹标签；否则退化为静默通知
        if (onTagsRequested != null) {
          onTagsRequested();
        } else {
          await _sendNotification(event);
        }
        break;

      case PostEventAction.promptIfAbnormal:
        if (_isAbnormal(event, recentEvents)) {
          if (onTagsRequested != null) {
            onTagsRequested();
          } else {
            await _sendNotification(event);
          }
        }
        break;
    }
  }

  // ─── 发送本地通知 ────────────────────────────────────────────────────────────

  Future<void> _sendNotification(PainEvent event) async {
    // Android 通知渠道配置（Android 8.0+ 必须有渠道）
    const androidDetails = AndroidNotificationDetails(
      'pain_events',           // 渠道 ID（唯一）
      'Pain Events',           // 渠道名（用户可在系统设置看到）
      channelDescription: 'Notifications for recorded pain events',
      importance: Importance.low,   // 低优先级 = 无声音
      priority: Priority.low,
      silent: true,
    );
    const iosDetails = DarwinNotificationDetails(presentSound: false);  // iOS 不发声音

    await _notif.show(
      event.hashCode,          // .hashCode = 对象的哈希值，用作通知 ID（唯一区分各条通知）
      'Episode Recorded',
      'Duration ${event.formattedDuration} · Peak ${event.peakForcePercent}',  // 通知正文
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  // ─── 异常判断 ────────────────────────────────────────────────────────────────

  bool _isAbnormal(PainEvent event, List<PainEvent> recent) {
    if (recent.isEmpty) return false;

    // 计算最近事件的平均时长
    final avgDuration =
        recent.map((e) => e.durationMs).reduce((a, b) => a + b) / recent.length;

    // 判断条件：时长超过均值 1.5 倍，或峰值超过 90%
    return event.durationMs > avgDuration * 1.5 || event.peakForce > 0.9;
  }
}
