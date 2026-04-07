import 'package:flutter/material.dart';
import '../services/firestore_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final TextEditingController deptController = TextEditingController();
  final TextEditingController areaController = TextEditingController();
  final TextEditingController machineController = TextEditingController();

  String? selectedDeptForArea;
  String? selectedDeptForMachine;
  String? selectedAreaForMachine;

  final FirestoreService _firestoreService = FirestoreService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin - Manage Structure')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            const Text('Add New Department', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            TextField(
              controller: deptController,
              decoration: const InputDecoration(labelText: 'Department name'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (deptController.text.isEmpty) return;

                try {
                  final structure = await _firestoreService.getFactoryStructure();
                  structure[deptController.text] = {};
                  await _firestoreService.updateFactoryStructure(structure);

                  deptController.clear();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Department added')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error adding department: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Add Department'),
            ),
            const Divider(height: 40),
            const Text('Add New Area', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            FutureBuilder<Map<String, dynamic>>(
              future: _firestoreService.getFactoryStructure(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const CircularProgressIndicator();
                final data = snapshot.data!;
                return Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedDeptForArea,
                      hint: const Text('Select Department'),
                      items: data.keys.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                      onChanged: (v) => setState(() => selectedDeptForArea = v),
                    ),
                    TextField(
                      controller: areaController,
                      decoration: const InputDecoration(labelText: 'Area name'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        if (selectedDeptForArea == null || areaController.text.isEmpty) return;

                        try {
                          final structure = await _firestoreService.getFactoryStructure();
                          (structure[selectedDeptForArea] as Map<String, dynamic>)[areaController.text] = [];
                          await _firestoreService.updateFactoryStructure(structure);

                          areaController.clear();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Area added')),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error adding area: $e'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                      child: const Text('Add Area'),
                    ),
                  ],
                );
              },
            ),
            const Divider(height: 40),
            const Text('Add New Machine / Part', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            FutureBuilder<Map<String, dynamic>>(
              future: _firestoreService.getFactoryStructure(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const CircularProgressIndicator();
                final data = snapshot.data!;
                return Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedDeptForMachine,
                      hint: const Text('Select Department'),
                      items: data.keys.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                      onChanged: (v) => setState(() {
                        selectedDeptForMachine = v;
                        selectedAreaForMachine = null;
                      }),
                    ),
                    if (selectedDeptForMachine != null)
                      DropdownButtonFormField<String>(
                        value: selectedAreaForMachine,
                        hint: const Text('Select Area'),
                        items: (data[selectedDeptForMachine] as Map<String, dynamic>).keys
                            .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                            .toList(),
                        onChanged: (v) => setState(() => selectedAreaForMachine = v),
                      ),
                    TextField(
                      controller: machineController,
                      decoration: const InputDecoration(labelText: 'Machine / Part name'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        if (selectedDeptForMachine == null || selectedAreaForMachine == null || machineController.text.isEmpty) return;

                        try {
                          final structure = await _firestoreService.getFactoryStructure();
                          (structure[selectedDeptForMachine]![selectedAreaForMachine] as List<dynamic>).add(machineController.text);
                          await _firestoreService.updateFactoryStructure(structure);

                          machineController.clear();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Machine added')),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error adding machine: $e'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                      child: const Text('Add Machine / Part'),
                    ),
                  ],
                );
              },
            ),
            const Divider(height: 40),
            const Text('Password Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              onPressed: () => _showPasswordChangeDialog(context),
              icon: const Icon(Icons.security),
              label: const Text('Change Switch User Password'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            ),
          ],
        ),
      ),
    );
  }

  void _showPasswordChangeDialog(BuildContext context) {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Switch User Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentPasswordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current Password', hintText: '••••••'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New Password', hintText: '••••••'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm Password', hintText: '••••••'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final currentPassword = currentPasswordController.text.trim();
              final newPassword = newPasswordController.text.trim();
              final confirmPassword = confirmPasswordController.text.trim();

              if (currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All fields required'), backgroundColor: Colors.red),
                );
                return;
              }
              if (newPassword != confirmPassword) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('New passwords do not match'), backgroundColor: Colors.red),
                );
                return;
              }

              try {
                final storedPassword = await _firestoreService.getSwitchUserPassword();

                if (currentPassword != storedPassword) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Current password incorrect'), backgroundColor: Colors.red),
                    );
                  }
                  return;
                }

                await _firestoreService.updateSwitchUserPassword(newPassword);

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ Password changed successfully'), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Update Password'),
          ),
        ],
      ),
    );
  }
}