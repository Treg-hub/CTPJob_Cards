import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee.dart';
import '../main.dart' show currentEmployee;
import '../services/location_service.dart';
import '../services/update_service.dart';
import 'home_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameController = TextEditingController();
  final _clockNoController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (currentEmployee != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
      });
    }
  }

  Future _login() async {
    final name = _nameController.text.trim();
    final clockNo = _clockNoController.text.trim();
    if (name.isEmpty || clockNo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name and clock card number'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final query = FirebaseFirestore.instance.collection('employees').where('name', isEqualTo: name).where('clockNo', isEqualTo: clockNo).limit(1);
      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid name or clock card number'), backgroundColor: Colors.red),
        );
        return;
      }
      final empData = snapshot.docs.first.data();
      final employee = Employee(
        clockNo: empData['clockNo'] as String? ?? '',
        name: empData['name'] as String? ?? '',
        position: empData['position'] as String? ?? '',
        department: empData['department'] as String? ?? '',
      );

      // === IMPROVED Custom Token Auth (Option B) - africa-south1 ===
      debugPrint('🔄 Starting custom token login for clockNo: $clockNo');
      final functions = FirebaseFunctions.instanceFor(region: 'africa-south1');
      final callable = functions.httpsCallable('createCustomToken');
      debugPrint('📡 Calling createCustomToken in africa-south1 with data: $clockNo');

      final result = await callable.call({'clockNo': clockNo});
      final customToken = result.data['customToken'] as String;
      debugPrint('✅ Custom token received from africa-south1');

      await FirebaseAuth.instance.signInWithCustomToken(customToken);
      debugPrint('✅ Signed in with custom token - UID: ${FirebaseAuth.instance.currentUser?.uid}');

      // Wait for auth state to fully propagate
      await Future.delayed(const Duration(milliseconds: 800));
      if (FirebaseAuth.instance.currentUser == null) {
        throw Exception('Auth state did not propagate');
      }
      // ==========================================

       final prefs = await SharedPreferences.getInstance();
       await prefs.setString('loggedInName', name);
       await prefs.setString('loggedInClockNo', clockNo);
       currentEmployee = employee;

        // Start automatic on-site detection (mobile only)
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          try {
            await LocationService().startNativeMonitoring(clockNo);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to start location monitoring: $e')),
              );
            }
          }
        } else if (kIsWeb) {
          debugPrint('📍 Geofencing skipped on web platform');
        }

         // Update check moved to app startup in main.dart

       if (mounted) {
         Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
       }
      // Save FCM token asynchronously after navigation
      if (!kIsWeb) {
        _saveFcmToken(clockNo);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveFcmToken(String clockNo) async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        debugPrint('⚠️ Notification permissions denied');
        return;
      }
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await FirebaseFirestore.instance.collection('employees').doc(clockNo).set({
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('✅ FCM Token saved successfully for $clockNo');
      }
    } catch (e) {
      debugPrint('❌ Error saving FCM token: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _clockNoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    double titleWidth;
    if (isMobile) {
      titleWidth = screenWidth - 48;
    } else {
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'CTP Job Cards',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      titleWidth = textPainter.width;
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
               children: [
                  SizedBox(
                    width: kIsWeb ? titleWidth * 1.8 : screenWidth * 0.95,
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: kIsWeb ? BoxFit.contain : BoxFit.fitWidth,
                    ),
                  ),
                 const SizedBox(height: 24),
                const Text('CTP Job Cards', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 8),
                const Text('Welcome', style: TextStyle(fontSize: 18, color: Colors.white70)),
                const SizedBox(height: 48),
                SizedBox(
                  width: kIsWeb ? titleWidth * 1.4 : titleWidth,
                  child: Column(
                    children: [
                      TextField(
                        controller: _nameController,
                        keyboardType: TextInputType.text,
                        decoration: InputDecoration(
                          labelText: 'Name',
                          hintText: 'Enter your name',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          filled: true,
                          fillColor: const Color(0xFF1A1A1A),
                          labelStyle: const TextStyle(color: Color(0xFFFF8C42)),
                        ),
                        style: const TextStyle(color: Colors.white),
                        enabled: !_isLoading,
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _clockNoController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Clock Card Number',
                          hintText: 'Enter your clock card number',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          filled: true,
                          fillColor: const Color(0xFF1A1A1A),
                          labelStyle: const TextStyle(color: Color(0xFFFF8C42)),
                        ),
                        style: const TextStyle(color: Colors.white),
                        enabled: !_isLoading,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: const Color(0xFFFF8C42),
                            disabledBackgroundColor: Colors.grey,
                          ),
                          child: _isLoading
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.black)))
                              : const Text('Login', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('This device will be limited to your account', style: TextStyle(fontSize: 14, color: Colors.white70), textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}