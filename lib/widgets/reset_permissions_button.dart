import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/permissions_onboarding_screen.dart';

class ResetPermissionsButton extends StatelessWidget {
  const ResetPermissionsButton({super.key});

  Future<void> _resetAndShowOnboarding(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permissionsCompleted', false);

    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PermissionsOnboardingScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.refresh, color: Color(0xFFFF8C42)),
      title: const Text(
        'Reset Permissions Onboarding',
        style: TextStyle(color: Colors.white),
      ),
      subtitle: const Text(
        'Show the permissions screen again (for testing)',
        style: TextStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white54),
      onTap: () => _resetAndShowOnboarding(context),
    );
  }
}