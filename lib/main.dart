import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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

import 'services/firestore_service.dart';
import 'services/sync_service.dart';


Employee? currentEmployee;

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('Background message received: ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  // Register Hive adapters
  Hive.registerAdapter(SyncQueueItemAdapter());

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Enable Crashlytics
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);

  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  final firestoreService = FirestoreService();
  await firestoreService.initializeSettings();

  // Initialize Sync Queue + SyncService
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

    return MaterialApp(
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
      ),
      home: const LoginScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}