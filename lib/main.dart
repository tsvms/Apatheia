import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

// -----------------------------------------------------------------------------
// 1. GLOBAL SETTINGS MANAGER (Theme & Haptics)
// -----------------------------------------------------------------------------

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);
final ValueNotifier<bool> hapticsNotifier = ValueNotifier(true);

Future<void> _loadSettings() async {
  final prefs = await SharedPreferences.getInstance();
  final String? themeStr = prefs.getString('theme_mode');
  if (themeStr == 'light')
    themeNotifier.value = ThemeMode.light;
  else if (themeStr == 'dark')
    themeNotifier.value = ThemeMode.dark;
  else
    themeNotifier.value = ThemeMode.system;
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
// 2. SERVICES (NOTIFICATIONS)
// -----------------------------------------------------------------------------

class NotificationService {
  static final _notifications = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    tz.initializeTimeZones();
    final timeZoneInfo = await FlutterTimezone.getLocalTimezone();
    final String timeZoneName = timeZoneInfo.identifier;
    tz.setLocalLocation(tz.getLocation(timeZoneName));

    const androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    final iosSettings = DarwinInitializationSettings();
    final settings =
        InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _notifications.initialize(settings);

    _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
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
        iOS: DarwinNotificationDetails(
            presentAlert: true, presentBadge: true, presentSound: true),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
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
        iOS: DarwinNotificationDetails(
            presentAlert: true, presentBadge: true, presentSound: true),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static Future<void> scheduleDailyQuotes(int hour, int minute) async {
    await _notifications.cancel(888);
    for (int i = 0; i < 7; i++) {
      await _notifications.cancel(800 + i);
    }

    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime firstSchedule =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    if (firstSchedule.isBefore(now)) {
      firstSchedule = firstSchedule.add(const Duration(days: 1));
    }

    for (int i = 0; i < 7; i++) {
      tz.TZDateTime scheduledDate = firstSchedule.add(Duration(days: i));
      String quoteForThatDay = getDailyQuote(scheduledDate);

      await _notifications.zonedSchedule(
        800 + i,
        "Daily Wisdom",
        quoteForThatDay,
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
              'daily_channel', 'Daily Reminders',
              styleInformation: BigTextStyleInformation(''),
              importance: Importance.max,
              priority: Priority.high),
          iOS: DarwinNotificationDetails(
              presentAlert: true, presentBadge: true, presentSound: true),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
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

String getDailyQuote(DateTime date) {
  int daysSinceEpoch = date.difference(DateTime(2024, 1, 1)).inDays.abs();
  return kQuotes[daysSinceEpoch % kQuotes.length];
}

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
  try {
    await NotificationService.init();
  } catch (e) {
    debugPrint("Notification Init Error: $e");
  }
  try {
    await _loadSettings();
  } catch (e) {
    debugPrint("Settings Init Error: $e");
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  try {
    final prefs = await SharedPreferences.getInstance();
    int qHour = prefs.getInt('quote_hour') ?? 9;
    int qMinute = prefs.getInt('quote_minute') ?? 0;

    await NotificationService.scheduleDailyQuotes(qHour, qMinute);

    NotificationService.scheduleDaily(
        id: 889,
        title: "Stay Disciplined",
        body: "Don't let the streak end, add a task for today!",
        hour: 18,
        minute: 0);

    NotificationService.scheduleDaily(
        id: 890,
        title: "Evening Reflection",
        body: "Time to review your day.",
        hour: 20,
        minute: 0);
  } catch (e) {
    debugPrint("Scheduling Error: $e");
  }

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
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
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
                ),
              ).animate().fadeIn(duration: 500.ms).moveY(begin: 50.0, end: 0.0),
            ),
          ],
        ),
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
      child: AnimatedScale(
        scale: isSelected ? 1.15 : 1.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
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
              Text("HOW APATHEIA WORKS",
                  style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2)),
              const SizedBox(height: 40),
              _buildTip(context, Icons.local_fire_department, "STOIC RANK",
                  "Complete at least one task daily to maintain your global streak and rank up."),
              _buildTip(context, CupertinoIcons.repeat, "HABIT STREAKS",
                  "Set intervals or specific days. Miss a scheduled day, and that habit's streak resets."),
              _buildTip(context, CupertinoIcons.book, "REFLECTION",
                  "You are limited to one journal entry per day to build mindful discipline."),
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
                  child: Text("GOT IT",
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

void _showSettingsSheet(BuildContext context) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final bg = isDark
      ? const Color(0xFF1C1C1E).withValues(alpha: 0.95)
      : Colors.white.withValues(alpha: 0.95);
  final textC = getTextColor(context);

  final prefs = await SharedPreferences.getInstance();
  int savedHour = prefs.getInt('quote_hour') ?? 9;
  int savedMinute = prefs.getInt('quote_minute') ?? 0;

  if (!context.mounted) return;

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
            String timeString =
                TimeOfDay(hour: savedHour, minute: savedMinute).format(context);

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
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text("Quote Notification Time",
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold, color: textC)),
                  subtitle: Text("Currently set to: $timeString",
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: Icon(CupertinoIcons.time, color: textC),
                  onTap: () async {
                    final TimeOfDay? picked = await showTimePicker(
                        context: context,
                        initialTime:
                            TimeOfDay(hour: savedHour, minute: savedMinute));
                    if (picked != null) {
                      await prefs.setInt('quote_hour', picked.hour);
                      await prefs.setInt('quote_minute', picked.minute);
                      setState(() {
                        savedHour = picked.hour;
                        savedMinute = picked.minute;
                      });

                      await NotificationService.scheduleDailyQuotes(
                          picked.hour, picked.minute);

                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              "Notification updated to ${picked.format(context)}"),
                          backgroundColor: Colors.black));
                    }
                  },
                ),
                const Divider(),
                Text("Appearance",
                    style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textC)),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoSegmentedControl<ThemeMode>(
                    groupValue: themeNotifier.value,
                    borderColor: isDark ? Colors.grey[700] : Colors.black,
                    selectedColor: isDark ? Colors.white : Colors.black,
                    unselectedColor: Colors.transparent,
                    pressedColor: isDark ? Colors.grey[800] : Colors.grey[200],
                    children: {
                      ThemeMode.system: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text("System",
                              style: TextStyle(
                                  color: themeNotifier.value == ThemeMode.system
                                      ? (isDark ? Colors.black : Colors.white)
                                      : textC,
                                  fontSize: 13))),
                      ThemeMode.light: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text("Light",
                              style: TextStyle(
                                  color: themeNotifier.value == ThemeMode.light
                                      ? (isDark ? Colors.black : Colors.white)
                                      : textC,
                                  fontSize: 13))),
                      ThemeMode.dark: Padding(
                          padding: const EdgeInsets.all(10),
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
      _currentQuote = getDailyQuote(DateTime.now());
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

  // ΝΕΑ ΛΕΙΤΟΥΡΓΙΑ: Sort by Priority
  void _sortByPriority() {
    setState(() {
      _tasks.sort((a, b) {
        int priorityA = a['priority'] ?? 0;
        int priorityB = b['priority'] ?? 0;
        return priorityB.compareTo(priorityA); // Τα High (2) πάνε πάνω
      });
    });
    _saveTasks();
    performHaptic(HapticFeedbackType.light);
  }

  Future<void> _logActivity() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().toIso8601String().split('T')[0];
    if (!_activityLog.contains(now)) {
      _activityLog.add(now);
      await prefs.setStringList('activity_log', _activityLog);
    }
  }

  Future<void> _addTask(String title, String tags, int color, String? time,
      {int priority = 0}) async {
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
        'color': color,
        'priority': priority
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

  void _updateTask(int index, String title, String tags, int colorValue,
      String? time, int priority) {
    setState(() {
      _tasks[index]['title'] = title;
      _tasks[index]['tags'] = tags;
      _tasks[index]['color'] = colorValue;
      _tasks[index]['time'] = time;
      _tasks[index]['priority'] = priority;
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
              onSave: (title, tags, color, time, freq, {weekdays, priority}) {
                if (title.isNotEmpty)
                  _addTask(title, tags, color, time, priority: priority ?? 0);
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
                      .moveY(begin: 20.0, end: 0.0),

                  const SizedBox(height: 20),
                  // ΤΟ ΝΕΟ ΚΟΥΜΠΙ SORT BY PRIORITY
                  if (_tasks.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: _sortByPriority,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey[800]?.withValues(alpha: 0.5)
                                : Colors.grey[200]?.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(CupertinoIcons.sort_down,
                                  size: 14, color: textC),
                              const SizedBox(width: 6),
                              Text("Sort",
                                  style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: textC)),
                            ],
                          ),
                        ),
                      ),
                    ).animate().fadeIn(duration: 400.ms),
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
                                    size: 48,
                                    color: Colors.grey.withValues(alpha: 0.5)),
                                const SizedBox(height: 16),
                                Text("Empty mind.\nPeaceful life.",
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                        color: Colors.grey, fontSize: 16)),
                                const SizedBox(height: 30),
                                Icon(CupertinoIcons.arrow_down,
                                        color:
                                            Colors.grey.withValues(alpha: 0.3))
                                    .animate(
                                        onPlay: (controller) =>
                                            controller.repeat(reverse: true))
                                    .moveY(
                                        begin: -5.0,
                                        end: 5.0,
                                        duration: 1.seconds),
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
                                    initialPriority:
                                        _tasks[index]['priority'] ?? 0,
                                    onSave: (title, tags, color, time, freq,
                                            {weekdays, priority}) =>
                                        _updateTask(index, title, tags, color,
                                            time, priority ?? 0),
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
// 8. POMODORO PAGE (Final Clean Version)
// -----------------------------------------------------------------------------

