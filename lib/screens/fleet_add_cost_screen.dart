import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_asset.dart';
import '../models/fleet_cost_line.dart';
import '../models/fleet_work_record.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';

/// Cost entry form for fleet cost managers and admins.
class FleetAddCostScreen extends ConsumerStatefulWidget {
  final String? preSelectedAssetId;
  final String? preSelectedAssetName;
  final String? preSelectedWorkRecordId;
  final String? preSelectedWorkNumber;

  const FleetAddCostScreen({
    super.key,
    this.preSelectedAssetId,
    this.preSelectedAssetName,
    this.preSelectedWorkRecordId,
    this.preSelectedWorkNumber,
  });

  @override
  ConsumerState<FleetAddCostScreen> createState() => _FleetAddCostScreenState();
}

class _FleetAddCostScreenState extends ConsumerState<FleetAddCostScreen> {
  final _service = FleetService();
  final _descCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _invoiceRefCtrl = TextEditingController();
  final _supplierCtrl = TextEditingController();

  FleetCostCategory _category = FleetCostCategory.parts;
  DateTime _costDate = DateTime.now();
  bool _saving = false;

  FleetAsset? _selectedAsset;
  List<FleetAsset> _assets = [];
  FleetWorkRecord? _selectedWorkRecord;
  List<FleetWorkRecord> _workRecords = [];

  @override
  void initState() {
    super.initState();
    _loadAssets();
    if (widget.preSelectedAssetId != null) {
      _service.getAsset(widget.preSelectedAssetId!).then((a) {
        if (a != null && mounted) {
          setState(() => _selectedAsset = a);
          _loadWorkRecordsForAsset(a.id!);
        }
      });
    }
    if (widget.preSelectedWorkRecordId != null) {
      _service.getWorkRecord(widget.preSelectedWorkRecordId!).then((r) {
        if (r != null && mounted) setState(() => _selectedWorkRecord = r);
      });
    }
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    _invoiceRefCtrl.dispose();
    _supplierCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAssets() async {
    final assets = await _service.watchAssets().first;
    if (mounted) setState(() => _assets = assets);
  }

  Future<void> _loadWorkRecordsForAsset(String assetId) async {
    final records =
        await _service.watchWorkRecords(assetId: assetId).first;
    if (mounted) {
      setState(() {
        _workRecords = records;
        // If pre-selected work record belongs to this asset, keep it; otherwise clear.
        if (_selectedWorkRecord != null &&
            _selectedWorkRecord!.assetId != assetId) {
          _selectedWorkRecord = null;
        }
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _costDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) setState(() => _costDate = picked);
  }

  Future<void> _save() async {
    final emp = currentEmployee;
    if (emp == null) return;

    if (_selectedAsset == null) {
      _snack('Please select an asset.');
      return;
    }
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) {
      _snack('Please enter a description.');
      return;
    }
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      _snack('Please enter a valid amount (e.g. 1500.00).');
      return;
    }

    setState(() => _saving = true);
    try {
      final line = FleetCostLine(
        assetId: _selectedAsset!.id!,
        assetName: _selectedAsset!.name,
        workRecordId: _selectedWorkRecord?.id,
        workNumber: _selectedWorkRecord?.workNumber,
        category: _category,
        description: desc,
        amountZar: amount,
        invoiceRef: _invoiceRefCtrl.text.trim().isEmpty
            ? null
            : _invoiceRefCtrl.text.trim(),
        supplier: _supplierCtrl.text.trim().isEmpty
            ? null
            : _supplierCtrl.text.trim(),
        costDate: _costDate,
        enteredByClockNo: emp.clockNo,
        enteredByName: emp.name,
      );
      await _service.createCostLine(line);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Cost line saved.'),
              backgroundColor: Colors.green),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) _snack('Save failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg),
          backgroundColor: isError ? Colors.red : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Cost'),
        backgroundColor: kBrandOrange,
        foregroundColor: Colors.white,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)),
            )
          else
            TextButton(
              onPressed: _save,
              child:
                  const Text('Save', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Asset ─────────────────────────────────────────────────────
          _Label('Asset *'),
          DropdownButtonFormField<FleetAsset>(
            key: ValueKey(_selectedAsset?.id),
            initialValue: _selectedAsset,
            decoration:
                const InputDecoration(border: OutlineInputBorder()),
            hint: const Text('Select asset'),
            items: _assets
                .map((a) => DropdownMenuItem(
                      value: a,
                      child: Text(a.name),
                    ))
                .toList(),
            onChanged: (a) {
              setState(() {
                _selectedAsset = a;
                _selectedWorkRecord = null;
                _workRecords = [];
              });
              if (a != null) _loadWorkRecordsForAsset(a.id!);
            },
          ),
          const SizedBox(height: 16),

          // ── Work record (optional) ─────────────────────────────────────
          _Label('Work Record (optional)'),
          DropdownButtonFormField<FleetWorkRecord?>(
            key: ValueKey(_selectedWorkRecord?.id),
            initialValue: _selectedWorkRecord,
            decoration:
                const InputDecoration(border: OutlineInputBorder()),
            hint: const Text('Link to a work record (optional)'),
            items: [
              const DropdownMenuItem(value: null, child: Text('None')),
              ..._workRecords.map((r) => DropdownMenuItem(
                    value: r,
                    child: Text(
                        '${r.workNumber}  ${r.title.length > 25 ? r.title.substring(0, 25) : r.title}',
                        style: const TextStyle(fontSize: 13)),
                  )),
            ],
            onChanged: (r) =>
                setState(() => _selectedWorkRecord = r),
          ),
          const SizedBox(height: 16),

          // ── Category ──────────────────────────────────────────────────
          _Label('Category *'),
          Wrap(
            spacing: 8,
            children: FleetCostCategory.values.map((c) {
              return ChoiceChip(
                label: Text(c.displayLabel),
                selected: _category == c,
                selectedColor: kBrandOrange,
                labelStyle: TextStyle(
                    color: _category == c ? Colors.white : null),
                onSelected: (_) => setState(() => _category = c),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // ── Description ───────────────────────────────────────────────
          _Label('Description *'),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(
                hintText: 'e.g. Oil filter replacement',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),

          // ── Amount ────────────────────────────────────────────────────
          _Label('Amount (ZAR) *'),
          TextField(
            controller: _amountCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                prefixText: 'R ',
                hintText: '0.00',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),

          // ── Invoice ref + Supplier (side by side) ─────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label('Invoice Ref'),
                    TextField(
                      controller: _invoiceRefCtrl,
                      decoration: const InputDecoration(
                          hintText: 'optional',
                          border: OutlineInputBorder()),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label('Supplier'),
                    TextField(
                      controller: _supplierCtrl,
                      decoration: const InputDecoration(
                          hintText: 'optional',
                          border: OutlineInputBorder()),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Date ──────────────────────────────────────────────────────
          _Label('Date *'),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today,
                      size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(dateFmt.format(_costDate)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }
}
