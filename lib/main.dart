import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:permission_handler/permission_handler.dart';
import 'data.dart';
import 'notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initNotifications();
  } catch (e) {
    debugPrint('init error: $e');
  }
  runApp(const RoutineApp());
}

class RoutineApp extends StatelessWidget {
  const RoutineApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'روتيني الجميل',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF29B6F6),
          scaffoldBackgroundColor: const Color(0xFFFFF8E1),
        ),
        home: const HomePage(),
      );
}

String fmt(int m) {
  final h = m ~/ 60, mm = m % 60;
  var h12 = h % 12;
  if (h12 == 0) h12 = 12;
  return '$h12:${mm.toString().padLeft(2, '0')} ${h < 12 ? 'ص' : 'م'}';
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  AppData? d;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // بعد منح صلاحية من الإعدادات يرجع المستخدم هنا، فنعيد الجدولة
    if (state == AppLifecycleState.resumed && d != null) rescheduleAll(d!);
  }

  Future<void> _init() async {
    try {
      d = await AppData.load()
          .timeout(const Duration(seconds: 5), onTimeout: AppData.defaults);
    } catch (e) {
      d = AppData.defaults();
    }
    if (mounted) setState(() {});
    try {
      await requestNotificationPermissions();
      await Permission.ignoreBatteryOptimizations.request();
      await rescheduleAll(d!);
    } catch (e) {
      debugPrint('schedule error: $e');
    }
  }

  Future<void> _commit() async {
    setState(() {});
    await d!.save();
    await rescheduleAll(d!);
  }

  Future<int?> _pick(int initial) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  @override
  Widget build(BuildContext context) {
    final data = d;
    return Scaffold(
      appBar: AppBar(
        title: const Text('روتيني الجميل 🌈',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: const Color(0xFF81D4FA),
      ),
      body: data == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _dayCard(data),
                const SizedBox(height: 16),
                _section(data, 'water', '💧', 'شرب الماء',
                    const Color(0xFFE1F5FE)),
                const SizedBox(height: 16),
                _section(data, 'toilet', '🚽', 'دخول الحمام',
                    const Color(0xFFF3E5F5)),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: showTestNotification,
                  icon: const Icon(Icons.notifications_active),
                  label: const Text('جرّب التنبيه الآن',
                      style: TextStyle(fontSize: 18)),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56)),
                ),
              ],
            ),
    );
  }

  Widget _dayCard(AppData data) => Card(
        color: const Color(0xFFFFF59D),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            const Text('☀️ يومي 🌙',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: _timeButton('بداية اليوم', data.startMin, () async {
                final m = await _pick(data.startMin);
                if (m != null) {
                  data.startMin = m;
                  _commit();
                }
              })),
              const SizedBox(width: 12),
              Expanded(
                  child: _timeButton('نهاية اليوم', data.endMin, () async {
                final m = await _pick(data.endMin);
                if (m != null) {
                  data.endMin = m;
                  _commit();
                }
              })),
            ]),
          ]),
        ),
      );

  Widget _timeButton(String label, int m, VoidCallback onTap) =>
      FilledButton.tonal(
        onPressed: onTap,
        style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(64),
            backgroundColor: Colors.white),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(fmt(m),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ]),
      );

  Widget _section(
      AppData data, String type, String emoji, String title, Color bg) {
    final on = type == 'water' ? data.waterOn : data.toiletOn;
    final items = data.reminders.where((r) => r.type == type).toList()
      ..sort((a, b) => a.minutes.compareTo(b.minutes));
    return Card(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 8),
            Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold))),
            Switch(
              value: on,
              onChanged: (v) {
                type == 'water' ? data.waterOn = v : data.toiletOn = v;
                _commit();
              },
            ),
          ]),
          for (final r in items)
            Card(
              child: ListTile(
                onTap: () async {
                  final m = await _pick(r.minutes);
                  if (m != null) {
                    r.minutes = m;
                    _commit();
                  }
                },
                title: Text(fmt(r.minutes),
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold)),
                subtitle: r.minutes < data.startMin || r.minutes > data.endMin
                    ? const Text('خارج وقت اليوم', style: TextStyle(color: Colors.red))
                    : null,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Switch(
                      value: r.enabled,
                      onChanged: (v) {
                        r.enabled = v;
                        _commit();
                      }),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () {
                      data.reminders.remove(r);
                      _commit();
                    },
                  ),
                ]),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () async {
              final m = await _pick(12 * 60);
              if (m != null) {
                data.reminders
                    .add(Reminder(id: data.nextId(), type: type, minutes: m));
                _commit();
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('إضافة موعد', style: TextStyle(fontSize: 18)),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ]),
      ),
    );
  }
}
