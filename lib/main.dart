import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// -----------------------------------------------------------------------------
// 1. GLOBAL SETTINGS MANAGER (Theme & Haptics)
// -----------------------------------------------------------------------------

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);
final ValueNotifier<bool> hapticsNotifier = ValueNotifier(true);

Future<void> _loadSettings() async {
  final prefs = await SharedPreferences.getInstance();

  // Theme
  final String? themeStr = prefs.getString('theme_mode');
  if (themeStr == 'light')
    themeNotifier.value = ThemeMode.light;
  else if (themeStr == 'dark')
    themeNotifier.value = ThemeMode.dark;
  else
    themeNotifier.value = ThemeMode.system;

  // Haptics
  hapticsNotifier.value = prefs.getBool('haptics_enabled') ?? true;
}

Future<void> _saveTheme(ThemeMode mode) async {
  themeNotifier.value = mode;
  final prefs = await SharedPreferences.getInstance();
  String val = 'system';
  if (mode == ThemeMode.light) val = 'light';
  if (mode == ThemeMode.dark) val = 'dark';
  await prefs.setString('theme_mode', val);
}

Future<void> _saveHaptics(bool enabled) async {
  hapticsNotifier.value = enabled;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('haptics_enabled', enabled);
}

void performHaptic(HapticFeedbackType type) {
  if (hapticsNotifier.value) {
    if (type == HapticFeedbackType.light)
      HapticFeedback.lightImpact();
    else if (type == HapticFeedbackType.medium)
      HapticFeedback.mediumImpact();
    else if (type == HapticFeedbackType.heavy) HapticFeedback.heavyImpact();
  }
}

enum HapticFeedbackType { light, medium, heavy }

// -----------------------------------------------------------------------------
// 2. SERVICES (UPDATED FOR ANDROID PERMISSIONS)
// -----------------------------------------------------------------------------

class NotificationService {
  static final _notifications = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    tz.initializeTimeZones();

    // Android Settings
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS Settings
    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    final settings =
        InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _notifications.initialize(settings);

    // ΤΟ "ΜΑΓΙΚΟ" ΓΙΑ ANDROID 13+: Ζητάει την άδεια αμέσως
    _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> scheduleNotification(
      {required int id,
      required String title,
      required DateTime scheduledTime}) async {
    await _notifications.zonedSchedule(
      id,
      'Apatheia',
      title,
      tz.TZDateTime.from(scheduledTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
            'main_channel', 'Main Notifications',
            importance: Importance.max, priority: Priority.high),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: id.toString(),
    );
  }

  static Future<void> scheduleDaily(
      {required int id,
      required String title,
      required String body,
      required int hour,
      required int minute}) async {
    await _notifications.zonedSchedule(
      id,
      title,
      body,
      _nextInstanceOfTime(hour, minute),
      const NotificationDetails(
        android: AndroidNotificationDetails('daily_channel', 'Daily Reminders',
            importance: Importance.max, priority: Priority.high),
        iOS: DarwinNotificationDetails(presentSound: true),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduledDate.isBefore(now))
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    return scheduledDate;
  }

  static Future<void> cancel(int id) async => await _notifications.cancel(id);
}

// -----------------------------------------------------------------------------
// 3. DATA & UTILS
// -----------------------------------------------------------------------------

const List<String> kQuotes = [
  "We suffer more often in imagination than in reality. -Seneca",
  "Waste no more time arguing about what a good man should be. Be one. -Marcus Aurelius",
  "The happiness of your life depends upon the quality of your thoughts. -Marcus Aurelius",
  "It is not death that a man should fear, but never beginning to live. -Marcus Aurelius",
  "First say to yourself what you would be; and then do what you have to do. -Epictetus",
  "Man is not worried by real problems so much as by his imagined anxieties about real problems. -Epictetus",
];

const List<Color> kTaskColors = [
  Colors.white,
  Color(0xFFE3F2FD),
  Color(0xFFF3E5F5),
  Color(0xFFE8F5E9),
  Color(0xFFFFF3E0),
  Color(0xFFFFEBEE),
];

bool isSameDay(DateTime d1, DateTime d2) {
  return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
}

Color getCardColor(BuildContext context, int colorVal) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (colorVal == Colors.white.value)
    return isDark ? const Color(0xFF1C1C1E) : Colors.white;
  if (isDark)
    return Color.alphaBlend(
        Colors.black.withValues(alpha: 0.3), Color(colorVal));
  return Color(colorVal);
}

Color getTextColor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? Colors.white
      : Colors.black;
}

// -----------------------------------------------------------------------------
// 4. MAIN APP
// -----------------------------------------------------------------------------

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init(); // Ζητάει άδειες εδώ
  await _loadSettings();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  NotificationService.scheduleDaily(
      id: 888,
      title: "Daily Stoic",
      body: "Start your day with clarity.",
      hour: 9,
      minute: 0);
  NotificationService.scheduleDaily(
      id: 889,
      title: "Keep the Streak!",
      body: "Don't break the chain.",
      hour: 18,
      minute: 0);
  NotificationService.scheduleDaily(
      id: 890,
      title: "Evening Reflection",
      body: "Time to review your day.",
      hour: 20,
      minute: 0);

  runApp(const MinimalApp());
}

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad
      };
  @override
  Widget buildOverscrollIndicator(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
  @override
  Widget buildScrollbar(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
}

class MinimalApp extends StatelessWidget {
  const MinimalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          scrollBehavior: MyCustomScrollBehavior(),
          debugShowCheckedModeBanner: false,
          title: 'Apatheia',
          themeMode: currentMode,
          theme: ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF2F2F7),
            primaryColor: Colors.black,
            textSelectionTheme:
                const TextSelectionThemeData(cursorColor: Colors.black),
            textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF000000),
            primaryColor: Colors.white,
            textSelectionTheme:
                const TextSelectionThemeData(cursorColor: Colors.white),
            textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
            useMaterial3: true,
          ),
          home: const MainScreen(),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// 5. MAIN SCREEN & NAVIGATION
