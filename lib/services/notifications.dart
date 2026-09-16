// ===== 极简记账 · 每日提醒（21:00 提醒；当天未记账则 23:00 再提醒一次）=====

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'database.dart';

class ReminderService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static const int _idDaily = 1; // 21:00 每日
  static const int _idTonight = 2; // 23:00 当日条件提醒

  Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    } catch (_) {
      // 时区设置失败则用默认，不阻塞启动
    }
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const init = InitializationSettings(android: android);
      await _plugin.initialize(init);
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {
      // 通知初始化失败不影响使用
    }
  }

  /// App 打开 / 记一笔后调用，重新评估 23:00 是否还需要提醒
  Future<void> refresh() async {
    try {
      await _scheduleDaily21();
      await _scheduleTonight23();
    } catch (_) {
      // 忽略单次调度失败
    }
  }

  Future<void> _scheduleDaily21() async {
    await _plugin.zonedSchedule(
      _idDaily,
      '记账提醒',
      '今天记账了吗？说一句就记好啦',
      _next(21, 0),
      _details(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> _scheduleTonight23() async {
    final hasToday = await _hasTxnToday();
    if (hasToday) {
      await _plugin.cancel(_idTonight);
      return;
    }
    final now = tz.TZDateTime.now(tz.local);
    final target = tz.TZDateTime(tz.local, now.year, now.month, now.day, 23, 0);
    if (target.isBefore(now)) return; // 已过 23 点，不再补
    await _plugin.zonedSchedule(
      _idTonight,
      '记账提醒',
      '今天还没记账，睡前记一下吧',
      target,
      _details(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<bool> _hasTxnToday() async {
    final now = DateTime.now();
    final list = await appDb.txns();
    return list.any((t) =>
        t.date.year == now.year && t.date.month == now.month && t.date.day == now.day);
  }

  tz.TZDateTime _next(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!t.isAfter(now)) t = t.add(const Duration(days: 1));
    return t;
  }

  NotificationDetails _details() => const NotificationDetails(
        android: AndroidNotificationDetails(
          'jizhang_reminder',
          '记账提醒',
          channelDescription: '每日记账提醒',
          importance: Importance.high,
          priority: Priority.high,
        ),
      );
}

final ReminderService reminder = ReminderService();
