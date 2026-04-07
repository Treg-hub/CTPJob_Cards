import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee.dart';
import '../services/firestore_service.dart';
import 'home_screen.dart';

Employee? currentEmployee;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _clockNoController = TextEditingController();
  bool _isLoading = false;
  final FirestoreService _firestoreService = FirestoreService();

  Future<void> _login() async {
    final clockNo = _clockNoController.text.trim();
    if (clockNo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your clock card number'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final empDoc = await FirebaseFirestore.instance.collection('employees').doc(clockNo).get();
      final empData = empDoc.data();
      if (empData == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load employee data'), backgroundColor: Colors.red),
        );
        return;
      }
      final employee = Employee(
        clockNo: empData['clockNo'] as String? ?? '',
        name: empData['name'] as String? ?? '',
        position: empData['position'] as String? ?? '',
        department: empData['department'] as String? ?? '',
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('loggedInClockNo', clockNo);
      currentEmployee = employee;
      if (!kIsWeb) {
        await _saveFcmToken(clockNo);
      }
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
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
    _clockNoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.business, size: 80, color: Color(0xFFFF8C42)),
                const SizedBox(height: 24),
                const Text('CTP Job Cards', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 8),
                const Text('Welcome', style: TextStyle(fontSize: 18, color: Colors.white70)),
                const SizedBox(height: 48),
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
        ),
      ),
    );
  }
}