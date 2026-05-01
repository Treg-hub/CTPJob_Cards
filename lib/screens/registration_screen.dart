import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee.dart';
import '../main.dart' show currentEmployee;
import 'home_screen.dart';

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
      // 1. Create Firebase Auth account
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      // 2. IMPORTANT: Wait for auth to fully propagate
      await Future.delayed(const Duration(milliseconds: 2000));

      // 3. Now query the employee document
      final empQuery = await FirebaseFirestore.instance
          .collection('employees')
          .where('clockNo', isEqualTo: clockNo)
          .limit(1)
          .get();

      if (empQuery.docs.isEmpty) {
        _showSnack('No employee found with that clock card number', Colors.red);
        setState(() => _isLoading = false);
        return;
      }

      final empDoc = empQuery.docs.first;
      final empData = empDoc.data();

      // 4. Update the employee document with uid + email
      await FirebaseFirestore.instance
          .collection('employees')
          .doc(clockNo)
          .set({
        'uid': credential.user!.uid,
        'email': email,
        'registeredAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));   // ← This is safer

      // 5. Create Employee object and save
      final employee = Employee(
        clockNo: clockNo,
        name: empData['name'] ?? '',
        position: empData['position'] ?? '',
        department: empData['department'] ?? '',
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('loggedInUid', credential.user!.uid);
      await prefs.setString('loggedInName', employee.name);
      await prefs.setString('loggedInClockNo', clockNo);
      currentEmployee = employee;

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
        _showSnack('Account created successfully!', Colors.green);
      }
    } on FirebaseAuthException catch (e) {
      String msg = 'Registration failed';
      if (e.code == 'email-already-in-use') msg = 'Email already in use';
      if (e.code == 'weak-password') msg = 'Password is too weak';
      _showSnack(msg, Colors.red);
    } catch (e) {
      _showSnack('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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