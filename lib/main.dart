import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb, kDebugMode, FlutterError, PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'models/employee.dart';
import 'models/sync_queue_item.dart';
import 'providers/theme_provider.dart';
import 'screens/login_screen.dart';
import 'services/firestore_service.dart';
import 'services/sync_service.dart';
import 'services/background_geofence_service.dart';
import 'services/job_alert_service.dart';
import 'services/update_service.dart';
import 'theme/app_theme.dart';

Employee? currentEmployee;

// ==================== GLOBAL NAVIGATOR KEY ====================
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ==================== NOTIFICATION ACTION HANDLER ====================
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _handleNotificationAction(NotificationResponse response) async {
  final String? payload = response.payload;
  final String? actionId = response.actionId;

  if (payload == null) return;

  final jobCardNumber = payload;

  // Navigate using global navigator key
  navigatorKey.currentState?.pushNamedAndRemoveUntil(
    '/',
    (route) => false,
    arguments: {
      'jobCardNumber': jobCardNumber,
      'action': actionId ?? 'view_job',
    },
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  Hive.registerAdapter(SyncQueueItemAdapter());

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize background geofence service only on mobile (Android/iOS)
  if (!kIsWeb) {
    await BackgroundGeofenceService.initializeService();
  }

  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);

  // ==================== INITIALIZE LOCAL NOTIFICATIONS ====================
  await flutterLocalNotificationsPlugin.initialize(
    settings: InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: _handleNotificationAction,
  );

  final firestoreService = FirestoreService();
  await firestoreService.initializeSettings();

  await Hive.openBox<SyncQueueItem>('syncQueue');
  await SyncService().init();

  final prefs = await SharedPreferences.getInstance();
  final hasLogin = prefs.containsKey('loggedInClockNo');
  if (hasLogin) {
    final clockNo = prefs.getString('loggedInClockNo');
    if (clockNo != null) {
      currentEmployee = await firestoreService.getEmployee(clockNo);
    }
  }

  runApp(
    const ProviderScope(
      child: CtpJobCardsApp(),
    ),
  );
}

class CtpJobCardsApp extends ConsumerWidget {
  const CtpJobCardsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeNotifierProvider);

    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await UpdateService().checkForUpdate(context);
        } catch (e) {
          debugPrint('Error checking for updates on startup: $e');
        }
      });
    }

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'CTP Job Cards',
      themeMode: themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.light(
          primary: Color(0xFFFF8C42),
          onPrimary: Colors.white,
          secondary: Color(0xFFE0E0E0),
          surface: Colors.white,
          outline: Color(0xFFBDBDBD),
        ),
        scaffoldBackgroundColor: Colors.grey[50],
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFF8C42),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        extensions: const [
          AppColors(
            priority1: Color(0xFF4CAF50),
            priority2: Color(0xFF8BC34A),
            priority3: Color(0xFFFFC107),
            priority4: Color(0xFFFF9800),
            priority5: Color(0xFFFF3D00),
            statusOpen: Colors.blue,
            statusInProgress: Colors.orange,
            statusCompleted: Colors.green,
            statusCancelled: Colors.red,
          ),
        ],
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF8C42),
          onPrimary: Colors.black,
          secondary: Color(0xFF1A1A1A),
          surface: Color(0xFF0F0F0F),
          outline: Color(0xFF333333),
        ),
        scaffoldBackgroundColor: const Color(0xFF000000),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFF8C42),
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        extensions: const [
          AppColors(
            priority1: Color(0xFF4CAF50),
            priority2: Color(0xFF8BC34A),
            priority3: Color(0xFFFFC107),
            priority4: Color(0xFFFF9800),
            priority5: Color(0xFFFF3D00),
            statusOpen: Colors.blue,
            statusInProgress: Colors.orange,
            statusCompleted: Colors.green,
            statusCancelled: Colors.red,
          ),
        ],
      ),
      home: const LoginScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}