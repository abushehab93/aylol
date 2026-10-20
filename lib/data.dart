import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class Reminder {
  int id;
  String type; // 'water' أو 'toilet'
  int minutes; // الدقائق منذ منتصف الليل
  bool enabled;

  Reminder({
    required this.id,
    required this.type,
    required this.minutes,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 'type': type, 'minutes': minutes, 'enabled': enabled};

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
        id: j['id'],
        type: j['type'],
        minutes: j['minutes'],
        enabled: j['enabled'],
      );
}

class AppData {
  int startMin;
  int endMin;
  bool waterOn;
  bool toiletOn;
  List<Reminder> reminders;

  AppData({
    this.startMin = 8 * 60,
    this.endMin = 21 * 60,
    this.waterOn = true,
    this.toiletOn = true,
    required this.reminders,
  });

  factory AppData.defaults() {
    final water = [510, 630, 750, 870, 990, 1110, 1230]; // كل ساعتين تقريباً
    final toilet = [570, 720, 900, 1080, 1200];
    int id = 1;
    final list = <Reminder>[
      for (final m in water) Reminder(id: id++, type: 'water', minutes: m),
      for (final m in toilet) Reminder(id: id++, type: 'toilet', minutes: m),
    ];
    return AppData(reminders: list);
  }

  static const _key = 'app_data_v1';

  static Future<AppData> load() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_key);
    if (s == null) return AppData.defaults();
    try {
      final j = jsonDecode(s) as Map<String, dynamic>;
      return AppData(
        startMin: j['startMin'],
        endMin: j['endMin'],
        waterOn: j['waterOn'],
        toiletOn: j['toiletOn'],
        reminders: (j['reminders'] as List)
            .map((e) => Reminder.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    } catch (_) {
      return AppData.defaults();
    }
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _key,
      jsonEncode({
        'startMin': startMin,
        'endMin': endMin,
        'waterOn': waterOn,
        'toiletOn': toiletOn,
        'reminders': reminders.map((r) => r.toJson()).toList(),
      }),
    );
  }

  int nextId() =>
      reminders.isEmpty ? 1 : reminders.map((r) => r.id).reduce(max) + 1;
}
