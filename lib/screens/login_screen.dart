import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee.dart';
import '../main.dart' show currentEmployee;
import '../services/notification_service.dart';
import 'registration_screen.dart';
import 'permissions_onboarding_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isForgotPasswordLoading = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();
      final permissionsCompleted = prefs.getBool('permissionsCompleted') ?? false;

      if (!mounted) return;
      if (currentEmployee != null && !permissionsCompleted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PermissionsOnboardingScreen()),
        );
      }
    });
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter email and password'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final credential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      final uid = credential.user!.uid;

      final query = await FirebaseFirestore.instance
          .collection('employees')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No employee profile found. Please register first.'), backgroundColor: Colors.orange),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      final empData = query.docs.first.data();
      final employee = Employee(
        clockNo: empData['clockNo'] ?? '',
        name: empData['name'] ?? '',
        position: empData['position'] ?? '',
        department: empData['department'] ?? '',
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('loggedInName', employee.name);
      await prefs.setString('loggedInClockNo', employee.clockNo);
      currentEmployee = employee;

      await FirebaseCrashlytics.instance.setUserIdentifier(employee.clockNo);

      if (!kIsWeb) {
        try {
          await FirebaseMessaging.instance.requestPermission();
          await NotificationService()
              .refreshAndSaveToken(employee.clockNo)
              .timeout(const Duration(seconds: 5));
        } catch (e, st) {
          FirebaseCrashlytics.instance
              .recordError(e, st, reason: 'fcm_register_at_login');
        }
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PermissionsOnboardingScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'user-not-found':
          msg = 'No account found with this email';
          break;
        case 'wrong-password':
        case 'invalid-credential':
          msg = 'Incorrect password';
          break;
        case 'invalid-email':
          msg = "That email address isn't valid";
          break;
        case 'too-many-requests':
          msg = 'Too many attempts. Try again in a few minutes';
          break;
        case 'network-request-failed':
          msg = 'No internet — check your connection';
          break;
        default:
          msg = e.message ?? 'Login failed';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email first'), backgroundColor: Colors.orange),
      );
      return;
    }

    final emailRegex = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
    if (!emailRegex.hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isForgotPasswordLoading = true);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Password reset email sent to $email. Check your spam folder if you don't see it within a minute.",
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } on FirebaseAuthException catch (e, st) {
      String msg;
      switch (e.code) {
        case 'user-not-found':
          msg = 'No account found with this email';
          break;
        case 'invalid-email':
          msg = "That email address isn't valid";
          break;
        case 'too-many-requests':
          msg = 'Too many attempts. Try again in a few minutes';
          break;
        case 'network-request-failed':
          msg = 'No internet — check your connection';
          break;
        default:
          msg = e.message ?? 'Failed to send reset email';
      }
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'password_reset_failed',
        information: ['domain:${email.split('@').last}'],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
      }
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'password_reset_failed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isForgotPasswordLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: screenWidth * 0.6,
                child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
              ),
              const SizedBox(height: 24),
              Text('CTP Job Cards', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
              const SizedBox(height: 8),
              Text('Welcome back', style: TextStyle(fontSize: 18, color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 48),

              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                ),
              ),
              const SizedBox(height: 8),

              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isForgotPasswordLoading ? null : _forgotPassword,
                  child: _isForgotPasswordLoading
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF8C42)),
                        )
                      : const Text(
                          'Forgot Password?',
                          style: TextStyle(color: Color(0xFFFF8C42), fontSize: 14),
                        ),
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8C42),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Text('Login', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
                ),
              ),
              const SizedBox(height: 24),

              TextButton(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const RegistrationScreen()));
                },
                child: const Text(
                  "Don't have an account? Register",
                  style: TextStyle(color: Color(0xFFFF8C42), fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}