// -----------------------------------------------------------------------------

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final List<Widget> _pages = [
    const FocusPage(),
    const HabitsPage(),
    const JournalPage(),
    const PomodoroPage(),
    const MementoMoriPage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkFirstRun());
  }

  Future<void> _checkFirstRun() async {
    final prefs = await SharedPreferences.getInstance();
    bool isFirstRun = prefs.getBool('is_first_run') ?? true;
    if (isFirstRun) {
      _showTutorialSheet(context);
      await prefs.setBool('is_first_run', false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
              child: IndexedStack(index: _selectedIndex, children: _pages)),
          Positioned(
            left: 20,
            right: 20,
            bottom: 30,
            child: SafeArea(
              child: Container(
                height: 70,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1C1C1E).withValues(alpha: 0.85)
                      : Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(35),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 10))
                  ],
                  border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.white.withValues(alpha: 0.5)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(35),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildNavItem(0, CupertinoIcons.check_mark_circled),
                        _buildNavItem(1, CupertinoIcons.repeat),
                        _buildNavItem(2, CupertinoIcons.book),
                        _buildNavItem(3, CupertinoIcons.timer),
                        _buildNavItem(4, CupertinoIcons.compass),
                      ],
                    ),
                  ),
                ),
              ).animate().fadeIn(duration: 500.ms).moveY(begin: 50, end: 0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon) {
    final bool isSelected = _selectedIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedIndex = index);
        performHaptic(HapticFeedbackType.light);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
        width: 50,
        height: 50,
        decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? Colors.white : Colors.black)
                : Colors.transparent,
            shape: BoxShape.circle),
        child: Icon(icon,
            color: isSelected
                ? (isDark ? Colors.black : Colors.white)
                : (isDark ? Colors.grey[600] : Colors.grey[400]),
            size: 24),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 6. SHARED SHEETS
// -----------------------------------------------------------------------------

void _showTutorialSheet(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1C1C1E).withValues(alpha: 0.95)
                  : Colors.white.withValues(alpha: 0.95)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.sparkles,
                  size: 50, color: isDark ? Colors.white : Colors.black),
              const SizedBox(height: 20),
              Text("WELCOME TO APATHEIA",
                  style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2)),
              const SizedBox(height: 40),
              _buildTip(context, CupertinoIcons.settings, "TOP LEFT",
                  "Access Settings & Customization."),
              _buildTip(context, Icons.local_fire_department, "TOP RIGHT",
                  "View your Stoic Rank & Stats."),
              _buildTip(context, Icons.touch_app, "LONG PRESS",
                  "Reorder your tasks & habits."),
              _buildTip(context, CupertinoIcons.repeat, "HABITS",
                  "Set Interval or Specific Days."),
              _buildTip(context, CupertinoIcons.book, "JOURNAL",
                  "Reflect once a day."),
              _buildTip(context, CupertinoIcons.timer, "POMODORO",
                  "Tap 'Adjust' to change timer."),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? Colors.white : Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16))),
                  onPressed: () => Navigator.pop(context),
                  child: Text("BEGIN",
                      style: TextStyle(
                          color: isDark ? Colors.black : Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _buildTip(
    BuildContext context, IconData icon, String title, String desc) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Padding(
    padding: const EdgeInsets.only(bottom: 20.0),
    child: Row(
      children: [
        Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[100],
                shape: BoxShape.circle),
            child: Icon(icon,
                size: 20, color: isDark ? Colors.white : Colors.black)),
        const SizedBox(width: 16),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w900)),
          Text(desc,
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[500]))
        ])),
      ],
    ),
  );
}

void _showSettingsSheet(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final bg = isDark
      ? const Color(0xFF1C1C1E).withValues(alpha: 0.95)
      : Colors.white.withValues(alpha: 0.95);
  final textC = getTextColor(context);

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(color: bg),
          child: StatefulBuilder(builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 30),
                Text("SETTINGS",
                    style: GoogleFonts.inter(
                        fontSize: 10, letterSpacing: 1.5, color: Colors.grey)),
                const SizedBox(height: 20),
                Text("Appearance",
                    style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textC)),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  child: CupertinoSegmentedControl<ThemeMode>(
                    groupValue: themeNotifier.value,
                    borderColor: isDark ? Colors.grey[700] : Colors.black,
                    selectedColor: isDark ? Colors.white : Colors.black,
                    unselectedColor: Colors.transparent,
                    pressedColor: isDark ? Colors.grey[800] : Colors.grey[200],
                    children: {
                      ThemeMode.system: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 10),
                          child: Text("System",
                              style: TextStyle(
                                  color: themeNotifier.value == ThemeMode.system
                                      ? (isDark ? Colors.black : Colors.white)
                                      : textC,
                                  fontSize: 13))),
                      ThemeMode.light: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 10),
                          child: Text("Light",
                              style: TextStyle(
                                  color: themeNotifier.value == ThemeMode.light
                                      ? (isDark ? Colors.black : Colors.white)
                                      : textC,
                                  fontSize: 13))),
                      ThemeMode.dark: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 10),
                          child: Text("Dark",
                              style: TextStyle(
                                  color: themeNotifier.value == ThemeMode.dark
                                      ? Colors.black
                                      : textC,
                                  fontSize: 13))),
                    },
                    onValueChanged: (mode) {
                      _saveTheme(mode);
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Haptics",
                        style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textC)),
                    CupertinoSwitch(
                      value: hapticsNotifier.value,
                      activeColor: CupertinoColors.activeBlue,
                      trackColor: isDark ? Colors.grey[800] : Colors.grey[300],
                      onChanged: (val) {
                        _saveHaptics(val);
                        setState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showTutorialSheet(context);
                    },
                    icon: Icon(CupertinoIcons.info, size: 18, color: textC),
                    label: Text("Show Guide", style: TextStyle(color: textC)),
                    style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color:
                                isDark ? Colors.grey[700]! : Colors.grey[300]!),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16))),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            );
          }),
        ),
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
// 7. FOCUS PAGE
// -----------------------------------------------------------------------------

