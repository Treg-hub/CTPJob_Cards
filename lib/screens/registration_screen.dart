import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee.dart';
import '../main.dart' show realEmployee;
import '../services/auth_claims_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import 'permissions_onboarding_screen.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _clockNoController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _register() async {
    final clockNo = _clockNoController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();

    if (clockNo.isEmpty || email.isEmpty || password.isEmpty || confirm.isEmpty) {
      _showSnack('Please fill all fields', Colors.red);
      return;
    }
    if (password != confirm) {
      _showSnack('Passwords do not match', Colors.red);
      return;
    }
    if (password.length < 6) {
      _showSnack('Password must be at least 6 characters', Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Create Firebase Auth account (signs the user in)
      UserCredential credential;
      try {
        credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
      } on FirebaseAuthException catch (e) {
        if (e.code != 'email-already-in-use') rethrow;
        // Self-heal: the auth account already exists — typically a previous
        // registration attempt that failed AFTER account creation (e.g. the
        // link call lost connectivity). Sign in with the provided credentials
        // and resume the same linking flow instead of dead-ending.
        try {
          credential = await FirebaseAuth.instance
              .signInWithEmailAndPassword(email: email, password: password);
        } on FirebaseAuthException catch (signInError) {
          if (signInError.code == 'wrong-password' ||
              signInError.code == 'invalid-credential') {
            _showSnack(
                'This email is already registered. Enter its password to finish '
                'setup, or go to Login and use Forgot Password.',
                Colors.orange);
            return;
          }
          rethrow;
        }
      }

      await _completeRegistration(credential.user!, clockNo, email);
    } on FirebaseAuthException catch (e) {
      String msg = 'Registration failed';
      if (e.code == 'weak-password') msg = 'Password is too weak';
      if (e.code == 'network-request-failed') {
        msg = 'No internet — check your connection';
      }
      _showSnack(msg, Colors.red);
    } catch (e) {
      _showSnack('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Post-auth registration flow, shared by the create-account path and the
  /// email-already-in-use sign-in fallback.
  Future<void> _completeRegistration(
      User user, String clockNo, String email) async {
    // Ensure the ID token is cached before the rules-gated employees query.
    // Replaces the old fixed 2 s "wait for auth to propagate" delay —
    // createUserWithEmailAndPassword returns an already-signed-in user.
    await user.getIdToken();

    final empQuery = await FirebaseFirestore.instance
        .collection('employees')
        .where('clockNo', isEqualTo: clockNo)
        .limit(1)
        .get();

    if (empQuery.docs.isEmpty) {
      _showSnack('No employee found with that clock card number', Colors.red);
      return;
    }

    final empData = empQuery.docs.first.data();

    // Link this auth account to the employee doc via the CF. employees is
    // locked under Wave B, so the client can no longer write uid directly;
    // the CF also refuses to claim a clock number already linked elsewhere.
    try {
      await FirestoreService().linkMyAccount(clockNo, email: email);
    } catch (e, st) {
      if (!kIsWeb) {
        FirebaseCrashlytics.instance
            .recordError(e, st, reason: 'registration_link_failed');
      }
      final msg = _linkFailureMessage(e);
      _showSnack(msg, Colors.orange);
      return;
    }

    final employee = Employee(
      clockNo: clockNo,
      name: empData['name'] ?? '',
      position: empData['position'] ?? '',
      department: empData['department'] ?? '',
      isAdmin: empData['isAdmin'] as bool? ?? false,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('loggedInName', employee.name);
    await prefs.setString('loggedInClockNo', clockNo);
    await prefs.setString('loggedInPosition', employee.position);
    await prefs.setString('loggedInDepartment', employee.department);
    await prefs.setBool('loggedInAdmin', employee.isAdmin);
    realEmployee = employee;

    if (!kIsWeb) {
      await FirebaseCrashlytics.instance.setUserIdentifier(clockNo);
    }

    // Mint custom claims AFTER the uid link (the CF derives clockNum from
    // it) — mirrors the login path. Without this a fresh registrant reached
    // Home with NO claims: inbox reads denied, and the presence CF rejected
    // the FCM token save below. Non-fatal, has its own 8 s timeout.
    await AuthClaimsService.refreshClaims(force: true);

    // Phase 9: session admin flag from claim (AuthClaimsService also updates prefs).
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdTokenResult();
      final claims = token?.claims;
      if (claims != null && claims.containsKey('isAdmin')) {
        final claimAdmin = claims['isAdmin'] == true;
        await prefs.setBool('loggedInAdmin', claimAdmin);
        if (realEmployee != null && realEmployee!.isAdmin != claimAdmin) {
          realEmployee = realEmployee!.copyWith(isAdmin: claimAdmin);
        }
      }
    } catch (_) {
      /* best-effort */
    }

    if (!kIsWeb) {
      try {
        await NotificationService()
            .refreshAndSaveToken(clockNo)
            .timeout(const Duration(seconds: 5));
      } catch (e, st) {
        FirebaseCrashlytics.instance
            .recordError(e, st, reason: 'fcm_register_at_registration');
      }
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PermissionsOnboardingScreen()),
      );
      _showSnack('Account created successfully!', Colors.green);
    }
  }

  /// Maps Phase-1 linkEmployeeAccount errors to user-facing copy.
  String _linkFailureMessage(Object e) {
    if (e is FirebaseFunctionsException) {
      final details = (e.message ?? '').toLowerCase();
      if (details.contains('email does not match') ||
          details.contains('company email')) {
        return 'Use the company email registered for this clock number, '
            'or ask an admin for help.';
      }
      if (details.contains('locked for registration')) {
        return 'This clock number is locked for registration — ask an admin.';
      }
      if (details.contains('already linked')) {
        return 'This clock number is already linked to another account.';
      }
      if (e.code == 'not-found') {
        return 'No employee found with that clock card number.';
      }
      if (e.message != null && e.message!.isNotEmpty) {
        return e.message!;
      }
    }
    return 'Account created but not yet linked — check your connection and '
        'tap Create Account again to retry.';
  }

  void _showSnack(String message, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: color),
      );
    }
  }

  @override
  void dispose() {
    _clockNoController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Create Account'),
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Text(
                'Register for CTP Job Cards',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 32),

              TextField(
                controller: _clockNoController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Clock Card Number',
                  labelStyle: const TextStyle(color: Color(0xFFFF8C42)),
                  filled: true,
                  fillColor: const Color(0xFF1A1A1A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  labelStyle: const TextStyle(color: Color(0xFFFF8C42)),
                  filled: true,
                  fillColor: const Color(0xFF1A1A1A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: const TextStyle(color: Color(0xFFFF8C42)),
                  filled: true,
                  fillColor: const Color(0xFF1A1A1A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  labelStyle: const TextStyle(color: Color(0xFFFF8C42)),
                  filled: true,
                  fillColor: const Color(0xFF1A1A1A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8C42),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.black)
                      : const Text('Create Account', style: TextStyle(fontSize: 18, color: Colors.black)),
                ),
              ),
              const SizedBox(height: 16),

              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Already have an account? Login', style: TextStyle(color: Color(0xFFFF8C42))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}