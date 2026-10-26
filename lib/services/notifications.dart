// ===== 极简记账 · 每日记账提醒（本地通知，无需联网）=====
// 逻辑：每天在设定时间（默认 21:00）提醒；若当天 23:00 前还没记过账，再提醒一次。
// 提醒不依赖网络，App 完全离线也能用；收不到提醒通常是「通知权限未开」或「系统电池优化」拦截。

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'database.dart';

class ReminderService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static const int _idDaily = 1; // 每日固定时间
  static const int _idTonight = 2; // 当日条件提醒（未记账）
  static const int _idTest = 3; // 测试

  bool permissionGranted = false;

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
      await requestPermission();
    } catch (_) {
      // 通知初始化失败不影响使用
    }
  }

  /// 请求通知权限；返回是否授权（Android 13+ 必须用户同意才会弹提醒）
  Future<bool> requestPermission() async {
    try {
      final r = await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      permissionGranted = r ?? permissionGranted;
    } catch (_) {}
    return permissionGranted;
  }

  Future<bool> _isEnabled() async {
    final v = await appDb.getSetting('reminder_enabled');
    return v != '0'; // 默认开启
  }

  Future<int> _hour() async {
    final v = await appDb.getSetting('reminder_hour');
    return int.tryParse(v ?? '') ?? 21;
  }

  Future<void> setEnabled(bool on) async {
    await appDb.setSetting('reminder_enabled', on ? '1' : '0');
    await refresh();
  }

  Future<void> setHour(int h) async {
    await appDb.setSetting('reminder_hour', '$h');
    await refresh();
  }

  /// App 打开 / 记一笔后调用：重新评估提醒是否需要排程
  Future<void> refresh() async {
    try {
      if (!await _isEnabled()) {
        await _plugin.cancel(_idDaily);
        await _plugin.cancel(_idTonight);
        return;
      }
      await _scheduleDaily();
      await _scheduleTonight();
    } catch (_) {
      // 忽略单次调度失败
    }
  }

  Future<void> _scheduleDaily() async {
    final hour = await _hour();
    await _zone(_idDaily, '记账提醒', '今天记账了吗？说一句就记好啦', _next(hour, 0), repeat: true);
  }

  Future<void> _scheduleTonight() async {
    if (await _hasTxnToday()) {
      await _plugin.cancel(_idTonight);
      return;
    }
    final now = tz.TZDateTime.now(tz.local);
    final target = tz.TZDateTime(tz.local, now.year, now.month, now.day, 23, 0);
    if (target.isBefore(now)) return; // 已过 23 点，不再补
    await _zone(_idTonight, '记账提醒', '今天还没记账，睡前记一下吧', target, repeat: false);
  }

  /// 立即发一条测试通知，方便用户确认通知是否开启
  Future<void> testNow() async {
    try {
      await _plugin.show(_idTest, '记账提醒（测试）', '如果你看到这条，说明通知已开启 ✅', _details());
    } catch (_) {}
  }

  /// 优先用精确闹钟（到点必响），失败则退回宽松闹钟
  Future<void> _zone(int id, String title, String body, tz.TZDateTime when, {bool repeat = false}) async {
    final d = _details();
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        d,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: repeat ? DateTimeComponents.time : null,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        d,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: repeat ? DateTimeComponents.time : null,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  Future<bool> _hasTxnToday() async {
    final now = DateTime.now();
    final list = await appDb.txns();
    return list.any((t) => t.date.year == now.year && t.date.month == now.month && t.date.day == now.day);
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
