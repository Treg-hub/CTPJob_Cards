import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
import 'package:permission_handler/permission_handler.dart';

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

  String? clockNo = prefs.getString('loggedInClockNo');

  // Fallback: SharedPreferences was cleared (e.g. reinstall) but Firebase Auth session survived
  if (clockNo == null && !kIsWeb) {
    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        final query = await FirebaseFirestore.instance
            .collection('employees')
            .where('uid', isEqualTo: firebaseUser.uid)
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) {
          clockNo = query.docs.first.data()['clockNo'] as String?;
          if (clockNo != null) {
            await prefs.setString('loggedInClockNo', clockNo);
            debugPrint('✅ Session restored from Firebase Auth for $clockNo');
          }
        }
      }
    } catch (e) {
      debugPrint('Firebase Auth session restore failed: $e');
    }
  }

  if (clockNo != null) {
    try {
      currentEmployee = await firestoreService.getEmployee(clockNo);

      if (currentEmployee != null) {
        if (!kIsWeb) {
          NotificationService().refreshAndSaveToken(clockNo).catchError((_) {});
        }

        final permissionsCompleted = prefs.getBool('permissionsCompleted') ?? false;

        final locationGranted = kIsWeb ? true : (await Permission.locationAlways.status).isGranted;
        if ((!permissionsCompleted || !locationGranted) && !kIsWeb) {
          initialScreen = const PermissionsOnboardingScreen();
        } else {
          initialScreen = const HomeScreen();
        }

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
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: kBrandOrange,
          onPrimary: Colors.black,
          secondary: Color(0xFFF0F0F0),
          onSecondary: Colors.black87,
          surface: Colors.white,
          onSurface: Colors.black87,
          onSurfaceVariant: Colors.black54,
          surfaceContainer: Color(0xFFF5F5F5),
          surfaceContainerHighest: Color(0xFFEEEEEE),
          outline: Color(0xFFBDBDBD),
          outlineVariant: Color(0xFFE0E0E0),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        appBarTheme: const AppBarTheme(
          backgroundColor: kBrandOrange,
          foregroundColor: Colors.black,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.black),
          titleTextStyle: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.w500),
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: kBrandOrange,
          unselectedItemColor: Colors.grey,
          elevation: 8,
          type: BottomNavigationBarType.fixed,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF0F0F0),
          labelStyle: const TextStyle(color: kBrandOrange),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFBDBDBD)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFBDBDBD)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: kBrandOrange, width: 2),
          ),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black54,
          indicatorColor: Colors.black,
          labelStyle: TextStyle(fontWeight: FontWeight.bold),
        ),
        switchTheme: const SwitchThemeData(
          thumbColor: WidgetStatePropertyAll(kBrandOrange),
        ),
        chipTheme: ChipThemeData(
          labelStyle: const TextStyle(color: Colors.black87),
          selectedColor: kBrandOrange.withValues(alpha: 51),
        ),
        extensions: const [lightAppColors],
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: kBrandOrange,
          onPrimary: Colors.black,
          secondary: Color(0xFF1A1A1A),
          onSecondary: Colors.white,
          surface: Color(0xFF1A1A1A),
          onSurface: Colors.white,
          onSurfaceVariant: Colors.white70,
          surfaceContainer: Color(0xFF0F0F0F),
          surfaceContainerHighest: Color(0xFF252525),
          outline: Color(0xFF333333),
          outlineVariant: Color(0xFF2A2A2A),
        ),
        scaffoldBackgroundColor: const Color(0xFF000000),
        appBarTheme: const AppBarTheme(
          backgroundColor: kBrandOrange,
          foregroundColor: Colors.black,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.black),
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF1A1A1A),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1A1A1A),
          selectedItemColor: kBrandOrange,
          unselectedItemColor: Colors.grey,
          elevation: 8,
          type: BottomNavigationBarType.fixed,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1A1A1A),
          labelStyle: const TextStyle(color: kBrandOrange),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF333333)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF333333)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: kBrandOrange, width: 2),
          ),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: kBrandOrange,
          unselectedLabelColor: Colors.white70,
          indicatorColor: kBrandOrange,
        ),
        switchTheme: const SwitchThemeData(
          thumbColor: WidgetStatePropertyAll(kBrandOrange),
        ),
        chipTheme: ChipThemeData(
          labelStyle: const TextStyle(color: Colors.white),
          selectedColor: kBrandOrange.withValues(alpha: 51),
        ),
        extensions: const [darkAppColors],
      ),
      home: initialScreen,
      debugShowCheckedModeBanner: false,
    );
  }
}