class FocusPage extends StatefulWidget {
  const FocusPage({super.key});
  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> {
  List<Map<String, dynamic>> _tasks = [];
  List<String> _activityLog = [];
  String _currentQuote = "";
  int _streakCount = 0;
  int _totalTasksCompleted = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentQuote = kQuotes[Random().nextInt(kQuotes.length)];
      _streakCount = prefs.getInt('global_streak') ?? 0;
      _totalTasksCompleted = prefs.getInt('total_tasks_completed') ?? 0;
      _activityLog = prefs.getStringList('activity_log') ?? [];
    });
    final String? tasksString = prefs.getString('tasks');
    if (tasksString != null)
      setState(() =>
          _tasks = List<Map<String, dynamic>>.from(jsonDecode(tasksString)));
    _checkStreakReset(prefs);
  }

  void _checkStreakReset(SharedPreferences prefs) {
    final lastDateStr = prefs.getString('last_task_date');
    if (lastDateStr != null) {
      final lastDate = DateTime.parse(lastDateStr);
      final now = DateTime.now();
      if (now
              .difference(DateTime(lastDate.year, lastDate.month, lastDate.day))
              .inDays >
          1) {
        setState(() => _streakCount = 0);
        prefs.setInt('global_streak', 0);
      }
    }
  }

  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tasks', jsonEncode(_tasks));
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _tasks.removeAt(oldIndex);
      _tasks.insert(newIndex, item);
    });
    _saveTasks();
  }

  Future<void> _logActivity() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().toIso8601String().split('T')[0];
    if (!_activityLog.contains(now)) {
      _activityLog.add(now);
      await prefs.setStringList('activity_log', _activityLog);
    }
  }

  Future<void> _addTask(
      String title, String tags, int color, String? time) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final int id = now.millisecondsSinceEpoch ~/ 1000;
    final lastDateStr = prefs.getString('last_task_date');
    bool shouldIncrement = false;

    if (lastDateStr == null)
      shouldIncrement = true;
    else {
      final lastDate = DateTime.parse(lastDateStr);
      if (!isSameDay(lastDate, now)) {
        final diff = now
            .difference(DateTime(lastDate.year, lastDate.month, lastDate.day))
            .inDays;
        if (diff == 1)
          shouldIncrement = true;
        else {
          _streakCount = 0;
          shouldIncrement = true;
        }
      }
    }

    if (shouldIncrement) {
      setState(() => _streakCount++);
      await prefs.setInt('global_streak', _streakCount);
      await prefs.setString('last_task_date', now.toIso8601String());
    }
    _logActivity();

    setState(() {
      _tasks.add({
        'id': id,
        'title': title,
        'time': time,
        'isDone': false,
        'tags': tags,
        'color': color
      });
    });
    _saveTasks();

    if (time != null) {
      final parts = time.split(':');
      final timeOfDay =
          TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      final scheduledDate = DateTime(
          now.year, now.month, now.day, timeOfDay.hour, timeOfDay.minute);
      var finalDate = scheduledDate;
      if (finalDate.isBefore(now))
        finalDate = finalDate.add(const Duration(days: 1));
      NotificationService.scheduleNotification(
          id: id, title: title, scheduledTime: finalDate);
    }
  }

  void _updateTask(
      int index, String title, String tags, int colorValue, String? time) {
    setState(() {
      _tasks[index]['title'] = title;
      _tasks[index]['tags'] = tags;
      _tasks[index]['color'] = colorValue;
      _tasks[index]['time'] = time;
    });
    _saveTasks();
    if (time != null) {
      final parts = time.split(':');
      final timeOfDay =
          TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      final now = DateTime.now();
      var scheduledDate = DateTime(
          now.year, now.month, now.day, timeOfDay.hour, timeOfDay.minute);
      if (scheduledDate.isBefore(now))
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      NotificationService.scheduleNotification(
          id: _tasks[index]['id'], title: title, scheduledTime: scheduledDate);
    } else {
      NotificationService.cancel(_tasks[index]['id']);
    }
  }

  void _toggleTask(int index) async {
    setState(() {
      _tasks[index]['isDone'] = !_tasks[index]['isDone'];
      if (_tasks[index]['isDone']) {
        SystemSound.play(SystemSoundType.click);
        performHaptic(HapticFeedbackType.heavy);
        _totalTasksCompleted++;
        _logActivity();
      } else if (_totalTasksCompleted > 0) _totalTasksCompleted--;
    });
    _saveTasks();
    final prefs = await SharedPreferences.getInstance();
    prefs.setInt('total_tasks_completed', _totalTasksCompleted);
  }

  void _deleteTask(int index) {
    NotificationService.cancel(_tasks[index]['id']);
    setState(() => _tasks.removeAt(index));
    _saveTasks();
  }

  // --- PROFILE ---
  Map<String, dynamic> _getRankData(int streak) {
    if (streak >= 100)
      return {'title': 'STOIC MASTER', 'next': 0, 'total': 100, 'prev': 100};
    if (streak >= 50)
      return {'title': 'SAGE', 'next': 100, 'total': 50, 'prev': 50};
    if (streak >= 20)
      return {'title': 'PHILOSOPHER', 'next': 50, 'total': 30, 'prev': 20};
    if (streak >= 5)
      return {'title': 'PROKOPTON', 'next': 20, 'total': 15, 'prev': 5};
    return {'title': 'NOVICE', 'next': 5, 'total': 5, 'prev': 0};
  }

  void _showProfileSheet(BuildContext context) {
    final rankData = _getRankData(_streakCount);
    final int nextGoal = rankData['next'];
    final int prevGoal = rankData['prev'];
    final int totalSpan = rankData['total'];
    double progress =
        nextGoal == 0 ? 1.0 : (_streakCount - prevGoal) / totalSpan;
    if (progress < 0) progress = 0;
    if (progress > 1) progress = 1;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.95)
        : Colors.white.withValues(alpha: 0.95);
    final textC = getTextColor(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            height: 650,
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(color: bg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 30),
                Icon(CupertinoIcons.checkmark_seal_fill,
                    size: 60, color: textC),
                const SizedBox(height: 20),
                Text(rankData['title'],
                    style: GoogleFonts.inter(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        color: textC)),
                Text("CURRENT RANK",
                    style: GoogleFonts.inter(
                        fontSize: 10, letterSpacing: 2, color: Colors.grey)),
                const SizedBox(height: 30),
                if (nextGoal > 0) ...[
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("$_streakCount Days",
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold, color: textC)),
                        Text("$nextGoal Days",
                            style: GoogleFonts.inter(color: Colors.grey))
                      ]),
                  const SizedBox(height: 10),
                  ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 10,
                          backgroundColor: Colors.grey.withValues(alpha: 0.2),
                          color: isDark ? Colors.white : Colors.black)),
                  const SizedBox(height: 40),
                ],
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStat("$_streakCount", "STREAK", Colors.orange),
                      _buildStat("$_totalTasksCompleted", "COMPLETED", textC)
                    ]),
                const SizedBox(height: 40),
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text("CONSISTENCY (Last 14 Days)",
                        style: GoogleFonts.inter(
                            fontSize: 10,
                            letterSpacing: 1.5,
                            color: Colors.grey))),
                const SizedBox(height: 15),
                SizedBox(
                  height: 30,
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(14, (index) {
                        final date =
                            DateTime.now().subtract(Duration(days: 13 - index));
                        final dateStr = date.toIso8601String().split('T')[0];
                        final isActive = _activityLog.contains(dateStr);
                        return Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isActive
                                    ? (isDark ? Colors.white : Colors.black)
                                    : Colors.grey.withValues(alpha: 0.3)));
                      })),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStat(String value, String label, Color color) {
    return Column(children: [
      Text(value,
          style: GoogleFonts.inter(
              fontSize: 32, fontWeight: FontWeight.bold, color: color)),
      Text(label,
          style: GoogleFonts.inter(
              fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey))
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textC = isDark ? Colors.white : Colors.black;

    return Scaffold(
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 90),
        child: FloatingActionButton(
          onPressed: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => TaskDetailSheet(
              initialTitle: "",
              initialTags: "",
              initialColor: Colors.white.value,
              initialTime: null,
              initialFrequency: 1,
              isHabit: false,
              isNew: true,
              onSave: (title, tags, color, time, freq, {weekdays}) {
                if (title.isNotEmpty) _addTask(title, tags, color, time);
              },
            ),
          ),
          backgroundColor: textC,
          elevation: 4,
          highlightElevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Icon(CupertinoIcons.add,
              color: isDark ? Colors.black : Colors.white, size: 28),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                          onTap: () => _showSettingsSheet(context),
                          child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.1),
                                  shape: BoxShape.circle),
                              child: Icon(CupertinoIcons.settings,
                                  size: 20, color: textC))),
                      Text(
                          DateFormat('EEEE, d MMM')
                              .format(DateTime.now())
                              .toUpperCase(),
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                              color: Colors.grey)),
                      GestureDetector(
                          onTap: () => _showProfileSheet(context),
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: ShapeDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  shape: const StadiumBorder()),
                              child: Row(children: [
                                Icon(Icons.local_fire_department,
                                    size: 16, color: Colors.orange[800]),
                                const SizedBox(width: 4),
                                Text("$_streakCount",
                                    style: GoogleFonts.inter(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange[900]))
                              ]))),
                    ],
                  ),
                  const SizedBox(height: 30),
                  Text(_currentQuote,
                          style: GoogleFonts.lora(
                              fontSize: 28,
                              fontWeight: FontWeight.w400,
                              fontStyle: FontStyle.italic,
                              height: 1.3,
                              color: textC))
                      .animate()
                      .fadeIn(duration: 800.ms)
                      .moveY(begin: 20, end: 0),
                ],
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(40)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1C1C1E).withValues(alpha: 0.7)
                          : Colors.white.withValues(alpha: 0.7),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(40)),
                      border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.white.withValues(alpha: 0.3),
                          width: 1.5),
                    ),
                    child: _tasks.isEmpty
                        ? Center(
                            child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                Icon(CupertinoIcons.check_mark_circled,
                                    size: 48, color: Colors.grey),
                                const SizedBox(height: 16),
                                Text("Empty mind.\nPeaceful life.",
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                        color: Colors.grey, fontSize: 16))
                              ]))
                        : ReorderableListView.builder(
                            padding: const EdgeInsets.only(
                                top: 30, left: 20, right: 20, bottom: 120),
                            itemCount: _tasks.length,
                            onReorder: _onReorder,
                            proxyDecorator: (child, index, animation) =>
                                Material(
                                    color: Colors.transparent, child: child),
                            itemBuilder: (context, index) {
                              final task = _tasks[index];
                              return ReorderableDismissibleTaskCard(
                                key: Key(task['id'].toString()),
                                task: task,
                                onToggle: () => _toggleTask(index),
                                onTap: () => showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (context) => TaskDetailSheet(
                                    initialTitle: _tasks[index]['title'],
                                    initialTags: _tasks[index]['tags'] ?? '',
                                    initialColor: _tasks[index]['color'] ??
                                        Colors.white.value,
                                    initialTime: _tasks[index]['time'],
                                    initialFrequency: 1,
                                    isHabit: false,
                                    onSave: (title, tags, color, time, freq,
                                            {weekdays}) =>
                                        _updateTask(
                                            index, title, tags, color, time),
                                    onDelete: () => _deleteTask(index),
                                  ),
                                ),
                                onDelete: () => _deleteTask(index),
                              );
                            },
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 8. POMODORO PAGE
// -----------------------------------------------------------------------------