enum PomodoroMode { focus, shortBreak, longBreak }

class PomodoroPage extends StatefulWidget {
  const PomodoroPage({super.key});
  @override
  State<PomodoroPage> createState() => _PomodoroPageState();
}

class _PomodoroPageState extends State<PomodoroPage>
    with WidgetsBindingObserver {
  int _userFocusTime = 25;
  PomodoroMode _mode = PomodoroMode.focus;
  late int _timeLeft;
  Timer? _timer;
  bool _isActive = false;
  int _cycleCount = 0;
  DateTime? _targetTime;

  @override
  void initState() {
    super.initState();
    _timeLeft = _userFocusTime * 60;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _isActive &&
        _targetTime != null) {
      final now = DateTime.now();
      if (now.isAfter(_targetTime!)) {
        _timer?.cancel();
        setState(() {
          _isActive = false;
          _targetTime = null;
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
      } else {
        setState(() {
          _timeLeft = _targetTime!.difference(now).inSeconds;
        });
      }
    }
  }

  void _toggleTimer() {
    if (_isActive) {
      _timer?.cancel();
      NotificationService.cancel(999);
      setState(() {
        _isActive = false;
        _targetTime = null;
      });
    } else {
      setState(() {
        _isActive = true;
        _targetTime = DateTime.now().add(Duration(seconds: _timeLeft));
      });

      NotificationService.scheduleNotification(
        id: 999,
        title: _mode == PomodoroMode.focus
            ? "Focus Session Complete!"
            : "Break is over!",
        scheduledTime: _targetTime!,
      );

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
    _targetTime = null;
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
    NotificationService.cancel(999);
    setState(() {
      _isActive = false;
      _targetTime = null;
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
    final double progress = 1 -
        (_timeLeft /
            (_mode == PomodoroMode.focus
                ? (_userFocusTime * 60)
                : (_mode == PomodoroMode.longBreak ? 900 : 300)));

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(
              left: 32.0,
              right: 32.0,
              top: 40.0,
              bottom: 120.0), // Πιο πολύ κενό για το notch/navbar
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 1. Elegant Top Mode Pill (Πιο κεντραρισμένο)
              const SizedBox(height: 10), // Επιπλέον κενό από το notch

              // 2. Huge Minimalist Timer
              Stack(alignment: Alignment.center, children: [
                // Mode Pill is now INSIDE the circle group for safety
                if (_isActive)
                  Container(
                    width: 310,
                    height: 310,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: textC.withValues(alpha: 0.03),
                    ),
                  )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scaleXY(begin: 1.0, end: 1.05, duration: 2.seconds),

                SizedBox(
                    width: 280,
                    height: 280,
                    child: CircularProgressIndicator(
                      value: 1.0,
                      strokeWidth: 2,
                      backgroundColor: Colors.transparent,
                      color: isDark ? Colors.white10 : Colors.black12,
                    )),

                SizedBox(
                    width: 280,
                    height: 280,
                    child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 8,
                        backgroundColor: Colors.transparent,
                        color: textC,
                        strokeCap: StrokeCap.round)),

                Column(mainAxisSize: MainAxisSize.min, children: [
                  // Mode Label inside circle
                  Text(_modeString,
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          letterSpacing: 2,
                          color: Colors.grey,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(_timerString,
                      style: GoogleFonts.inter(
                          fontSize: 80,
                          fontWeight: FontWeight.w200,
                          letterSpacing: -2,
                          color: textC)),
                  if (_mode == PomodoroMode.focus && !_isActive)
                    Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: GestureDetector(
                            onTap: _changeDuration,
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
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

              // 3. Modern Controls Row
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(
                    onPressed: _resetTimer,
                    icon: const Icon(CupertinoIcons.refresh,
                        size: 24, color: Colors.grey)),
                const SizedBox(width: 40),
                GestureDetector(
                    onTap: _toggleTimer,
                    child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                            color: textC,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: textC.withValues(alpha: 0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10))
                            ]),
                        child: Icon(
                            _isActive
                                ? CupertinoIcons.pause_solid
                                : CupertinoIcons.play_arrow_solid,
                            color: isDark ? Colors.black : Colors.white,
                            size: 36))),
                const SizedBox(width: 40),
                Column(
                  children: [
                    const Icon(CupertinoIcons.arrow_2_circlepath,
                        size: 20, color: Colors.grey),
                    const SizedBox(height: 4),
                    Text("$_cycleCount/4",
                        style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ]),
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

  void _updateEntry(int index, String q1, String q2, String q3) {
    setState(() {
      _entries[index]['q1'] = q1;
      _entries[index]['q2'] = q2;
      _entries[index]['q3'] = q3;
    });
    _saveEntries();
  }

  void _deleteEntry(int index) {
    setState(() => _entries.removeAt(index));
    _saveEntries();
  }

  void _showReadEntrySheet(
      BuildContext context, int index, Map<String, dynamic> entry) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.95)
        : Colors.white.withValues(alpha: 0.95);
    final textC = isDark ? Colors.white : Colors.black;
    final date = DateTime.parse(entry['date']);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(color: bg),
            child: SafeArea(
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
                  const SizedBox(height: 30),
                  Text(
                      DateFormat('EEEE, d MMM yyyy').format(date).toUpperCase(),
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          letterSpacing: 1.5,
                          color: Colors.grey)),
                  const SizedBox(height: 20),
                  _buildQA("What went well?", entry['q1'], textC, isDark),
                  _buildQA("What went wrong?", entry['q2'], textC, isDark),
                  _buildQA("What did I learn?", entry['q3'], textC, isDark),
                  const SizedBox(height: 40),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _deleteEntry(index);
                            performHaptic(HapticFeedbackType.medium);
                          },
                          icon: const Icon(CupertinoIcons.trash,
                              color: Colors.red, size: 18),
                          label: const Text("Delete",
                              style: TextStyle(color: Colors.red)),
                          style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: const BorderSide(color: Colors.red),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16))),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (context) => JournalEntrySheet(
                                initialQ1: entry['q1'],
                                initialQ2: entry['q2'],
                                initialQ3: entry['q3'],
                                onSave: (q1, q2, q3) =>
                                    _updateEntry(index, q1, q2, q3),
                              ),
                            );
                          },
                          icon: Icon(CupertinoIcons.pen,
                              color: isDark ? Colors.black : Colors.white,
                              size: 18),
                          label: Text("Edit",
                              style: TextStyle(
                                  color: isDark ? Colors.black : Colors.white)),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: textC,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16))),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.only(
                          left: 24, right: 24, top: 10, bottom: 120),
                      itemCount: _entries.length,
                      itemBuilder: (context, index) {
                        final entry = _entries[index];
                        final date = DateTime.parse(entry['date']);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          width: double.infinity,
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 15,
                                    offset: const Offset(0, 8))
                              ]),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Dismissible(
                              key: Key(entry['date']),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 24),
                                color: Colors.red.shade400,
                                child: const Icon(CupertinoIcons.delete,
                                    color: Colors.white),
                              ),
                              onDismissed: (_) => _deleteEntry(index),
                              child: GestureDetector(
                                onTap: () {
                                  performHaptic(HapticFeedbackType.light);
                                  _showReadEntrySheet(context, index, entry);
                                },
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(24),
                                  color: isDark
                                      ? const Color(0xFF1C1C1E)
                                      : Colors.white,
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 6),
                                          decoration: ShapeDecoration(
                                              color: isDark
                                                  ? Colors.grey[800]
                                                  : Colors.grey[100],
                                              shape: const StadiumBorder()),
                                          child: Text(
                                              DateFormat('EEEE, d MMM yyyy')
                                                  .format(date)
                                                  .toUpperCase(),
                                              style: GoogleFonts.inter(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 1.0,
                                                  color: Colors.grey)),
                                        ),
                                        const SizedBox(height: 20),
                                        _buildQA("What went well?", entry['q1'],
                                            textC, isDark),
                                        _buildQA("What went wrong?",
                                            entry['q2'], textC, isDark),
                                        _buildQA("What did I learn?",
                                            entry['q3'], textC, isDark),
                                      ]),
                                ),
                              ),
                            ),
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

  Widget _buildQA(String q, String a, Color textC, bool isDark) {
    if (a.isEmpty) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Icon(CupertinoIcons.quote_bubble_fill,
                size: 14, color: Colors.orange.withValues(alpha: 0.8)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(q,
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: textC.withValues(alpha: 0.6),
                      letterSpacing: 0.5)),
            ),
          ]),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 22.0),
            child: Text(a,
                style: GoogleFonts.lora(
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.black87,
                    height: 1.5,
                    fontStyle: FontStyle.italic)),
          )
        ]));
  }
}

