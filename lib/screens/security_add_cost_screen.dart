import 'package:flutter/material.dart';
import '../utils/persona_audit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart' show currentEmployee;
import '../providers/security_provider.dart';
import '../services/security_service.dart';
import '../theme/app_theme.dart';
import '../utils/role.dart' as role_utils;
import '../utils/screen_insets.dart';
import '../utils/security_error_messages.dart';

/// Manager/admin vehicle cost entry — server-validated via the
/// addSecurityVehicleCost Cloud Function. Same entry point + data model as
/// CTP Pulse's Costing hub; either surface can be used interchangeably.
class SecurityAddCostScreen extends ConsumerStatefulWidget {
  const SecurityAddCostScreen({super.key});

  @override
  ConsumerState<SecurityAddCostScreen> createState() =>
      _SecurityAddCostScreenState();
}

class _SecurityAddCostScreenState extends ConsumerState<SecurityAddCostScreen> {
  final _service = SecurityService();
  final _descCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String? _selectedReg;
  String? _category;
  DateTime _costDate = DateTime.now();
  String? _receiptLocalPath;
  bool _submitting = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _costDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _costDate = picked);
  }

  Future<void> _pickReceiptPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (picked != null) setState(() => _receiptLocalPath = picked.path);
  }

  Future<void> _submit(List<String> categories) async {
    if (!guardPersonaSubmit(context)) return;
    final emp = currentEmployee;
    if (emp == null) return;

    final reg = (_selectedReg ?? '').trim();
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (reg.isEmpty) {
      _showError('Select a company car.');
      return;
    }
    if (amount == null || amount <= 0) {
      _showError('Enter a valid amount.');
      return;
    }
    if (_category == null) {
      _showError('Select a cost category.');
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      _showError('Description is required.');
      return;
    }

    setState(() => _submitting = true);
    try {
      await _service.addVehicleCost(
        vehicleReg: reg,
        costDate: _costDate,
        category: _category!,
        description: _descCtrl.text.trim(),
        amountZar: amount,
        enteredByClockNo: resolveWriteActor(emp)!.clockNo,
        receiptLocalPath: _receiptLocalPath,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cost recorded'),
          backgroundColor: kBrandOrange,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      _showError(friendlySecurityError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(securitySettingsProvider).valueOrNull;
    final canManage =
        role_utils.isSecurityCostManager(currentEmployee, settings);

    if (settings != null && !canManage) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add Company Car Cost')),
        body: const Center(
          child: Text('Manager or admin access required.'),
        ),
      );
    }

    final categories = settings?.costTypeSuggestions ?? [];
    final vehiclesAsync = ref.watch(securityVehiclesProvider);
    final companyCars = vehiclesAsync.valueOrNull
            ?.where((v) => v.isCompanyCar)
            .toList() ??
        [];

    return Scaffold(
      appBar: AppBar(title: const Text('Add Company Car Cost')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (companyCars.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'No company cars registered. Add them in Pulse Settings.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            DropdownButtonFormField<String>(
              key: ValueKey(_selectedReg),
              initialValue: _selectedReg,
              decoration: const InputDecoration(
                labelText: 'Company car *',
                border: OutlineInputBorder(),
              ),
              items: companyCars
                  .map(
                    (v) => DropdownMenuItem(
                      value: v.vehicleReg,
                      child: Text(
                        v.assignedDriver != null && v.assignedDriver!.isNotEmpty
                            ? '${v.vehicleReg} · ${v.assignedDriver}'
                            : v.vehicleReg,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _selectedReg = v),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(_category),
            initialValue: _category,
            decoration: const InputDecoration(
              labelText: 'Category *',
              border: OutlineInputBorder(),
            ),
            items: categories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(
              labelText: 'Description *',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            decoration: const InputDecoration(
              labelText: 'Amount (ZAR) *',
              border: OutlineInputBorder(),
              prefixText: 'R ',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cost date'),
            subtitle: Text(
              '${_costDate.day}/${_costDate.month}/${_costDate.year}',
            ),
            trailing: const Icon(Icons.calendar_today),
            onTap: _pickDate,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickReceiptPhoto,
            icon: const Icon(Icons.camera_alt_outlined),
            label: Text(
              _receiptLocalPath == null
                  ? 'Add receipt photo (optional)'
                  : 'Receipt photo attached',
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeBottomBar(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: _submitting ? null : () => _submit(categories),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: kBrandOrange,
          ),
          child: _submitting
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save cost'),
        ),
      ),
    );
  }
}
