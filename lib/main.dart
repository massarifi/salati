import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_qiblah/flutter_qiblah.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  await _initNotifications();
  await _requestPermissions();
  runApp(const SalatiApp());
}

Future<void> _initNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}

Future<void> _requestPermissions() async {
  await Permission.location.request();
  await Permission.notification.request();
}

class SalatiApp extends StatelessWidget {
  const SalatiApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'أذكاري و صلاتي',
      theme: ThemeData(primarySwatch: Colors.green, fontFamily: 'Cairo'),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  Map<String, dynamic>? prayerTimes;
  String location = "جارٍ التحديد...";
  double qiblah = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await _getLocationAndPrayers();
    await _getQiblah();
  }  Future<void> _getLocationAndPrayers() async {
    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    setState(() { location = "${position.latitude.toStringAsFixed(2)}, ${position.longitude.toStringAsFixed(2)}"; });
    
    final today = DateFormat('dd-MM-yyyy').format(DateTime.now());
    final url = 'https://api.aladhan.com/v1/timesByCoordinates/$today?latitude=${position.latitude}&longitude=${position.longitude}&method=2';
    final response = await http.get(Uri.parse(url));
    
    if (response.statusCode == 200) {
      setState(() { prayerTimes = json.decode(response.body)['data']['timings']; });
      _schedulePrayerNotifications();
    }
  }

  Future<void> _getQiblah() async {
    final qiblahStream = FlutterQiblah.qiblahStream;
    qiblahStream.listen((data) { setState(() { qiblah = data.qiblah; });
  }

  Future<void> _schedulePrayerNotifications() async {
    if(prayerTimes == null) return;
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails('prayer_channel', 'Prayer Times', importance: Importance.max);
    const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);
    
    prayerTimes!.forEach((name, time) {
      final parts = time.split(':');
      final scheduledTime = Time(int.parse(parts[0]), int.parse(parts[1]));
      flutterLocalNotificationsPlugin.zonedSchedule(
        name.hashCode, 'حان وقت $name', 'الله أكبر',
        _nextInstanceOfTime(scheduledTime), platformDetails,
        androidAllowWhileIdle: true, matchDateTimeComponents: DateTimeComponents.time);
    });
  }

  tz.TZDateTime _nextInstanceOfTime(Time time) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (scheduledDate.isBefore(now)) scheduledDate = scheduledDate.add(const Duration(days: 1));
    return scheduledDate;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('أذكاري و صلاتي'), centerTitle: true),
      body: IndexedStack(
        index: _selectedIndex,
        children: [_prayerTab(), _qiblahTab(), _dhikrTab()],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.access_time), label: 'المواقيت'),
          BottomNavigationBarItem(icon: Icon(Icons.compass_calibration), label: 'القبلة'),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'الأذكار'),
        ],
      ),
    );
  }

  Widget _prayerTab() => ListView(
    children: [
      ListTile(title: Text('الموقع: $location')),
      if(prayerTimes != null)
        ...prayerTimes!.entries.map((e) => ListTile(title: Text(e.key), trailing: Text(e.value))).toList(),
      if(prayerTimes == null) const Center(child: CircularProgressIndicator()),
    ],
  );

  Widget _qiblahTab() => Center(
    child: Transform.rotate(angle: (qiblah * (pi / 180) * -1), child: const Icon(Icons.navigation, size: 150, color: Colors.green)),
  );

  Widget _dhikrTab() {
    List<String> adhkar = ["سبحان الله", "الحمد لله", "الله أكبر", "لا إله إلا الله", "أستغفر الله"];
    int count = 0;
    return StatefulBuilder(builder: (context, setState) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(adhkar[count % adhkar.length], style: const TextStyle(fontSize: 30)),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: () => setState(() => count++), child: Text('تسبيح: $count'))
      ]));
    });
  }
}