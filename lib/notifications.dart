import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'data.dart';

final FlutterLocalNotificationsPlugin plugin =
    FlutterLocalNotificationsPlugin();

// v2: قناة جديدة بإعدادات صوت التنبيه (alarm)
const _channelId = 'routine_channel_v2';

const _texts = {
  'water': ['وقت شرب الماء 💧', 'يلا نشرب كوب ماء يا بطل!'],
  'toilet': ['وقت الحمام 🚽', 'يلا نروح الحمام يا بطل!'],
};

const _androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

Future<void> _ensureTz() async {
  tzdata.initializeTimeZones();
  final name = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(name));
}

NotificationDetails _details() => NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'تذكيرات الروتين',
        channelDescription: 'تذكيرات شرب الماء ودخول الحمام',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        // صوت على قناة المنبّه: يعمل حتى لو الرنين على الصامت
        audioAttributesUsage: AudioAttributesUsage.alarm,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        // FLAG_INSISTENT = 4 : يكرر الصوت حتى الضغط على "تم" أو "تأجيل"
        additionalFlags: Int32List.fromList(<int>[4]),
        // يختفي الإشعار ويتوقف الصوت بعد دقيقة إن لم يتم الرد
        timeoutAfter: 60000,
        actions: const [
          AndroidNotificationAction('done', 'تم', cancelNotification: true),
          AndroidNotificationAction('snooze', 'تأجيل 10 دقائق',
              cancelNotification: true),
        ],
      ),
    );

/// تعمل حتى لو كان التطبيق مغلقاً تماماً (ضغط الأزرار داخل الإشعار)
@pragma('vm:entry-point')
void notificationBackground(NotificationResponse r) async {
  await _handle(r);
}

Future<void> _handle(NotificationResponse r) async {
  if (r.actionId != 'snooze') return; // "تم" يغلق الإشعار تلقائياً
  await _ensureTz();
  await plugin.initialize(const InitializationSettings(android: _androidInit));
  final parts = (r.payload ?? '||').split('||');
  final title = parts.isNotEmpty ? parts[0] : 'تذكير';
  final body = parts.length > 1 ? parts[1] : '';
  final snoozeId = (r.id ?? 0) % 100000 + 100000;
  final when = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 10));
  await _schedule(snoozeId, title, body, when, null);
}

Future<void> initNotifications() async {
  await _ensureTz();
  await plugin.initialize(
    const InitializationSettings(android: _androidInit),
    onDidReceiveNotificationResponse: _handle,
    onDidReceiveBackgroundNotificationResponse: notificationBackground,
  );
}

Future<void> requestNotificationPermissions() async {
  final android = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.requestNotificationsPermission();
  await android?.requestExactAlarmsPermission();
}

Future<void> _schedule(int id, String title, String body, tz.TZDateTime when,
    DateTimeComponents? repeat) async {
  Future<void> go(AndroidScheduleMode mode) => plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        _details(),
        androidScheduleMode: mode,
        matchDateTimeComponents: repeat,
        payload: '$title||$body',
      );
  try {
    await go(AndroidScheduleMode.exactAllowWhileIdle);
  } catch (_) {
    await go(AndroidScheduleMode.inexactAllowWhileIdle);
  }
}

tz.TZDateTime _nextOccurrence(int minutes) {
  final now = tz.TZDateTime.now(tz.local);
  var t = tz.TZDateTime(
      tz.local, now.year, now.month, now.day, minutes ~/ 60, minutes % 60);
  if (t.isBefore(now)) t = t.add(const Duration(days: 1));
  return t;
}

/// يعيد جدولة كل التذكيرات حسب الإعدادات الحالية
Future<void> rescheduleAll(AppData d) async {
  await plugin.cancelAll();
  for (final r in d.reminders) {
    final typeOn = r.type == 'water' ? d.waterOn : d.toiletOn;
    final inRange = r.minutes >= d.startMin && r.minutes <= d.endMin;
    if (!r.enabled || !typeOn || !inRange) continue;
    final t = _texts[r.type]!;
    await _schedule(
        r.id, t[0], t[1], _nextOccurrence(r.minutes), DateTimeComponents.time);
  }
}

Future<void> showTestNotification() async {
  const t = ['تجربة 🔔', 'هكذا سيظهر التذكير'];
  await plugin.show(999999, t[0], t[1], _details(), payload: '${t[0]}||${t[1]}');
}
