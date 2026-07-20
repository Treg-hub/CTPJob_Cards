import 'dart:io';

import 'package:flutter/material.dart';
import '../utils/persona_audit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart' show currentEmployee;
import '../providers/security_provider.dart';
import '../services/security_receipt_ocr_service.dart';
import '../services/security_service.dart';
import '../theme/app_theme.dart';
import '../utils/role.dart' as role_utils;
import '../utils/screen_insets.dart';
import '../utils/security_error_messages.dart';

/// Manager/admin vehicle cost entry — server-validated via the
/// addSecurityVehicleCost Cloud Function. Same entry point + data model as
/// CTP Pulse's Costing hub; either surface can be used interchangeably.
///
/// Receipt scan: on-device OCR prefills amount/date/description/category;
/// the same photo is uploaded to Storage on Save (`receipt_photo_url`).
class SecurityAddCostScreen extends ConsumerStatefulWidget {
  const SecurityAddCostScreen({super.key});

  @override
  ConsumerState<SecurityAddCostScreen> createState() =>
      _SecurityAddCostScreenState();
}

class _SecurityAddCostScreenState extends ConsumerState<SecurityAddCostScreen> {
  final _service = SecurityService();
  final _ocr = SecurityReceiptOcrService();
  final _descCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String? _selectedReg;
  String? _category;
  DateTime _costDate = DateTime.now();
  String? _receiptLocalPath;
  bool _submitting = false;
  bool _ocrBusy = false;
  String? _ocrHint;

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    _ocr.close();
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

  Future<void> _pickReceiptPhotoOnly() async {
    final source = await _pickImageSource();
    if (source == null || !mounted) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _receiptLocalPath = picked.path;
      _ocrHint = 'Receipt photo attached (not scanned)';
    });
  }

  Future<void> _scanReceipt(List<String> categories) async {
    final source = await _pickImageSource();
    if (source == null || !mounted) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;

    setState(() {
      _receiptLocalPath = picked.path;
      _ocrBusy = true;
      _ocrHint = null;
    });

    try {
      final result = await _ocr.parseImageFile(
        picked.path,
        categories: categories,
      );
      if (!mounted) return;

      setState(() {
        if (result.amountZar != null) {
          _amountCtrl.text = result.amountZar!.toStringAsFixed(2);
        }
        if (result.costDate != null) {
          _costDate = result.costDate!;
        }
        if (result.description != null && result.description!.isNotEmpty) {
          _descCtrl.text = result.description!;
        }
        if (result.suggestedCategory != null) {
          _category = result.suggestedCategory;
        }
        if (result.amountZar != null) {
          _ocrHint =
              'Fields filled from receipt — check amount and date before save. '
              'Photo will be stored with this cost.';
        } else if (result.hasUsableFields) {
          _ocrHint =
              'Some fields filled — enter amount manually. '
              'Photo will be stored with this cost.';
        } else {
          _ocrHint =
              'Couldn’t read fields — enter manually. '
              'Photo will still be saved with this cost.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ocrHint =
            'Couldn’t read receipt — enter details manually. '
            'Photo will still be saved with this cost.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlySecurityError(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _ocrBusy = false);
    }
  }

  Future<ImageSource?> _pickImageSource() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  void _clearReceipt() {
    setState(() {
      _receiptLocalPath = null;
      _ocrHint = null;
    });
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
          // ── Receipt scan (primary) ─────────────────────────────────────
          Text(
            'Receipt',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: (_submitting || _ocrBusy)
                ? null
                : () => _scanReceipt(categories),
            icon: _ocrBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.document_scanner_outlined),
            label: Text(_ocrBusy ? 'Reading receipt…' : 'Scan receipt'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: (_submitting || _ocrBusy) ? null : _pickReceiptPhotoOnly,
            icon: const Icon(Icons.camera_alt_outlined),
            label: Text(
              _receiptLocalPath == null
                  ? 'Attach photo only (no scan)'
                  : 'Replace photo (no scan)',
            ),
          ),
          if (_receiptLocalPath != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(_receiptLocalPath!),
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 72,
                      height: 72,
                      color: Colors.grey.shade300,
                      child: const Icon(Icons.receipt_long),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Receipt will be saved with this cost',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      if (_ocrHint != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _ocrHint!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade700,
                              ),
                        ),
                      ],
                      TextButton(
                        onPressed: _submitting ? null : _clearReceipt,
                        child: const Text('Remove photo'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

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
        ],
      ),
      bottomNavigationBar: SafeBottomBar(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: (_submitting || _ocrBusy)
              ? null
              : () => _submit(categories),
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
