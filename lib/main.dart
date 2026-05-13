import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb, FlutterError, PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'models/employee.dart';
import 'models/sync_queue_item.dart';
import 'providers/theme_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/permissions_onboarding_screen.dart';
import 'services/firestore_service.dart';
import 'services/notification_service.dart';
import 'services/sync_service.dart';
import 'services/update_service.dart';
import 'theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'services/location_service.dart';

Employee? currentEmployee;

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  Hive.registerAdapter(SyncQueueItemAdapter());

  const String syncBoxName = 'sync_queue';
  try {
    if (Hive.isBoxOpen(syncBoxName)) {
      await Hive.box<SyncQueueItem>(syncBoxName).close();
    }
    await Hive.openBox<SyncQueueItem>(syncBoxName);
  } catch (e) {
    debugPrint('Hive error: $e');
    try { await Hive.deleteBoxFromDisk(syncBoxName); } catch (_) {}
    await Hive.openBox<SyncQueueItem>(syncBoxName);
  }

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: !kIsWeb);
  } catch (e) {
    debugPrint('Firebase warning: $e');
  }

  final notificationService = NotificationService();
  await notificationService.initialize();

  const MethodChannel globalAlertChannel = MethodChannel('job_alert_channel');

  globalAlertChannel.setMethodCallHandler((MethodCall call) async {
    if (call.method == 'handleAlertAction') {
      final String? actionId = call.arguments['actionId'];
      final String? payload = call.arguments['payload'];

      if (actionId != null && payload != null) {
        await notificationService.handleNotificationAction(NotificationResponse(
          actionId: actionId,
          payload: payload,
          notificationResponseType: NotificationResponseType.selectedNotificationAction,
        ));
      }
    }
  });

  final firestoreService = FirestoreService();
  try {
    await firestoreService.initializeSettings();
  } catch (e) {
    debugPrint('Settings warning: $e');
  }

  await SyncService().init();

  // ==================== DETERMINE INITIAL SCREEN + START LOCATION ====================
  Widget initialScreen;
  final prefs = await SharedPreferences.getInstance();
  final hasLogin = prefs.containsKey('loggedInClockNo');

  if (hasLogin) {
    final clockNo = prefs.getString('loggedInClockNo');
    if (clockNo != null) {
      try {
        currentEmployee = await firestoreService.getEmployee(clockNo);

        if (currentEmployee != null) {
          final permissionsCompleted = prefs.getBool('permissionsCompleted') ?? false;

          if (!permissionsCompleted && !kIsWeb) {
            initialScreen = const PermissionsOnboardingScreen();
          } else {
            initialScreen = const HomeScreen();
          }

          // === START NATIVE MONITORING ON AUTO-LOGIN ===
          if (!kIsWeb) {
            try {
              await LocationService().startNativeMonitoring(clockNo);
              debugPrint('✅ Native monitoring started on auto-login');
            } catch (e) {
              debugPrint('Location monitoring error on auto-login: $e');
            }
          }

          LocationService().checkCurrentLocation();
        } else {
          initialScreen = const LoginScreen();
        }
      } catch (e) {
        currentEmployee = null;
        initialScreen = const LoginScreen();
      }
    } else {
      initialScreen = const LoginScreen();
    }
  } else {
    initialScreen = const LoginScreen();
  }

  runApp(
    ProviderScope(
      child: CtpJobCardsApp(initialScreen: initialScreen),
    ),
  );
}

class CtpJobCardsApp extends ConsumerWidget {
  final Widget initialScreen;

  const CtpJobCardsApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeNotifierProvider);

    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await UpdateService().checkForUpdate(context);
        } catch (e) {
          debugPrint('Update check error: $e');
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
      home: initialScreen,
      debugShowCheckedModeBanner: false,
    );
  }
}