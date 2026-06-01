import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../services/waste_service.dart';
import '../models/contractor.dart';
import '../models/waste_type.dart';
import '../main.dart' show currentEmployee;

/// Manager-facing screen: schedule an upcoming waste load before the truck arrives.
/// Creates a [WasteLoad] with status [scheduled] — no driver, items, or photos needed yet.
/// The guard will complete the load when the contractor arrives at the gate.
class WasteScheduleLoadScreen extends ConsumerStatefulWidget {
  const WasteScheduleLoadScreen({super.key});

  @override
  ConsumerState<WasteScheduleLoadScreen> createState() =>
      _WasteScheduleLoadScreenState();
}

class _WasteScheduleLoadScreenState
    extends ConsumerState<WasteScheduleLoadScreen> {
  final WasteService _wasteService = WasteService();
  final _notesController = TextEditingController();

  List<Contractor> _contractors = [];
  List<WasteType> _wasteTypes = [];
  Contractor? _selectedContractor;
  WasteType? _selectedType;
  DateTime _scheduledFor = DateTime.now();
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    const timeout = Duration(seconds: 10);
    try {
      final contractors = await _wasteService
          .watchContractors()
          .first
          .timeout(timeout, onTimeout: () => []);
      final types = await _wasteService
          .watchWasteTypes()
          .first
          .timeout(timeout, onTimeout: () => []);
      if (mounted) {
        setState(() {
          _contractors = contractors;
          _wasteTypes = types;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load data — check connection')),
        );
      }
    }
  }

  bool get _isValid =>
      _selectedContractor != null &&
      _selectedType != null;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledFor,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null && mounted) {
      final pickedTime = await showTimePicker(
        context: context, // ignore: use_build_context_synchronously
        initialTime: TimeOfDay.fromDateTime(_scheduledFor),
      );
      setState(() {
        _scheduledFor = DateTime(
          picked.year, picked.month, picked.day,
          pickedTime?.hour ?? _scheduledFor.hour,
          pickedTime?.minute ?? _scheduledFor.minute,
        );
      });
    }
  }

  Future<void> _save() async {
    if (!_isValid || _isSaving) return;
    setState(() => _isSaving = true);

    final employee = currentEmployee;
    try {
      await _wasteService.createScheduledLoad(
        contractorId: _selectedContractor!.id!,
        mainWasteType: _selectedType!.mainType,
        scheduledFor: _scheduledFor,
        scheduledBy: employee?.clockNo ?? '',
        scheduledByName: employee?.name ?? '',
        scheduledNotes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Load scheduled — guard will be notified via the app'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to schedule load: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule Incoming Load'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton(
              onPressed: _isValid ? _save : null,
              child: const Text('Save'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_contractors.isEmpty || _wasteTypes.isEmpty)
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.settings_suggest, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text('Setup Required', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      _contractors.isEmpty && _wasteTypes.isEmpty
                          ? 'No contractors or waste types have been added yet.\nAsk an admin to set these up in Waste Admin.'
                          : _contractors.isEmpty
                              ? 'No contractors have been added yet.\nAsk an admin to add them in Waste Admin.'
                              : 'No waste types have been added yet.\nAsk an admin to add them in Waste Admin.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: _loadData,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Info banner ──────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withAlpha(77),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withAlpha(77),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: Theme.of(context).colorScheme.primary, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'The guard will see this load when the contractor arrives and will add driver details, items, photos and signature.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Contractor ───────────────────────────────
                  Text('Contractor *', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<Contractor>(
                    value: _selectedContractor,
                    hint: const Text('Select contractor'),
                    isExpanded: true,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: _contractors.map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(c.name),
                    )).toList(),
                    onChanged: (c) => setState(() => _selectedContractor = c),
                  ),

                  const SizedBox(height: 20),

                  // ── Waste type ───────────────────────────────
                  Text('Main Waste Type *', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _wasteTypes.map((type) {
                      final selected = _selectedType?.mainType == type.mainType;
                      return ChoiceChip(
                        label: Text(type.mainType),
                        selected: selected,
                        onSelected: (_) => setState(() => _selectedType = type),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 20),

                  // ── Expected date/time ───────────────────────
                  Text('Expected Date & Time *', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(4),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        DateFormat('EEE d MMM yyyy, HH:mm').format(_scheduledFor),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Notes ────────────────────────────────────
                  Text('Notes (optional)', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'e.g. Approx 500 kg, heavy vehicle, use rear gate',
                    ),
                  ),

                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isValid && !_isSaving ? _save : null,
                      child: _isSaving
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Schedule Load'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