class JournalEntrySheet extends StatefulWidget {
  final String initialQ1;
  final String initialQ2;
  final String initialQ3;
  final Function(String, String, String) onSave;

  const JournalEntrySheet(
      {super.key,
      this.initialQ1 = "",
      this.initialQ2 = "",
      this.initialQ3 = "",
      required this.onSave});

  @override
  State<JournalEntrySheet> createState() => _JournalEntrySheetState();
}

class _JournalEntrySheetState extends State<JournalEntrySheet> {
  late final TextEditingController _c1;
  late final TextEditingController _c2;
  late final TextEditingController _c3;

  @override
  void initState() {
    super.initState();
    _c1 = TextEditingController(text: widget.initialQ1);
    _c2 = TextEditingController(text: widget.initialQ2);
    _c3 = TextEditingController(text: widget.initialQ3);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.95)
        : Colors.white.withValues(alpha: 0.95);
    final textC = isDark ? Colors.white : Colors.black;

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
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
                                    color: isDark
                                        ? Colors.black
                                        : Colors.white)))),
                  ]),
            ),
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
          textInputAction: TextInputAction.done,
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
      List<int>? weekdays, String? time) {
    setState(() {
      _habits.add({
        'id': DateTime.now().millisecondsSinceEpoch,
        'title': title,
        'time': time,
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
      int freq, List<int>? weekdays, String? time) {
    setState(() {
      _habits[index]['title'] = title;
      _habits[index]['tags'] = tags;
      _habits[index]['color'] = colorValue;
      _habits[index]['time'] = time;
      _habits[index]['frequency'] = freq;
      _habits[index]['repeatType'] = weekdays != null ? 'weekdays' : 'interval';
      _habits[index]['weekdays'] = weekdays;
    });
    _saveHabits();
  }

  void _showHabitDetails(int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TaskDetailSheet(
        initialTitle: _habits[index]['title'],
        initialTags: _habits[index]['tags'] ?? '',
        initialColor: _habits[index]['color'] ?? Colors.white.value,
        initialTime: _habits[index]['time'],
        initialFrequency: _habits[index]['frequency'] ?? 1,
        initialRepeatType: _habits[index]['repeatType'] ?? 'interval',
        initialWeekdays: List<int>.from(_habits[index]['weekdays'] ?? []),
        isHabit: true,
        onSave: (title, tags, color, time, freq, {weekdays, priority}) =>
            _updateHabit(index, title, tags, color, freq, weekdays, time),
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
        onSave: (title, tags, color, time, freq, {weekdays, priority}) {
          if (title.isNotEmpty)
            _addHabit(title, tags, color, freq, weekdays, time);
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
                              size: 48,
                              color: Colors.grey.withValues(alpha: 0.5)),
                          const SizedBox(height: 16),
                          Text("No rituals yet.\nDiscipline starts now.",
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                  color: Colors.grey, fontSize: 16)),
                          const SizedBox(height: 30),
                          Icon(CupertinoIcons.arrow_down,
                                  color: Colors.grey.withValues(alpha: 0.3))
                              .animate(
                                  onPlay: (controller) =>
                                      controller.repeat(reverse: true))
                              .moveY(
                                  begin: -5.0, end: 5.0, duration: 1.seconds),
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
                          onTap: () => _showHabitDetails(index),
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
      {super.key,
      required this.task,
      required this.onToggle,
      required this.onTap,
      required this.onDelete,
      this.isHabit = false,
      this.extraInfo});

  @override
  Widget build(BuildContext context) {
    final colorVal = task['color'] ?? Colors.white.value;
    final bgColor = getCardColor(context, colorVal);
    final bool isDarkBg =
        ThemeData.estimateBrightnessForColor(bgColor) == Brightness.dark;
    final Color contentColor = isDarkBg ? Colors.white : Colors.black;

    final int priority = task['priority'] ?? 0;
    Color priorityColor = Colors.transparent;
    if (priority == 1) priorityColor = Colors.blue;
    if (priority == 2) priorityColor = Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration:
          BoxDecoration(borderRadius: BorderRadius.circular(24), boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4))
      ]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Dismissible(
          key: Key(task['id'].toString()),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            color: Colors.red.shade400,
            child: const Icon(CupertinoIcons.delete, color: Colors.white),
          ),
          onDismissed: (_) => onDelete(),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              color: bgColor,
              child: Row(children: [
                if (priority > 0 && !task['isDone'])
                  Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                              color: priorityColor, shape: BoxShape.circle))),
                GestureDetector(
                    onTap: onToggle,
                    child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 24,
                        height: 24,
                        decoration: ShapeDecoration(
                            color: task['isDone']
                                ? contentColor
                                : Colors.transparent,
                            shape: ContinuousRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                    color: contentColor, width: 1.5))),
                        child: task['isDone']
                            ? Icon(Icons.check,
                                size: 16,
                                color: isDarkBg ? Colors.black : Colors.white)
                            : null)),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: task['isDone'] ? 0.4 : 1.0,
                          child: Text(task['title'],
                              style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: contentColor,
                                  decoration: task['isDone']
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationColor: contentColor))),
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
                                          color: Colors.grey
                                              .withValues(alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(4)),
                                      child: Text("🔥 ${task['streak'] ?? 0}",
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: contentColor))),
                                if (extraInfo != null && extraInfo!.isNotEmpty)
                                  Text("↻ $extraInfo",
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: contentColor.withValues(
                                              alpha: 0.6),
                                          fontWeight: FontWeight.w600)),
                                if (task['time'] != null && !task['isDone'])
                                  Text("⏰ ${task['time']}",
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: contentColor.withValues(
                                              alpha: 0.6))),
                                if (task['tags'] != null &&
                                    task['tags'].toString().isNotEmpty)
                                  Text("#${task['tags']}",
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: contentColor.withValues(
                                              alpha: 0.6),
                                          fontWeight: FontWeight.bold)),
                              ])),
                    ])),
              ]),
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.2, end: 0.0, curve: Curves.easeOutQuad);
  }
}

