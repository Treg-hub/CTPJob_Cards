import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_asset.dart';
import '../models/fleet_cost_line.dart';
import '../models/fleet_settings.dart';
import '../models/fleet_work_record.dart';
import '../providers/fleet_provider.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../utils/role.dart' as role_utils;
import '../widgets/fleet_app_bar.dart';
import '../widgets/fleet_asset_selector.dart';
import '../widgets/fleet_cost_widgets.dart';
import '../widgets/fleet_form_fields.dart';
import '../widgets/fleet_work_record_selector.dart';

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
  FleetWorkRecord? _selectedWorkRecord;

  bool get _linkedFromJob =>
      widget.preSelectedWorkRecordId != null && _selectedWorkRecord != null;

  @override
  void initState() {
    super.initState();
    if (widget.preSelectedAssetId != null) {
      _service.getAsset(widget.preSelectedAssetId!).then((a) {
        if (a != null && mounted) {
          setState(() => _selectedAsset = a);
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
      _snack('Please pick which Hyster this cost is for.');
      return;
    }
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) {
      _snack('Please describe what was purchased or paid for.');
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
      final result = await _service.createCostLineResilient(line);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.queuedOffline
                  ? 'Cost saved offline — will sync when connection returns.'
                  : _selectedWorkRecord != null
                      ? 'Cost saved and linked to the mechanic job.'
                      : 'Cost saved.',
            ),
            backgroundColor:
                result.queuedOffline ? Colors.orange : Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) _snack('Could not save cost: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM yyyy');
    final settingsAsync = ref.watch(fleetSettingsProvider);
    final settings = settingsAsync.asData?.value ?? FleetSettings.defaults;
    final costMgrUx = role_utils.isFleetCostManager(currentEmployee, settings) &&
        !role_utils.isFleetAdmin(currentEmployee);

    return Scaffold(
      appBar: FleetAppBar(
        title: costMgrUx ? 'Add a Cost' : 'Add Cost',
        actions: [
          if (!costMgrUx)
            if (_saving)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              TextButton(
                onPressed: _save,
                child: const Text('Save'),
              ),
        ],
      ),
      bottomNavigationBar: costMgrUx
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving…' : 'Save cost'),
                  style: FilledButton.styleFrom(
                    backgroundColor: kBrandOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (costMgrUx) ...[
            FleetCostGuideBanner(linkedToJob: _linkedFromJob),
            const SizedBox(height: 16),
          ],

          FleetSectionLabel(
            costMgrUx ? 'Which Hyster? *' : 'Asset *',
          ),
          FleetAssetSelector(
            value: _selectedAsset,
            onChanged: (asset) {
              setState(() {
                _selectedAsset = asset;
                if (_selectedWorkRecord != null &&
                    _selectedWorkRecord!.assetId != asset?.id) {
                  _selectedWorkRecord = null;
                }
              });
            },
          ),
          const SizedBox(height: 16),

          FleetSectionLabel(
            costMgrUx
                ? 'Link to mechanic\'s job (optional)'
                : 'Work Record (optional)',
          ),
          if (_linkedFromJob && _selectedWorkRecord != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedWorkRecord!.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_selectedWorkRecord!.assetName} · ${_selectedWorkRecord!.workTypeName}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).appColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ] else
            FleetWorkRecordSelector(
              assetId: _selectedAsset?.id,
              value: _selectedWorkRecord,
              hintText: costMgrUx
                  ? 'Pick a job from History (optional)'
                  : 'Link to a work record (optional)',
              showCostStatus: costMgrUx,
              onChanged: (record) =>
                  setState(() => _selectedWorkRecord = record),
            ),
          if (costMgrUx)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Linking helps track spend against a specific repair or service.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).appColors.textMuted,
                ),
              ),
            ),
          const SizedBox(height: 16),

          FleetSectionLabel(
            costMgrUx ? 'What type of cost? *' : 'Category *',
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: FleetCostCategory.values.map((c) {
              return ChoiceChip(
                label: Text(c.displayLabel),
                selected: _category == c,
                selectedColor: kBrandOrange,
                labelStyle: TextStyle(
                  color: _category == c ? Colors.white : null,
                ),
                onSelected: (_) => setState(() => _category = c),
              );
            }).toList(),
          ),
          if (costMgrUx) ...[
            const SizedBox(height: 10),
            FleetCostCategoryHint(category: _category),
          ],
          const SizedBox(height: 16),

          FleetSectionLabel(
            costMgrUx ? 'What was purchased / paid for? *' : 'Description *',
          ),
          TextField(
            controller: _descCtrl,
            decoration: fleetDropdownDecoration(
              hintText: costMgrUx
                  ? 'e.g. Transmission oil filter kit'
                  : 'e.g. Oil filter replacement',
            ),
          ),
          const SizedBox(height: 16),

          FleetSectionLabel(
            costMgrUx ? 'Amount (Rands) *' : 'Amount (ZAR) *',
          ),
          TextField(
            controller: _amountCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: fleetDropdownDecoration(
              hintText: '0.00',
            ).copyWith(prefixText: 'R '),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FleetSectionLabel(
                      costMgrUx ? 'Invoice number' : 'Invoice Ref',
                    ),
                    TextField(
                      controller: _invoiceRefCtrl,
                      decoration: fleetDropdownDecoration(
                        hintText: 'optional',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FleetSectionLabel('Supplier'),
                    TextField(
                      controller: _supplierCtrl,
                      decoration: fleetDropdownDecoration(
                        hintText: 'optional',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          FleetSectionLabel(
            costMgrUx ? 'Invoice / payment date *' : 'Date *',
          ),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(4),
            child: InputDecorator(
              decoration: fleetDropdownDecoration(),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: Theme.of(context).appColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(dateFmt.format(_costDate)),
                ],
              ),
            ),
          ),
          SizedBox(height: costMgrUx ? 100 : 80),
        ],
      ),
    );
  }
}