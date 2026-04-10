import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'models/employee.dart';
import 'screens/login_screen.dart';
import 'services/connectivity_service.dart';
import 'services/firestore_service.dart';

// ==================== BACKGROUND HANDLER (mobile only) ====================
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('Background message received: ${message.messageId}');
  // Message will be displayed automatically by FCM
}

Employee? currentEmployee;

// ==================== APP ====================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  final firestoreService = FirestoreService();

  // Initialize settings if not exist
  await firestoreService.initializeSettings();

  // If logged in, restore employee from storage
  final prefs = await SharedPreferences.getInstance();
  final hasLogin = prefs.containsKey('loggedInClockNo');
  if (hasLogin) {
    final clockNo = prefs.getString('loggedInClockNo');
    if (clockNo != null) {
      currentEmployee = await firestoreService.getEmployee(clockNo);
    }
  }

  runApp(MultiProvider(
    providers: [
      Provider<ConnectivityService>(create: (_) => ConnectivityService()),
    ],
    child: CtpJobCardsApp(isLoggedIn: hasLogin),
  ));
}

class CtpJobCardsApp extends StatelessWidget {
  final bool isLoggedIn;
  const CtpJobCardsApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CTP Job Cards',
      theme: ThemeData(
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
      ),
      home: const LoginScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
