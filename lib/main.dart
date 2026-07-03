import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb, FlutterError, PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'firebase_options.dart';
import 'models/employee.dart';
import 'models/sync_queue_item.dart';
import 'providers/theme_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/permissions_onboarding_screen.dart';
import 'screens/update_required_screen.dart';
import 'services/firestore_service.dart';
import 'services/notification_service.dart';
import 'services/auth_claims_service.dart';
import 'services/sync_service.dart';
import 'theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'services/client_platform_service.dart';
import 'services/device_health_service.dart';
import 'services/kiosk_mode_service.dart';
import 'services/location_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'widgets/kiosk_lifecycle_guard.dart';

/// Logged-in employee (never replaced by UI persona).
Employee? realEmployee;

/// UI-only persona overlay for admin role testing (in-memory; cleared on restart).
Employee? personaEmployee;

/// When persona is active, whether Firestore writes are allowed (with audit stamping).
bool personaAllowTestSubmissions = false;

/// Effective identity for UI gating — persona when active, otherwise [realEmployee].
Employee? get currentEmployee => personaEmployee ?? realEmployee;

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Tracks the name of the topmost route so notification deep links can avoid
/// pushing a duplicate JobCardDetailScreen for the job already on screen.
class TopRouteTracker extends NavigatorObserver {
  static String? topRouteName;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    topRouteName = route.settings.name;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    topRouteName = previousRoute?.settings.name;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    topRouteName = newRoute?.settings.name;
  }
}

/// Returns true for async errors that are recoverable noise rather than real
/// crashes (see PlatformDispatcher.onError below). The app keeps running, so
/// these are recorded as non-fatal to keep the Crashlytics crash dashboard
/// meaningful:
///   • Firestore permission-denied — a snapshot listener still attached across
///     sign-out; the resilient wrapper (services/resilient_stream.dart)
///     re-subscribes it after a claims/token refresh or on re-login.
///   • PlatformException(channel-error) — a Firestore/plugin platform call that
///     lost its channel during early startup or teardown.
bool _isRecoverableAsyncError(Object error) {
  if (error is FirebaseException && error.code == 'permission-denied') {
    return true;
  }
  if (error is PlatformException &&
      (error.code == 'channel-error' ||
          (error.message?.contains('Unable to establish connection on channel') ??
              false))) {
    return true;
  }
  return false;
}

/// True once Firebase init succeeded, so startup breadcrumbs can safely reach
/// Crashlytics (calls before initializeApp would throw on native platforms).
bool _crashlyticsReady = false;