enum PomodoroMode { focus, shortBreak, longBreak }

class PomodoroPage extends StatefulWidget {
  const PomodoroPage({super.key});
  @override
  State<PomodoroPage> createState() => _PomodoroPageState();
}

class _PomodoroPageState extends State<PomodoroPage> {
  int _userFocusTime = 25;
  PomodoroMode _mode = PomodoroMode.focus;
  late int _timeLeft;
  Timer? _timer;
  bool _isActive = false;
  int _cycleCount = 0;

  @override
  void initState() {
    super.initState();
    _timeLeft = _userFocusTime * 60;
  }

  void _toggleTimer() {
    if (_isActive) {
      _timer?.cancel();
      setState(() => _isActive = false);
    } else {
      setState(() => _isActive = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_timeLeft > 0)
          setState(() => _timeLeft--);
        else
          _finishCycle();
      });
    }
  }

  void _finishCycle() {
    _timer?.cancel();
    performHaptic(HapticFeedbackType.heavy);
    SystemSound.play(SystemSoundType.alert);
    setState(() {
      _isActive = false;
      if (_mode == PomodoroMode.focus) {
        _cycleCount++;
        if (_cycleCount % 4 == 0) {
          _mode = PomodoroMode.longBreak;
          _timeLeft = 15 * 60;
        } else {
          _mode = PomodoroMode.shortBreak;
          _timeLeft = 5 * 60;
        }
      } else {
        _mode = PomodoroMode.focus;
        _timeLeft = _userFocusTime * 60;
      }
    });
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _isActive = false;
      _mode = PomodoroMode.focus;
      _cycleCount = 0;
      _timeLeft = _userFocusTime * 60;
    });
  }

  void _changeDuration() {
    if (_isActive) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showCupertinoModalPopup(
      context: context,
      builder: (context) => Container(
        height: 250,
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        child: Column(children: [
          SizedBox(
              height: 180,
              child: CupertinoPicker(
                itemExtent: 32,
                scrollController: FixedExtentScrollController(
                    initialItem: _userFocusTime - 1),
                onSelectedItemChanged: (index) {
                  setState(() {
                    _userFocusTime = index + 1;
                    if (_mode == PomodoroMode.focus)
                      _timeLeft = _userFocusTime * 60;
                  });
                },
                children: List.generate(
                    60,
                    (index) => Center(
                        child: Text("${index + 1} min",
                            style: TextStyle(
                                color: isDark ? Colors.white : Colors.black)))),
              )),
          CupertinoButton(
              child: Text("Done",
                  style:
                      TextStyle(color: isDark ? Colors.white : Colors.black)),
              onPressed: () => Navigator.pop(context))
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _timerString {
    final minutes = (_timeLeft ~/ 60).toString().padLeft(2, '0');
    final seconds = (_timeLeft % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  String get _modeString {
    switch (_mode) {
      case PomodoroMode.focus:
        return "FOCUS";
      case PomodoroMode.shortBreak:
        return "SHORT BREAK";
      case PomodoroMode.longBreak:
        return "LONG BREAK";
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textC = isDark ? Colors.white : Colors.black;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_modeString,
                  style: GoogleFonts.inter(
                      fontSize: 14,
                      letterSpacing: 3,
                      color: Colors.grey,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 50),
              Stack(alignment: Alignment.center, children: [
                SizedBox(
                    width: 280,
                    height: 280,
                    child: CircularProgressIndicator(
                        value: 1.0,
                        strokeWidth: 12,
                        backgroundColor: Colors.transparent,
                        color: isDark ? Colors.grey[900] : Colors.grey[200],
                        strokeCap: StrokeCap.round)),
                SizedBox(
                    width: 280,
                    height: 280,
                    child: CircularProgressIndicator(
                        value: 1 -
                            (_timeLeft /
                                (_mode == PomodoroMode.focus
                                    ? (_userFocusTime * 60)
                                    : (_mode == PomodoroMode.longBreak
                                        ? 900
                                        : 300))),
                        strokeWidth: 12,
                        backgroundColor: Colors.transparent,
                        color: textC,
                        strokeCap: StrokeCap.round)),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_timerString,
                      style: GoogleFonts.inter(
                          fontSize: 64,
                          fontWeight: FontWeight.w200,
                          color: textC)),
                  if (_mode == PomodoroMode.focus && !_isActive)
                    Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: GestureDetector(
                            onTap: _changeDuration,
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.grey[800]
                                        : Colors.grey[200],
                                    borderRadius: BorderRadius.circular(20)),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(CupertinoIcons.slider_horizontal_3,
                                          size: 14, color: textC),
                                      const SizedBox(width: 6),
                                      Text("Adjust",
                                          style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: textC))
                                    ])))),
                ]),
              ]),
              const SizedBox(height: 60),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(
                    onPressed: _resetTimer,
                    icon: const Icon(Icons.refresh,
                        size: 36, color: Colors.grey)),
                const SizedBox(width: 40),
                GestureDetector(
                    onTap: _toggleTimer,
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 40, vertical: 20),
                        decoration: BoxDecoration(
                            color: textC,
                            borderRadius: BorderRadius.circular(40),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 10,
                                  offset: const Offset(0, 5))
                            ]),
                        child: Text(_isActive ? "PAUSE" : "START",
                            style: GoogleFonts.inter(
                                color: isDark ? Colors.black : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16)))),
              ]),
              const SizedBox(height: 20),
              Text("Cycles: $_cycleCount",
                  style: TextStyle(
                      color: Colors.grey, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 9. JOURNAL PAGE
// -----------------------------------------------------------------------------

class JournalPage extends StatefulWidget {
  const JournalPage({super.key});
  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage> {
  List<Map<String, dynamic>> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final String? entriesStr = prefs.getString('journal_entries');
    if (entriesStr != null)
      setState(() =>
          _entries = List<Map<String, dynamic>>.from(jsonDecode(entriesStr)));
  }

  Future<void> _saveEntries() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('journal_entries', jsonEncode(_entries));
  }

  void _addEntry(String q1, String q2, String q3) {
    final now = DateTime.now();
    if (_entries.any((e) => isSameDay(DateTime.parse(e['date']), now))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Only one reflection allowed per day."),
          backgroundColor: Colors.black));
      return;
    }
    setState(() => _entries.insert(
        0, {'date': now.toIso8601String(), 'q1': q1, 'q2': q2, 'q3': q3}));
    _saveEntries();
  }

  void _deleteEntry(int index) {
    setState(() => _entries.removeAt(index));
    _saveEntries();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textC = isDark ? Colors.white : Colors.black;

    return Scaffold(
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 90),
        child: FloatingActionButton(
          onPressed: () {
            final now = DateTime.now();
            if (_entries
                .any((e) => isSameDay(DateTime.parse(e['date']), now))) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text("Only one reflection allowed per day."),
                  backgroundColor: Colors.black));
            } else {
              showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => JournalEntrySheet(onSave: _addEntry));
            }
          },
          backgroundColor: textC,
          elevation: 4,
          highlightElevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Icon(CupertinoIcons.pen,
              color: isDark ? Colors.black : Colors.white, size: 28),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("EVENING REFLECTION",
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 3,
                                color: Colors.grey)),
                        const SizedBox(height: 10),
                        Text("Review your day.\nPrepare for tomorrow.",
                            style: GoogleFonts.lora(
                                fontSize: 24,
                                fontStyle: FontStyle.italic,
                                color: textC))
                      ])),
            ),
            Expanded(
              child: _entries.isEmpty
                  ? Center(
                      child: Text("No entries yet.",
                          style: GoogleFonts.inter(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.only(
                          left: 24, right: 24, top: 10, bottom: 120),
                      itemCount: _entries.length,
                      itemBuilder: (context, index) {
                        final entry = _entries[index];
                        final date = DateTime.parse(entry['date']);
                        return Dismissible(
                          key: Key(entry['date']),
                          direction: DismissDirection.endToStart,
                          background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              color: Colors.red.withValues(alpha: 0.1),
                              child: const Icon(CupertinoIcons.trash,
                                  color: Colors.red)),
                          onDismissed: (_) => _deleteEntry(index),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1C1C1E)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4))
                                ]),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      DateFormat('EEEE, d MMM yyyy')
                                          .format(date),
                                      style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey)),
                                  const SizedBox(height: 12),
                                  _buildQA(
                                      "What went well?", entry['q1'], textC),
                                  _buildQA(
                                      "What went wrong?", entry['q2'], textC),
                                  _buildQA(
                                      "What did I learn?", entry['q3'], textC),
                                ]),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQA(String q, String a, Color textC) {
    return Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(q,
              style: GoogleFonts.inter(
                  fontSize: 11, fontWeight: FontWeight.w600, color: textC)),
          const SizedBox(height: 4),
          Text(a,
              style: GoogleFonts.inter(
                  fontSize: 14, color: Colors.grey, height: 1.4))
        ]));
  }
}