class TaskDetailSheet extends StatefulWidget {
  final String initialTitle;
  final String initialTags;
  final int initialColor;
  final String? initialTime;
  final int initialFrequency;
  final int initialPriority;
  final String initialRepeatType;
  final List<int> initialWeekdays;
  final bool isHabit;
  final bool isNew;
  final Function(String, String, int, String?, int,
      {List<int>? weekdays, int? priority}) onSave;
  final VoidCallback? onDelete;

  const TaskDetailSheet(
      {super.key,
      required this.initialTitle,
      required this.initialTags,
      required this.initialColor,
      this.initialTime,
      required this.initialFrequency,
      this.initialPriority = 0,
      this.initialRepeatType = 'interval',
      this.initialWeekdays = const [],
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
  late int _selectedPriority;
  String? _selectedTime;
  late String _repeatType;
  late List<int> _selectedWeekdays;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _tagsController = TextEditingController(text: widget.initialTags);
    _selectedColor = widget.initialColor;
    _selectedTime = widget.initialTime;
    _selectedFrequency = widget.initialFrequency;
    _selectedPriority = widget.initialPriority;
    _repeatType = widget.initialRepeatType;
    _selectedWeekdays = List<int>.from(widget.initialWeekdays);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.95)
        : Colors.white.withValues(alpha: 0.95);
    final textC = isDark ? Colors.white : Colors.black;

    final Color selectedThumbColor = isDark ? Colors.white : Colors.black;
    final Color unselectedTextColor = isDark ? Colors.white : Colors.black;
    final Color selectedTextColor = isDark ? Colors.black : Colors.white;

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
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
                          fontSize: 10,
                          letterSpacing: 1.5,
                          color: Colors.grey)),
                  TextField(
                      controller: _titleController,
                      autofocus: widget.isNew,
                      textInputAction: TextInputAction.done,
                      style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: textC),
                      decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText:
                              widget.isNew ? "What needs to be done?" : null,
                          hintStyle: const TextStyle(color: Colors.grey))),
                  const SizedBox(height: 20),
                  if (!widget.isHabit) ...[
                    Text("PRIORITY",
                        style: GoogleFonts.inter(
                            fontSize: 10,
                            letterSpacing: 1.5,
                            color: Colors.grey)),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoSegmentedControl<int>(
                        groupValue: _selectedPriority,
                        borderColor: isDark ? Colors.grey[700] : Colors.black,
                        selectedColor: selectedThumbColor,
                        unselectedColor: Colors.transparent,
                        pressedColor:
                            isDark ? Colors.grey[800] : Colors.grey[200],
                        children: {
                          0: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text("Low",
                                  style: TextStyle(
                                      color: _selectedPriority == 0
                                          ? selectedTextColor
                                          : unselectedTextColor))),
                          1: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text("Medium",
                                  style: TextStyle(
                                      color: _selectedPriority == 1
                                          ? selectedTextColor
                                          : unselectedTextColor))),
                          2: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text("High",
                                  style: TextStyle(
                                      color: _selectedPriority == 2
                                          ? selectedTextColor
                                          : unselectedTextColor))),
                        },
                        onValueChanged: (val) {
                          setState(() => _selectedPriority = val);
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
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
                              children: {
                                'interval': Text("Every X Days",
                                    style: TextStyle(
                                        color: _repeatType == 'interval'
                                            ? selectedTextColor
                                            : unselectedTextColor)),
                                'weekdays': Text("Weekdays",
                                    style: TextStyle(
                                        color: _repeatType == 'weekdays'
                                            ? selectedTextColor
                                            : unselectedTextColor))
                              },
                              onValueChanged: (val) {
                                setState(() => _repeatType = val!);
                              },
                              thumbColor: selectedThumbColor)
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
                              onSelectedItemChanged: (index) => setState(
                                  () => _selectedFrequency = index + 1),
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
                                        color: isSelected
                                            ? textC
                                            : Colors.transparent,
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
                          fontSize: 10,
                          letterSpacing: 1.5,
                          color: Colors.grey)),
                  TextField(
                      controller: _tagsController,
                      textInputAction: TextInputAction.done,
                      style: GoogleFonts.inter(fontSize: 16, color: textC),
                      decoration: const InputDecoration(
                          hintText: "e.g. Work, Gym",
                          border: InputBorder.none,
                          hintStyle: TextStyle(color: Colors.grey))),
                  const SizedBox(height: 20),
                  Text("COLOR",
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          letterSpacing: 1.5,
                          color: Colors.grey)),
                  const SizedBox(height: 10),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: kTaskColors
                          .map((c) => GestureDetector(
                              onTap: () =>
                                  setState(() => _selectedColor = c.value),
                              child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                      color: c,
                                      shape: BoxShape.circle,
                                      border:
                                          Border.all(color: Colors.grey[300]!),
                                      boxShadow: _selectedColor == c.value
                                          ? [
                                              BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.2),
                                                  blurRadius: 6)
                                            ]
                                          : []),
                                  child: _selectedColor == c.value
                                      ? Icon(Icons.check,
                                          size: 16,
                                          color: ThemeData
                                                      .estimateBrightnessForColor(
                                                          c) ==
                                                  Brightness.light
                                              ? Colors.black
                                              : Colors.white)
                                      : null)))
                          .toList()),
                  const SizedBox(height: 20),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("TIME (Optional)",
                            style: GoogleFonts.inter(
                                fontSize: 10,
                                letterSpacing: 1.5,
                                color: Colors.grey)),
                        GestureDetector(
                            onTap: () async {
                              final t = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.now());
                              if (t != null)
                                setState(() => _selectedTime =
                                    "${t.hour}:${t.minute.toString().padLeft(2, '0')}");
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
                            onPressed: () =>
                                setState(() => _selectedTime = null),
                            child: const Text("Clear",
                                style: TextStyle(
                                    color: Colors.red, fontSize: 12)))),
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
                                      : null,
                                  priority: _selectedPriority);
                              Navigator.pop(context);
                            }
                          },
                          child: Text(widget.isNew ? "Create" : "Save Changes",
                              style: TextStyle(
                                  color:
                                      isDark ? Colors.black : Colors.white)))),
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
        ),
      ),
    );
  }
}
