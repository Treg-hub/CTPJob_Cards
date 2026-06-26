import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../constants/collections.dart';
import '../main.dart' show currentEmployee;
import '../models/employee.dart';
import '../models/parsed_document.dart';
import '../models/security_entry.dart';
import '../models/security_gate.dart';
import '../models/security_vehicle.dart';
import '../models/security_vehicle_trip.dart';
import '../providers/security_provider.dart';
import '../services/security_service.dart';
import '../theme/app_theme.dart';
import 'security_document_scan_screen.dart';

/// Company car exit/return — disc scan identifies vehicle; exit adds licence + clock + mileage.
class SecurityCompanyCarScreen extends ConsumerStatefulWidget {
  const SecurityCompanyCarScreen({super.key});

  @override
  ConsumerState<SecurityCompanyCarScreen> createState() =>
      _SecurityCompanyCarScreenState();
}

class _SecurityCompanyCarScreenState
    extends ConsumerState<SecurityCompanyCarScreen> {
  final _service = SecurityService();
  final _clockNoCtrl = TextEditingController();
  final _odometerCtrl = TextEditingController();
  final _purposeCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  SecurityVehicle? _vehicle;
  Employee? _resolvedEmployee;
  ParsedDocument? _driverLicence;
  ParsedDocument? _disc;
  bool _isReturn = false;
  bool _discDamaged = false;
  bool _submitting = false;
  bool _resolvingEmployee = false;

  @override
  void dispose() {
    _clockNoCtrl.dispose();
    _odometerCtrl.dispose();
    _purposeCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  SecurityVehicle? _matchVehicleFromDisc(
    List<SecurityVehicle> companyCars,
    ParsedDocument? disc,
  ) {
    if (disc?.vehicleReg == null) return null;
    final reg = SecurityVehicle.normalizeReg(disc!.vehicleReg);
    for (final v in companyCars) {
      if (v.vehicleReg == reg) return v;
    }
    return null;
  }

  Future<void> _scanDisc(List<SecurityVehicle> companyCars) async {
    final result = await Navigator.push<ParsedDocument>(
      context,
      MaterialPageRoute(
        builder: (_) => const SecurityDocumentScanScreen(
          title: 'Scan Licence Disc',
          expectedType: SecurityDocumentType.licenseDisc,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final matched = _matchVehicleFromDisc(companyCars, result);
    setState(() {
      _disc = result;
      _vehicle = matched;
    });
    if (matched == null) {
      _showError(
        'Disc reg ${result.vehicleReg ?? "—"} is not a registered company car. '
        'Add it in Pulse Settings › Site Security › Company vehicles.',
      );
    }
  }

  Future<void> _resolveEmployeeFromClock() async {
    final clock = _clockNoCtrl.text.trim();
    if (clock.isEmpty) {
      setState(() => _resolvedEmployee = null);
      return;
    }
    setState(() => _resolvingEmployee = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection(Collections.employees)
          .doc(clock)
          .get();
      if (!mounted) return;
      setState(() {
        _resolvedEmployee = doc.exists
            ? Employee.fromFirestore(doc.data() ?? {}, doc.id)
            : null;
      });
    } finally {
      if (mounted) setState(() => _resolvingEmployee = false);
    }
  }

  Future<void> _scanDriverLicence() async {
    final result = await Navigator.push<ParsedDocument>(
      context,
      MaterialPageRoute(
        builder: (_) => const SecurityDocumentScanScreen(
          title: "Scan Driver's Licence",
          expectedType: SecurityDocumentType.driverLicence,
        ),
      ),
    );
    if (result != null) setState(() => _driverLicence = result);
  }

  Future<void> _submit(SecurityGate? gate) async {
    final emp = currentEmployee;
    if (emp == null || gate == null) return;

    if (_vehicle == null) {
      _showError(
        _discDamaged
            ? 'Select a company car from the list.'
            : 'Scan the licence disc to identify the company car.',
      );
      return;
    }

    if (!_discDamaged) {
      if (_disc == null) {
        _showError('Scan the licence disc on the vehicle first.');
        return;
      }
      final discReg = SecurityVehicle.normalizeReg(_disc!.vehicleReg);
      if (discReg != _vehicle!.vehicleReg) {
        _showError(
          'Disc reg $discReg does not match company car ${_vehicle!.vehicleReg}.',
        );
        return;
      }
    }

    final odometer = double.tryParse(_odometerCtrl.text.trim());
    if (odometer == null) {
      _showError('Enter a valid odometer reading (km) from the vehicle.');
      return;
    }

    final direction =
        _isReturn ? SecurityDirection.in_ : SecurityDirection.out;

    if (!_isReturn) {
      if (_driverLicence == null) {
        _showError("Scan the driver's licence before exit.");
        return;
      }
      await _resolveEmployeeFromClock();
      if (_clockNoCtrl.text.trim().isEmpty) {
        _showError('Enter the employee clock number.');
        return;
      }
      if (_resolvedEmployee == null) {
        _showError('No employee found for that clock number.');
        return;
      }
      if (_purposeCtrl.text.trim().isEmpty) {
        _showError('Purpose of trip is required.');
        return;
      }
      if (_addressCtrl.text.trim().isEmpty) {
        _showError('Destination (address or business) is required.');
        return;
      }
    }

    final double? mileage = _vehicle!.odometerLast != null && _isReturn
        ? (odometer - _vehicle!.odometerLast!)
            .clamp(0, double.infinity)
            .toDouble()
        : null;

    final sessionId = _isReturn ? null : const Uuid().v4();
    final driver = _isReturn
        ? (_resolvedEmployee?.name ?? _vehicle!.assignedDriver)
        : _resolvedEmployee!.name;

    setState(() => _submitting = true);
    try {
      final entryData = <String, dynamic>{
        'gate_id': gate.id,
        'gate_name': gate.name,
        'direction': direction.value,
        'entry_type': SecurityEntryType.companyCar.value,
        'vehicle_reg': _vehicle!.vehicleReg,
        'driver_name': driver,
        'disc_scan_captured': _disc != null,
        'disc_scan_missing_flag': _discDamaged || _disc == null,
        if (_disc?.expiryDate != null)
          'disc_expiry': _disc!.expiryDate!.toIso8601String(),
        if (_disc?.vehicleMake != null) 'vehicle_make': _disc!.vehicleMake,
        if (!_isReturn) ...{
          'employee_clock_no': _resolvedEmployee!.clockNo,
          'employee_name': _resolvedEmployee!.name,
          'purpose': _purposeCtrl.text.trim(),
          'destination_address': _addressCtrl.text.trim(),
          'odometer_start': odometer,
          'session_id': sessionId,
          'driver_licence_scan_captured': true,
          'id_scan_captured': true,
          if (_driverLicence?.idNumber != null)
            'driver_id_number': _driverLicence!.idNumber,
          if (_driverLicence?.expiryDate != null)
            'driver_licence_expiry':
                _driverLicence!.expiryDate!.toIso8601String(),
          if (_driverLicence?.expiryDate != null)
            'id_expiry': _driverLicence!.expiryDate!.toIso8601String(),
        },
        if (_isReturn) ...{
          'odometer_end': odometer,
          if (mileage != null) 'mileage_km': mileage,
        },
        'logged_by_clock_no': emp.clockNo,
        'logged_by_name': emp.name,
        'logged_at': DateTime.now().toIso8601String(),
      };

      final result = await _service.createEntry(data: entryData);

      await _service.recordCompanyCarTrip(
        trip: SecurityVehicleTrip(
          id: '',
          vehicleReg: _vehicle!.vehicleReg,
          gateId: gate.id,
          direction: direction,
          entryId: result.id,
          loggedAt: DateTime.now(),
          driverName: driver,
          odometerStart: _isReturn ? _vehicle!.odometerLast : odometer,
          odometerEnd: _isReturn ? odometer : null,
          mileageKm: mileage,
          sessionId: sessionId,
        ),
      );

      await _service.updateCompanyVehicleOdometer(
        vehicleId: _vehicle!.id,
        odometer: odometer,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isReturn
                ? 'Company car return logged'
                    '${mileage != null ? ' · ${mileage.toStringAsFixed(0)} km' : ''}'
                : 'Company car exit logged',
          ),
          backgroundColor: kBrandOrange,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      _showError('Failed: $e');
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
    final gate = ref.watch(selectedSecurityGateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Company Car')),
      body: StreamBuilder<List<SecurityVehicle>>(
        stream: _service.watchVehicles(),
        builder: (context, snap) {
          final companyCars =
              (snap.data ?? []).where((v) => v.isCompanyCar).toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (gate == null)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Select a gate on the Security home screen.',
                    ),
                  ),
                ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Exit')),
                  ButtonSegment(value: true, label: Text('Return')),
                ],
                selected: {_isReturn},
                onSelectionChanged: (s) => setState(() {
                  _isReturn = s.first;
                  _driverLicence = null;
                  _disc = null;
                  _vehicle = null;
                  _discDamaged = false;
                  _odometerCtrl.clear();
                }),
              ),
              const SizedBox(height: 8),
              Text(
                _isReturn
                    ? 'Return: scan licence disc to identify the company car, '
                        'then enter return mileage from the odometer.'
                    : 'Exit: scan licence disc to identify the company car, '
                        "then scan driver licence, enter clock number and "
                        'odometer, purpose and destination.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (!_discDamaged)
                OutlinedButton.icon(
                  onPressed: () => _scanDisc(companyCars),
                  icon: Icon(
                    _disc != null ? Icons.check_circle : Icons.qr_code_scanner,
                    color: _disc != null ? Colors.green : null,
                  ),
                  label: Text(
                    _disc != null
                        ? 'Disc scanned: ${_disc!.vehicleReg ?? "—"}'
                        : 'Scan licence disc *',
                  ),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _discDamaged,
                onChanged: (v) => setState(() {
                  _discDamaged = v ?? false;
                  if (_discDamaged) {
                    _disc = null;
                  } else {
                    _vehicle = null;
                  }
                }),
                title: const Text('Disc damaged / cannot scan'),
                subtitle: const Text('Select company car manually — entry will be flagged'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (_discDamaged) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<SecurityVehicle>(
                  initialValue: _vehicle,
                  decoration: const InputDecoration(
                    labelText: 'Company car *',
                    border: OutlineInputBorder(),
                  ),
                  items: companyCars
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(
                            '${v.vehicleReg}'
                            '${v.description != null ? ' — ${v.description}' : ''}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _vehicle = v),
                ),
              ],
              if (_vehicle != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: kBrandOrange.withValues(alpha: 0.08),
                  child: ListTile(
                    leading: const Icon(
                      Icons.directions_car_outlined,
                      color: kBrandOrange,
                    ),
                    title: Text(_vehicle!.vehicleReg),
                    subtitle: Text(
                      _vehicle!.description ?? 'Company car',
                    ),
                    trailing: _vehicle!.odometerLast != null
                        ? Text(
                            'Last: ${_vehicle!.odometerLast!.toStringAsFixed(0)} km',
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        : null,
                  ),
                ),
              ] else if (_disc != null) ...[
                const SizedBox(height: 12),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Disc scanned but no matching company car found. '
                      'Check Pulse Settings › Company vehicles.',
                    ),
                  ),
                ),
              ],
              if (!_isReturn && _vehicle != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _scanDriverLicence,
                  icon: Icon(
                    _driverLicence != null
                        ? Icons.check_circle
                        : Icons.badge_outlined,
                    color: _driverLicence != null ? Colors.green : null,
                  ),
                  label: const Text("Scan driver's licence *"),
                ),
                if (_driverLicence?.fullName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Licence: ${_driverLicence!.fullName}'
                    '${_driverLicence!.idNumber != null ? ' · ${_driverLicence!.idNumber}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _clockNoCtrl,
                  decoration: InputDecoration(
                    labelText: 'Employee clock number *',
                    border: const OutlineInputBorder(),
                    suffixIcon: _resolvingEmployee
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.search),
                            onPressed: _resolveEmployeeFromClock,
                            tooltip: 'Look up employee',
                          ),
                    helperText: _resolvedEmployee != null
                        ? _resolvedEmployee!.displayName
                        : 'Check clock number on driver ID badge',
                  ),
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _resolveEmployeeFromClock(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _purposeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Purpose of trip *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _addressCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Destination (address or business) *',
                    border: OutlineInputBorder(),
                    helperText: 'Street address or business name',
                  ),
                  maxLines: 2,
                ),
              ],
              if (_vehicle != null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _odometerCtrl,
                  decoration: InputDecoration(
                    labelText: _isReturn
                        ? 'Return mileage — odometer (km) *'
                        : 'Exit mileage — odometer (km) *',
                    border: const OutlineInputBorder(),
                    helperText: _vehicle?.odometerLast != null
                        ? 'Last recorded: ${_vehicle!.odometerLast!.toStringAsFixed(0)} km'
                        : 'Read odometer in vehicle',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submitting || gate == null
                    ? null
                    : () => _submit(gate),
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
                    : Text(_isReturn ? 'Log return' : 'Log exit'),
              ),
            ],
          );
        },
      ),
    );
  }
}