class JournalEntrySheet extends StatefulWidget {
  final Function(String, String, String) onSave;
  const JournalEntrySheet({super.key, required this.onSave});
  @override
  State<JournalEntrySheet> createState() => _JournalEntrySheetState();
}

class _JournalEntrySheetState extends State<JournalEntrySheet> {
  final _c1 = TextEditingController();
  final _c2 = TextEditingController();
  final _c3 = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.95)
        : Colors.white.withValues(alpha: 0.95);
    final textC = isDark ? Colors.white : Colors.black;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 40,
              top: 30,
              left: 30,
              right: 30),
          decoration: BoxDecoration(color: bg),
          child: SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                      child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 30),
                  Text("REFLECTION",
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          letterSpacing: 1.5,
                          color: Colors.grey)),
                  const SizedBox(height: 20),
                  _buildInput("1. What went well today?", _c1, textC, isDark),
                  const SizedBox(height: 20),
                  _buildInput("2. What went wrong?", _c2, textC, isDark),
                  const SizedBox(height: 20),
                  _buildInput("3. What did I learn?", _c3, textC, isDark),
                  const SizedBox(height: 30),
                  SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: textC,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16))),
                          onPressed: () {
                            if (_c1.text.isNotEmpty ||
                                _c2.text.isNotEmpty ||
                                _c3.text.isNotEmpty) {
                              widget.onSave(_c1.text, _c2.text, _c3.text);
                              Navigator.pop(context);
                            }
                          },
                          child: Text("Save Entry",
                              style: TextStyle(
                                  color:
                                      isDark ? Colors.black : Colors.white)))),
                ]),
          ),
        ),
      ),
    );
  }

  Widget _buildInput(String label, TextEditingController controller,
      Color textC, bool isDark) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: GoogleFonts.inter(
              fontSize: 14, fontWeight: FontWeight.bold, color: textC)),
      const SizedBox(height: 8),
      TextField(
          controller: controller,
          maxLines: 3,
          style: GoogleFonts.inter(fontSize: 14, color: textC),
          decoration: InputDecoration(
              filled: true,
              fillColor: isDark ? Colors.black : Colors.grey[100],
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.all(12)))
    ]);
  }
}

