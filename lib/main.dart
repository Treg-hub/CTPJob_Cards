import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'firebase_options.dart';
import 'models/employee.dart';
import 'providers/theme_provider.dart';
import 'providers/copper_provider.dart';   // ← now Riverpod
import 'screens/login_screen.dart';
import 'services/connectivity_service.dart';
import 'services/firestore_service.dart';
import 'theme/app_theme.dart';

Employee? currentEmployee;

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('Background message received: ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);

  // ←←← CRASHLYTICS SETUP
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  final firestoreService = FirestoreService();
  await firestoreService.initializeSettings();

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
          titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Colors.black87),
          titleMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: Color(0xFFFF8C42)),
          bodyLarge: TextStyle(fontSize: 18, color: Colors.black87),
          bodyMedium: TextStyle(fontSize: 17, color: Colors.black54),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: const Color(0xFFFF8C42),
            foregroundColor: Colors.white,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey[100],
          labelStyle: const TextStyle(color: Color(0xFFFF8C42)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.grey),
          ),
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
          onPrimary: Color.fromARGB(255, 0, 0, 0),
          secondary: Color(0xFF1A1A1A),
          surface: Color(0xFF0F0F0F),
          outline: Color(0xFF333333),
        ),
        scaffoldBackgroundColor: const Color(0xFF000000),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFF8C42),
          foregroundColor: Color.fromARGB(255, 0, 0, 0),
          elevation: 0,
          titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.black),
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Colors.white),
          titleMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: Color(0xFFFF8C42)),
          bodyLarge: TextStyle(fontSize: 18, color: Colors.white),
          bodyMedium: TextStyle(fontSize: 17, color: Colors.white70),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: const Color(0xFFFF8C42),
            foregroundColor: Colors.black,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1A1A1A),
          labelStyle: const TextStyle(color: Color(0xFFFF8C42)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF333333)),
          ),
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