import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee.dart';
import '../main.dart' show realEmployee;
import '../services/notification_service.dart';
import '../services/auth_claims_service.dart';
import '../services/client_platform_service.dart';
import '../services/firestore_service.dart';
import 'home_screen.dart';
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
      if (realEmployee != null && !permissionsCompleted) {
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

      var query = await FirebaseFirestore.instance
          .collection('employees')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();

      // Fallback: admin-created accounts and reinstall-recovery users may have
      // an employee doc that doesn't yet carry their auth uid. Match by email
      // and self-heal the doc with the current uid so the next login takes the
      // fast path above.
      if (query.docs.isEmpty) {
        final emailQuery = await FirebaseFirestore.instance
            .collection('employees')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();

        if (emailQuery.docs.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No employee profile found. Please register first.'), backgroundColor: Colors.orange),
            );
          }
          setState(() => _isLoading = false);
          return;
        }

        try {
          // employees is locked under Wave B — link uid via the CF, not a
          // direct write. (Doc id == clockNo.)
          await FirestoreService().linkMyAccount(emailQuery.docs.first.id, email: email);
        } catch (e, st) {
          if (!kIsWeb) {
            FirebaseCrashlytics.instance.recordError(e, st, reason: 'login_uid_self_heal_failed');
          }
          // Non-fatal — continue with the employee data we already have.
          // The user can still log in this session; next time they'll fall
          // through to this branch again until the rules / data are fixed.
        }
        query = emailQuery;
      }

      final empData = query.docs.first.data();
      final employee = Employee(
        clockNo: empData['clockNo'] ?? '',
        name: empData['name'] ?? '',
        position: empData['position'] ?? '',
        department: empData['department'] ?? '',
        isAdmin: empData['isAdmin'] as bool? ?? false,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('loggedInName', employee.name);
      await prefs.setString('loggedInClockNo', employee.clockNo);
      await prefs.setString('loggedInPosition', employee.position);
      await prefs.setString('loggedInDepartment', employee.department);
      await prefs.setBool('loggedInAdmin', employee.isAdmin);
      realEmployee = employee;

      if (!kIsWeb) await FirebaseCrashlytics.instance.setUserIdentifier(employee.clockNo);

      // Mint/refresh server-derived custom claims FIRST (role, department,
      // clockNum, isAdmin from the locked admins/{uid} registry). The presence
      // CF used by the FCM-token save below needs the clockNum claim, and admin
      // config writes need isAdmin. Non-fatal — never blocks login.
        await AuthClaimsService.refreshClaims();

      ClientPlatformService().syncToFirestore();

      if (!kIsWeb) {
        // Do not request notification permission here — it fires during the
        // permissions onboarding screen after the user has read the explanation.
        // Saving the FCM token is safe without the permission on Android.
        try {
          await NotificationService()
              .refreshAndSaveToken(employee.clockNo)
              .timeout(const Duration(seconds: 5));
        } catch (e, st) {
          FirebaseCrashlytics.instance
              .recordError(e, st, reason: 'fcm_register_at_login');
        }
      }

      if (mounted) {
        final onboardingDone =
            prefs.getBool('permissionsCompleted') ?? false;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) {
              if (kIsWeb || onboardingDone) return const HomeScreen();
              return const PermissionsOnboardingScreen();
            },
          ),
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
      if (!kIsWeb) {
        FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'password_reset_failed',
        information: ['domain:${email.split('@').last}'],
      );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
      }
    } catch (e, st) {
      if (!kIsWeb) FirebaseCrashlytics.instance.recordError(e, st, reason: 'password_reset_failed');
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
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 800) {
                return _buildWideLayout(colorScheme);
              }
              return _buildNarrowLayout(colorScheme);
            },
          ),
          IgnorePointer(child: _buildPerimeterGlow()),
        ],
      ),
    );
  }

  Widget _buildPerimeterGlow() {
    const glow = Color(0xFFFF8C42);
    const extent = 160.0;
    const opacity = 0.45;
    gradient(Alignment from, Alignment to) => BoxDecoration(
          gradient: LinearGradient(
            begin: from,
            end: to,
            colors: [glow.withValues(alpha: opacity), Colors.transparent],
          ),
        );
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(top: 0, left: 0, right: 0, height: extent,
            child: DecoratedBox(decoration: gradient(Alignment.topCenter, Alignment.bottomCenter))),
        Positioned(bottom: 0, left: 0, right: 0, height: extent,
            child: DecoratedBox(decoration: gradient(Alignment.bottomCenter, Alignment.topCenter))),
        Positioned(top: 0, bottom: 0, left: 0, width: extent,
            child: DecoratedBox(decoration: gradient(Alignment.centerLeft, Alignment.centerRight))),
        Positioned(top: 0, bottom: 0, right: 0, width: extent,
            child: DecoratedBox(decoration: gradient(Alignment.centerRight, Alignment.centerLeft))),
      ],
    );
  }

  Widget _buildWideLayout(ColorScheme colorScheme) {
    return Row(
      children: [
        // Left branding panel
        Expanded(
          child: Container(
            color: Colors.black,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/images/logo.png', width: 260, fit: BoxFit.contain),
                    const SizedBox(height: 32),
                    const Text(
                      'CTP Job Cards',
                      style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Orange accent divider
        Container(width: 4, color: const Color(0xFFFF8C42)),
        // Right login panel
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Welcome back',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sign in to your account',
                      style: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 40),
                    _buildFormFields(colorScheme),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(ColorScheme colorScheme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/logo.png', width: 180, fit: BoxFit.contain),
            const SizedBox(height: 20),
            Text('CTP Job Cards', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
            const SizedBox(height: 6),
            Text('Welcome back', style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 40),
            _buildFormFields(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildFormFields(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _isForgotPasswordLoading ? null : _forgotPassword,
            child: _isForgotPasswordLoading
                ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF8C42)))
                : const Text('Forgot Password?', style: TextStyle(color: Color(0xFFFF8C42), fontSize: 14)),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
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
        const SizedBox(height: 20),
        TextButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegistrationScreen())),
          child: const Text("Don't have an account? Register", style: TextStyle(color: Color(0xFFFF8C42), fontSize: 16)),
        ),
      ],
    );
  }
}