// -----------------------------------------------------------------------------
// 10. PAGE 2: MEMENTO MORI
// -----------------------------------------------------------------------------

class MementoMoriPage extends StatelessWidget {
  const MementoMoriPage({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startOfYear = DateTime(now.year, 1, 1);
    final dayOfYear = now.difference(startOfYear).inDays + 1;
    final daysLeft = 365 - dayOfYear;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textC = isDark ? Colors.white : Colors.black;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("MEMENTO MORI",
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                      color: Colors.grey)),
              const SizedBox(height: 10),
              Text("Only $daysLeft days left.\nMake them count.",
                  style: GoogleFonts.lora(
                      fontSize: 28,
                      fontStyle: FontStyle.italic,
                      height: 1.2,
                      color: textC)),
              const SizedBox(height: 20),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.only(bottom: 120),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 15,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8),
                  itemCount: 365,
                  itemBuilder: (context, index) {
                    final isPast = index < dayOfYear;
                    return Container(
                        decoration: BoxDecoration(
                            color: isPast
                                ? (isDark ? Colors.white : Colors.black)
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.black.withValues(alpha: 0.05)),
                            borderRadius: BorderRadius.circular(2)));
                  },
                ).animate().fadeIn(duration: 800.ms),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 11. PAGE 3: HABITS
// -----------------------------------------------------------------------------

class HabitsPage extends StatefulWidget {
  const HabitsPage({super.key});
  @override
  State<HabitsPage> createState() => _HabitsPageState();
}

class _HabitsPageState extends State<HabitsPage> {
  List<Map<String, dynamic>> _habits = [];

  @override
  void initState() {
    super.initState();
    _loadHabits();
  }

  Future<void> _loadHabits() async {
    final prefs = await SharedPreferences.getInstance();
    final String? habitsString = prefs.getString('habits');
    if (habitsString != null) {
      setState(() =>
          _habits = List<Map<String, dynamic>>.from(jsonDecode(habitsString)));
      _checkHabitDays();
    }
  }

  // --- LOGIC: Check Interval OR Specific Days ---
  void _checkHabitDays() {
    final now = DateTime.now();
    bool changed = false;
    for (var habit in _habits) {
      final String type = habit['repeatType'] ?? 'interval';
      final lastDoneStr = habit['lastDoneDate'];

      if (type == 'interval') {
        final int freq = habit['frequency'] ?? 1;
        if (habit['isDone'] == true && lastDoneStr != null) {
          final diff = now.difference(DateTime.parse(lastDoneStr)).inDays;
          if (diff >= freq) {
            habit['isDone'] = false;
            changed = true;
          }
        }
        if (lastDoneStr != null) {
          final diff = now.difference(DateTime.parse(lastDoneStr)).inDays;
          if (diff > freq) {
            habit['streak'] = 0;
            changed = true;
          }
        }
      } else {
        if (habit['isDone'] == true && lastDoneStr != null) {
          if (!isSameDay(DateTime.parse(lastDoneStr), now)) {
            habit['isDone'] = false;
            changed = true;
          }
        }
        if (lastDoneStr != null) {
          final lastDone = DateTime.parse(lastDoneStr);
          final weekdays = List<int>.from(habit['weekdays'] ?? []);
          DateTime cursor = lastDone.add(const Duration(days: 1));
          while (cursor.isBefore(DateTime(now.year, now.month, now.day))) {
            if (weekdays.contains(cursor.weekday)) {
              habit['streak'] = 0;
              changed = true;
              break;
            }
            cursor = cursor.add(const Duration(days: 1));
          }
        }
      }
    }
    if (changed) _saveHabits();
  }