/// Startup breadcrumb: debug console always; Crashlytics log fire-and-forget.
/// Lets a "opened the app and nothing appeared" report show exactly which
/// startup path was taken (cache/network/stub employee, kill-switch, screen).
void _crumb(String message) {
  debugPrint('🚀 startup: $message');
  if (!kIsWeb && _crashlyticsReady) {
    unawaited(FirebaseCrashlytics.instance.log('startup: $message'));
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-edge on modern Android/iOS — all screens must respect safe areas.
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

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
    // Settings are separated from the isEmpty guard: background services (FCM,
    // WorkManager, geofencing) may have pre-initialised Firebase without starting
    // Firestore. We always try to set settings, catching the "already started"
    // exception if a background service beat us to it.
    if (!kIsWeb) {
      try {
        FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
      } catch (_) {
        // Firestore already started by a background isolate — existing settings apply.
      }
    }
    if (!kIsWeb) {
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterError;
      PlatformDispatcher.instance.onError = (error, stack) {
        // We return true (error handled, app keeps running), so only record as
        // a fatal crash when it isn't recoverable async noise. See
        // _isRecoverableAsyncError for the two reclassified cases.
        FirebaseCrashlytics.instance
            .recordError(error, stack, fatal: !_isRecoverableAsyncError(error));
        return true;
      };
    }
    _crashlyticsReady = !kIsWeb;
    _crumb('firebase-ok');
  } catch (e) {
    debugPrint('Firebase warning: $e');
  }

  // ==================== VERSION KILL-SWITCH ====================
  // settings/app.minSupportedBuild retires old builds with a blocking screen
  // before login. Firestore-backed (works off the offline cache, unlike the
  // Remote Config force-update dialog, which only fires on HomeScreen with a
  // cooldown). Fails open: no doc / no field / fetch error → app continues.
  if (!kIsWeb) {
    try {
      // Capped: on a dead network this get() could previously hang the native
      // splash indefinitely. 4 s then fail open (kill-switch is best-effort).
      final settingsDoc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('app')
          .get()
          .timeout(const Duration(seconds: 4));
      final minBuild = settingsDoc.data()?['minSupportedBuild'];
      if (minBuild is num && minBuild > 0) {
        final info = await PackageInfo.fromPlatform();
        final currentBuild = int.tryParse(info.buildNumber) ?? 0;
        if (currentBuild > 0 && currentBuild < minBuild.toInt()) {
          final url = settingsDoc.data()?['updateDownloadUrl'] as String? ?? '';
          _crumb('killswitch-blocked build=$currentBuild min=$minBuild');
          KioskModeService.instance.reassertIfEnabled();
          runApp(KioskLifecycleGuard(child: UpdateRequiredScreen(downloadUrl: url)));
          return;
        }
      }
      _crumb('killswitch-passed');
    } catch (e) {
      _crumb('killswitch-skipped');
      debugPrint('minSupportedBuild check skipped: $e');
    }
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

  // NOTE: the old initializeSettings() call is gone — it re-read the same
  // settings/app doc the kill-switch just fetched and only debugPrinted.
  final firestoreService = FirestoreService();

  await SyncService().init();

  // ==================== DETERMINE INITIAL SCREEN + START LOCATION ====================
  Widget initialScreen;
  final prefs = await SharedPreferences.getInstance();

  String? clockNo = prefs.getString('loggedInClockNo');

  // Fallback: SharedPreferences was cleared (e.g. reinstall) but Firebase Auth session survived
  if (clockNo == null && !kIsWeb) {
    try {
      // currentUser can still be null while FirebaseAuth restores the session
      // from disk on a cold start — wait (capped) for the first auth event so
      // a surviving session isn't missed. Only runs when prefs are missing,
      // so the normal startup path never pays this wait.
      final firebaseUser = await FirebaseAuth.instance
          .authStateChanges()
          .first
          .timeout(const Duration(seconds: 2),
              onTimeout: () => FirebaseAuth.instance.currentUser);
      if (firebaseUser != null) {
        final query = await FirebaseFirestore.instance
            .collection('employees')
            .where('uid', isEqualTo: firebaseUser.uid)
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 5));
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
    bool employeeNotFound = false;
    String employeeSource = 'none';

    // Try Firestore offline cache first — fast and survives app updates without network
    try {
      final cachedDoc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(clockNo)
          .get(const GetOptions(source: Source.cache));
      if (cachedDoc.exists && cachedDoc.data() != null) {
        realEmployee = Employee.fromFirestore(cachedDoc.data()!, clockNo);
        employeeSource = 'cache';
        debugPrint('✅ Employee loaded from cache for $clockNo');
      }
    } catch (_) {
      // Cache miss — fall through to network
    }

    // Cache miss: try network (capped — a hung channel must not hold the splash)
    if (realEmployee == null) {
      try {
        final checked = await firestoreService
            .getEmployeeChecked(clockNo)
            .timeout(const Duration(seconds: 6));
        realEmployee = checked.employee;
        if (checked.employee != null) {
          employeeSource = 'network';
        } else if (checked.serverConfirmedAbsent) {
          // Only a SERVER-confirmed absence clears the session. A default
          // get() answered from cache while offline also reports
          // exists == false — that used to wrongly log the user out here.
          employeeNotFound = true;
          _crumb('employee-absent-server');
        }
      } catch (e) {
        // Network/transient failure — don't force logout, trust the saved session
        debugPrint('Employee fetch failed at startup (network?): $e');
      }
    }

    // Both cache and network failed transiently — build a stub from SharedPreferences
    // so HomeScreen always has a name to display while Firestore loads in the background.
    if (realEmployee == null && !employeeNotFound) {
      final name = prefs.getString('loggedInName') ?? '';
      final position = prefs.getString('loggedInPosition') ?? '';
      final department = prefs.getString('loggedInDepartment') ?? '';
      final adminFlag = prefs.getBool('loggedInAdmin') ?? false;
      if (name.isNotEmpty) {
        realEmployee = Employee(
          clockNo: clockNo,
          name: name,
          position: position,
          department: department,
          isAdmin: adminFlag,
        );
        employeeSource = 'stub';
        debugPrint('⚡ Employee stub built from SharedPreferences for $clockNo');
      }
    }
    _crumb('employee-$employeeSource');
    if (!kIsWeb && _crashlyticsReady) {
      unawaited(FirebaseCrashlytics.instance
          .setCustomKey('startup_employee_source', employeeSource));
      unawaited(FirebaseCrashlytics.instance.setCustomKey(
          'startup_auth_present', FirebaseAuth.instance.currentUser != null));
    }

    if (employeeNotFound) {
      // Account was explicitly confirmed missing — clear session
      await prefs.remove('loggedInClockNo');
      initialScreen = const LoginScreen();
    } else {
      // Employee loaded (or fetch failed transiently) — keep user logged in
      if (realEmployee != null) {
        if (!kIsWeb) await FirebaseCrashlytics.instance.setUserIdentifier(clockNo);
        if (!kIsWeb) {
          NotificationService().refreshAndSaveToken(clockNo).catchError((_) {});
        }
        // Claims (role/department/isAdmin/clockNum) are platform-agnostic and
        // gate Wave B reads/writes, so refresh on web too. Fire-and-forget;
        // never blocks startup.
        AuthClaimsService.refreshClaims();
      }

      final permissionsCompleted = prefs.getBool('permissionsCompleted') ?? false;
      final locationGranted =
          kIsWeb ? true : (await Permission.locationAlways.status).isGranted;

      if (!permissionsCompleted && !kIsWeb) {
        initialScreen = const PermissionsOnboardingScreen();
      } else {
        initialScreen = const HomeScreen();
      }

      if (kIsWeb || permissionsCompleted) {
        ClientPlatformService().syncToFirestore();
      }

      if (!kIsWeb && permissionsCompleted) {
        DeviceHealthService().syncPermissionsToFirestore();
        if (locationGranted) {
          try {
            await LocationService().startNativeMonitoring(clockNo);
            debugPrint('✅ Native monitoring started on auto-login');
          } catch (e) {
            debugPrint('Location monitoring error on auto-login: $e');
          }
          LocationService().checkCurrentLocation();
        }
      }
    }
  } else {
    initialScreen = const LoginScreen();
  }

  _crumb('screen-${initialScreen.runtimeType}');
  runApp(
    ProviderScope(
      child: KioskLifecycleGuard(
        child: CtpJobCardsApp(initialScreen: initialScreen),
      ),
    ),
  );
}

/// One consistent push/pop animation for every route. The framework default
/// on Android is the zoom+fade transition, which is heavier to render (visible
/// stutter on low-end tablets) and animates differently per platform. A single
/// Cupertino-style horizontal slide is lighter, uniform, and adds an
/// interactive edge-swipe back — so navigating (especially back) looks
/// deliberate instead of janky.
const PageTransitionsTheme _appPageTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: CupertinoPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
    TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
  },
);

class CtpJobCardsApp extends ConsumerWidget {
  final Widget initialScreen;

  const CtpJobCardsApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeNotifierProvider);

    return MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [TopRouteTracker()],
      title: 'CTP Job Cards',
      themeMode: themeMode,
      builder: (context, child) {
        // Preserve system insets so nested Scaffolds and scroll views can read them.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            padding: EdgeInsets.fromLTRB(
              mq.padding.left,
              mq.padding.top,
              mq.padding.right,
              mq.viewPadding.bottom > mq.padding.bottom
                  ? mq.viewPadding.bottom
                  : mq.padding.bottom,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: ThemeData(
        useMaterial3: true,
        pageTransitionsTheme: _appPageTransitions,
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
          labelPadding: EdgeInsets.symmetric(horizontal: 8),
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
        pageTransitionsTheme: _appPageTransitions,
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
          unselectedLabelColor: Colors.white54,
          indicatorColor: kBrandOrange,
          labelPadding: EdgeInsets.symmetric(horizontal: 8),
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