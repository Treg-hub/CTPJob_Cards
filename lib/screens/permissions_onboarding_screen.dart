import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/permissions_provider.dart';
import 'home_screen.dart';

class PermissionsOnboardingScreen extends ConsumerStatefulWidget {
  const PermissionsOnboardingScreen({super.key});

  @override
  ConsumerState<PermissionsOnboardingScreen> createState() => _PermissionsOnboardingScreenState();
}

class _PermissionsOnboardingScreenState extends ConsumerState<PermissionsOnboardingScreen> {
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _checkAndAutoAdvance();
  }

  Future<void> _checkAndAutoAdvance() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool('permissionsCompleted') ?? false;

    if (completed) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    }
  }

  Future<void> _completeOnboarding() async {
    setState(() => _isProcessing = true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permissionsCompleted', true);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final permissionsAsync = ref.watch(permissionsProvider);
    final requiredItems = ref.watch(requiredPermissionsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        title: const Text('Welcome to CTP Job Cards', style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            const Icon(Icons.security, size: 64, color: Color(0xFFFF8C42)),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Just a few quick permissions to unlock the full power of Job Cards',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: Colors.white70),
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'We only ask for what we truly need. You can change these anytime in your device settings.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.white54),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: permissionsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFFF8C42))),
                error: (err, _) => Center(child: Text('Error loading permissions: $err', style: const TextStyle(color: Colors.red))),
                data: (statusMap) {
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: requiredItems.length,
                    itemBuilder: (context, index) {
                      final item = requiredItems[index];
                      final currentStatus = statusMap[item.permission] ?? PermissionStatus.denied;
                      final isGranted = currentStatus.isGranted;

                      return Card(
                        color: const Color(0xFF1E1E1E),
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(item.icon, color: const Color(0xFFFF8C42), size: 28),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      item.title,
                                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ),
                                  if (isGranted)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Text('✓ Granted', style: TextStyle(color: Colors.green, fontSize: 12)),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(item.description, style: const TextStyle(color: Colors.white70, fontSize: 15)),
                              const SizedBox(height: 6),
                              Text(
                                'Why we need this: ${item.whyNeeded}',
                                style: const TextStyle(color: Colors.white54, fontSize: 13, fontStyle: FontStyle.italic),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: isGranted || _isProcessing
                                      ? null
                                      : () async {
                                          await ref.read(permissionsProvider.notifier).requestPermission(item.permission);
                                        },
                                  icon: Icon(isGranted ? Icons.check : Icons.lock_open),
                                  label: Text(isGranted ? 'Access Granted' : 'Grant Access'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isGranted ? Colors.green : const Color(0xFFFF8C42),
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isProcessing ? null : _completeOnboarding,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8C42),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isProcessing
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Text('Continue to Dashboard', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _completeOnboarding,
                    child: const Text('Skip for now (some features limited)', style: TextStyle(color: Colors.white54)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}