  Future<void> _saveHabits() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('habits', jsonEncode(_habits));
  }

  void _addHabit(String title, String tags, int color, int frequency,
      List<int>? weekdays) {
    setState(() {
      _habits.add({
        'id': DateTime.now().millisecondsSinceEpoch,
        'title': title,
        'streak': 0,
        'isDone': false,
        'tags': tags,
        'color': color,
        'frequency': frequency,
        'repeatType': weekdays != null ? 'weekdays' : 'interval',
        'weekdays': weekdays,
        'lastDoneDate': null,
      });
    });
    _saveHabits();
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _habits.removeAt(oldIndex);
      _habits.insert(newIndex, item);
    });
    _saveHabits();
  }

  void _deleteHabit(int index) {
    setState(() => _habits.removeAt(index));
    _saveHabits();
  }

  void _updateHabit(int index, String title, String tags, int colorValue,
      int freq, List<int>? weekdays) {
    setState(() {
      _habits[index]['title'] = title;
      _habits[index]['tags'] = tags;
      _habits[index]['color'] = colorValue;
      _habits[index]['frequency'] = freq;
      _habits[index]['repeatType'] = weekdays != null ? 'weekdays' : 'interval';
      _habits[index]['weekdays'] = weekdays;
    });
    _saveHabits();
  }

  // ignore: unused_element
  void _showHabitDetails(int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TaskDetailSheet(
        initialTitle: _habits[index]['title'],
        initialTags: _habits[index]['tags'] ?? '',
        initialColor: _habits[index]['color'] ?? Colors.white.value,
        initialTime: null,
        initialFrequency: _habits[index]['frequency'] ?? 1,
        isHabit: true,
        onSave: (title, tags, color, time, freq, {weekdays}) =>
            _updateHabit(index, title, tags, color, freq, weekdays),
        onDelete: () {
          _deleteHabit(index);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showAddHabitSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TaskDetailSheet(
        initialTitle: "",
        initialTags: "",
        initialColor: Colors.white.value,
        initialTime: null,
        initialFrequency: 1,
        isHabit: true,
        isNew: true,
        onSave: (title, tags, color, time, freq, {weekdays}) {
          if (title.isNotEmpty) _addHabit(title, tags, color, freq, weekdays);
        },
      ),
    );
  }

  void _toggleHabit(int index) {
    setState(() {
      final habit = _habits[index];
      final now = DateTime.now();

      if (habit['isDone']) {
        habit['isDone'] = false;
      } else {
        habit['isDone'] = true;
        performHaptic(HapticFeedbackType.heavy);
        SystemSound.play(SystemSoundType.click);

        final lastDoneStr = habit['lastDoneDate'];
        bool increment = false;

        if (lastDoneStr == null)
          increment = true;
        else {
          final lastDone = DateTime.parse(lastDoneStr);
          if (!isSameDay(lastDone, now)) {
            if (habit['repeatType'] != 'weekdays') {
              final diff = now
                  .difference(
                      DateTime(lastDone.year, lastDone.month, lastDone.day))
                  .inDays;
              if (diff <= (habit['frequency'] ?? 1))
                increment = true;
              else
                habit['streak'] = 0;
            } else {
              final weekdays = List<int>.from(habit['weekdays'] ?? []);
              bool missed = false;
              DateTime cursor = lastDone.add(const Duration(days: 1));
              while (cursor.isBefore(DateTime(now.year, now.month, now.day))) {
                if (weekdays.contains(cursor.weekday)) {
                  missed = true;
                  break;
                }
                cursor = cursor.add(const Duration(days: 1));
              }
              if (!missed)
                increment = true;
              else {
                habit['streak'] = 0;
                increment = true;
              }
            }
          }
        }

        if (increment) {
          habit['streak'] = (habit['streak'] ?? 0) + 1;
          habit['lastDoneDate'] = now.toIso8601String();
        }
      }
    });
    _saveHabits();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textC = isDark ? Colors.white : Colors.black;

    return Scaffold(
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 90),
        child: FloatingActionButton(
          onPressed: () => _showAddHabitSheet(context),
          backgroundColor: textC,
          elevation: 4,
          highlightElevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Icon(Icons.add,
              color: isDark ? Colors.black : Colors.white, size: 28),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text("DAILY RITUALS",
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 3,
                          color: Colors.grey))),
            ),
            Expanded(
              child: _habits.isEmpty
                  ? Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                          Icon(CupertinoIcons.repeat,
                              size: 48, color: Colors.grey),
                          SizedBox(height: 16),
                          Text("No rituals yet.\nDiscipline starts now.",
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                  color: Colors.grey, fontSize: 16))
                        ]))
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.only(
                          top: 10, left: 24, right: 24, bottom: 120),
                      itemCount: _habits.length,
                      onReorder: _onReorder,
                      proxyDecorator: (child, index, animation) =>
                          Material(color: Colors.transparent, child: child),
                      itemBuilder: (context, index) {
                        final habit = _habits[index];
                        String freqText = "";
                        if (habit['repeatType'] == 'weekdays') {
                          final List<int> days =
                              List<int>.from(habit['weekdays'] ?? []);
                          const weekMap = {
                            1: 'M',
                            2: 'T',
                            3: 'W',
                            4: 'T',
                            5: 'F',
                            6: 'S',
                            7: 'S'
                          };
                          days.sort();
                          freqText = days.map((d) => weekMap[d]).join(" ");
                        } else {
                          final freq = habit['frequency'] ?? 1;
                          if (freq > 1) freqText = "Every $freq days";
                        }

                        return ReorderableDismissibleTaskCard(
                          key: Key("habit_${habit['id']}"),
                          task: habit,
                          isHabit: true,
                          extraInfo: freqText,
                          onToggle: () => _toggleHabit(index),
                          onTap: () => showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (context) => TaskDetailSheet(
                              initialTitle: habit['title'],
                              initialTags: habit['tags'] ?? '',
                              initialColor:
                                  habit['color'] ?? Colors.white.value,
                              initialTime: null,
                              initialFrequency: habit['frequency'] ?? 1,
                              isHabit: true,
                              onSave: (title, tags, color, time, freq,
                                      {weekdays}) =>
                                  _updateHabit(index, title, tags, color, freq,
                                      weekdays),
                              onDelete: () => _deleteHabit(index),
                            ),
                          ),
                          onDelete: () => _deleteHabit(index),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 12. SHARED WIDGETS
// -----------------------------------------------------------------------------

class ReorderableDismissibleTaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final VoidCallback onToggle;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool isHabit;
  final String? extraInfo;

  const ReorderableDismissibleTaskCard(
      {required Key key,
      required this.task,
      required this.onToggle,
      required this.onTap,
      required this.onDelete,
      this.isHabit = false,
      this.extraInfo})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colorVal = task['color'] ?? Colors.white.value;
    final bgColor = getCardColor(context, colorVal);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textC = getTextColor(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: key!,
        direction: DismissDirection.endToStart,
        background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(48)),
            child: const Icon(CupertinoIcons.trash, color: Colors.red)),
        onDismissed: (_) => onDelete(),
        child: GestureDetector(
          onTap: onTap,
          onLongPress: () {},
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            decoration: ShapeDecoration(
                color: bgColor,
                shape: ContinuousRectangleBorder(
                    borderRadius: BorderRadius.circular(48)),
                shadows: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ]),
            child: Row(children: [
              GestureDetector(
                  onTap: onToggle,
                  child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 24,
                      height: 24,
                      decoration: ShapeDecoration(
                          color: task['isDone'] ? textC : Colors.transparent,
                          shape: ContinuousRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: textC, width: 1.5))),
                      child: task['isDone']
                          ? Icon(Icons.check,
                              size: 16,
                              color: isDark ? Colors.black : Colors.white)
                          : null)),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: task['isDone'] ? 0.3 : 1.0,
                        child: Text(task['title'],
                            style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: textC,
                                decoration: task['isDone']
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor: textC))),
                    Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            children: [
                              if (isHabit)
                                Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                        color:
                                            Colors.grey.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4)),
                                    child: Text("🔥 ${task['streak'] ?? 0}",
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: textC))),
                              if (extraInfo != null && extraInfo!.isNotEmpty)
                                Text("↻ $extraInfo",
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w600)),
                              if (task['time'] != null && !task['isDone'])
                                Text("⏰ ${task['time']}",
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                              if (task['tags'] != null &&
                                  task['tags'].toString().isNotEmpty)
                                Text("#${task['tags']}",
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                        fontWeight: FontWeight.bold)),
                            ])),
                  ])),
            ]),
          ),
        ),
      ),
    );
  }
}

class TaskDetailSheet extends StatefulWidget {
  final String initialTitle;
  final String initialTags;
  final int initialColor;
  final String? initialTime;
  final int initialFrequency;
  final bool isHabit;
  final bool isNew;
  final Function(String, String, int, String?, int, {List<int>? weekdays})
      onSave;
  final VoidCallback? onDelete;

  const TaskDetailSheet(
      {super.key,
      required this.initialTitle,
      required this.initialTags,
      required this.initialColor,
      this.initialTime,
      required this.initialFrequency,
      required this.isHabit,
      this.isNew = false,
      required this.onSave,
      this.onDelete});

  @override
  State<TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends State<TaskDetailSheet> {
  late TextEditingController _titleController;
  late TextEditingController _tagsController;
  late int _selectedColor;
  late int _selectedFrequency;
  String? _selectedTime;

  String _repeatType = 'interval';
  List<int> _selectedWeekdays = [];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _tagsController = TextEditingController(text: widget.initialTags);
    _selectedColor = widget.initialColor;
    _selectedTime = widget.initialTime;
    _selectedFrequency = widget.initialFrequency;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.95)
        : Colors.white.withValues(alpha: 0.95);
    final textC = isDark ? Colors.white : Colors.black;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 40,
              top: 30,
              left: 30,
              right: 30),
          decoration: BoxDecoration(color: bg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Text(
                  widget.isNew
                      ? (widget.isHabit ? "NEW HABIT" : "NEW TASK")
                      : "EDIT",
                  style: GoogleFonts.inter(
                      fontSize: 10, letterSpacing: 1.5, color: Colors.grey)),
              TextField(
                  controller: _titleController,
                  autofocus: widget.isNew,
                  style: GoogleFonts.inter(
                      fontSize: 20, fontWeight: FontWeight.w600, color: textC),
                  decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: widget.isNew ? "What needs to be done?" : null,
                      hintStyle: TextStyle(color: Colors.grey))),
              const SizedBox(height: 20),
              if (widget.isHabit) ...[
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("REPEAT TYPE",
                          style: GoogleFonts.inter(
                              fontSize: 10,
                              letterSpacing: 1.5,
                              color: Colors.grey)),
                      CupertinoSlidingSegmentedControl<String>(
                          groupValue: _repeatType,
                          children: const {
                            'interval': Text("Every X Days"),
                            'weekdays': Text("Weekdays")
                          },
                          onValueChanged: (val) {
                            setState(() => _repeatType = val!);
                          },
                          thumbColor: isDark ? Colors.grey[800]! : Colors.white)
                    ]),
                const SizedBox(height: 15),
                if (_repeatType == 'interval')
                  SizedBox(
                      height: 100,
                      child: CupertinoPicker(
                          backgroundColor: Colors.transparent,
                          itemExtent: 32,
                          scrollController: FixedExtentScrollController(
                              initialItem: _selectedFrequency - 1),
                          onSelectedItemChanged: (index) =>
                              setState(() => _selectedFrequency = index + 1),
                          children: List.generate(
                              30,
                              (index) => Center(
                                  child: Text(
                                      index == 0
                                          ? "Every Day"
                                          : "Every ${index + 1} Days",
                                      style: GoogleFonts.inter(
                                          fontSize: 16, color: textC))))))
                else
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(7, (index) {
                        final day = index + 1;
                        final isSelected = _selectedWeekdays.contains(day);
                        const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                        return GestureDetector(
                            onTap: () => setState(() {
                                  isSelected
                                      ? _selectedWeekdays.remove(day)
                                      : _selectedWeekdays.add(day);
                                }),
                            child: Container(
                                width: 35,
                                height: 35,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                    color:
                                        isSelected ? textC : Colors.transparent,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: textC)),
                                child: Text(labels[index],
                                    style: TextStyle(
                                        color: isSelected
                                            ? (isDark
                                                ? Colors.black
                                                : Colors.white)
                                            : textC,
                                        fontWeight: FontWeight.bold))));
                      })),
                const SizedBox(height: 20),
              ],
              Text("TAGS",
                  style: GoogleFonts.inter(
                      fontSize: 10, letterSpacing: 1.5, color: Colors.grey)),
              TextField(
                  controller: _tagsController,
                  style: GoogleFonts.inter(fontSize: 16, color: textC),
                  decoration: const InputDecoration(
                      hintText: "e.g. Work, Gym",
                      border: InputBorder.none,
                      hintStyle: TextStyle(color: Colors.grey))),
              const SizedBox(height: 20),
              Text("COLOR",
                  style: GoogleFonts.inter(
                      fontSize: 10, letterSpacing: 1.5, color: Colors.grey)),
              const SizedBox(height: 10),
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: kTaskColors
                      .map((c) => GestureDetector(
                          onTap: () => setState(() => _selectedColor = c.value),
                          child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.grey[300]!),
                                  boxShadow: _selectedColor == c.value
                                      ? [
                                          BoxShadow(
                                              color:
                                                  Colors.black.withOpacity(0.2),
                                              blurRadius: 6)
                                        ]
                                      : []),
                              child: _selectedColor == c.value
                                  ? const Icon(Icons.check,
                                      size: 16, color: Colors.black)
                                  : null)))
                      .toList()),
              const SizedBox(height: 20),
              if (!widget.isHabit) ...[
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("NOTIFICATION",
                          style: GoogleFonts.inter(
                              fontSize: 10,
                              letterSpacing: 1.5,
                              color: Colors.grey)),
                      GestureDetector(
                          onTap: () async {
                            final t = await showTimePicker(
                                context: context, initialTime: TimeOfDay.now());
                            if (t != null)
                              setState(() =>
                                  _selectedTime = "${t.hour}:${t.minute}");
                          },
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                  color: _selectedTime != null
                                      ? textC
                                      : Colors.grey.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12)),
                              child: Text(_selectedTime ?? "Set Time",
                                  style: TextStyle(
                                      color: _selectedTime != null
                                          ? (isDark
                                              ? Colors.black
                                              : Colors.white)
                                          : textC,
                                      fontWeight: FontWeight.bold))))
                    ]),
                if (_selectedTime != null)
                  Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                          onPressed: () => setState(() => _selectedTime = null),
                          child: const Text("Clear",
                              style:
                                  TextStyle(color: Colors.red, fontSize: 12))))
              ],
              const SizedBox(height: 30),
              SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: textC,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16))),
                      onPressed: () {
                        if (_titleController.text.isNotEmpty) {
                          widget.onSave(
                              _titleController.text,
                              _tagsController.text,
                              _selectedColor,
                              _selectedTime,
                              _selectedFrequency,
                              weekdays: _repeatType == 'weekdays'
                                  ? _selectedWeekdays
                                  : null);
                          Navigator.pop(context);
                        }
                      },
                      child: Text(widget.isNew ? "Create" : "Save Changes",
                          style: TextStyle(
                              color: isDark ? Colors.black : Colors.white)))),
              if (!widget.isNew && widget.onDelete != null) ...[
                const SizedBox(height: 16),
                SizedBox(
                    width: double.infinity,
                    child: TextButton(
                        onPressed: widget.onDelete,
                        child: Text(
                            widget.isHabit ? "Delete Habit" : "Delete Task",
                            style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold))))
              ],
            ],
          ),
        ),
      ),
    );
  }
}
