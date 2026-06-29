import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../constants/collections.dart';
import '../main.dart' show currentEmployee;
import '../models/employee.dart';
import '../models/parsed_document.dart';
import '../models/security_contractor.dart';
import '../models/security_deny_entry.dart';
import '../models/security_entry.dart';
import '../models/security_gate.dart';
import '../models/security_settings.dart';
import '../models/security_vehicle.dart';
import '../models/security_vehicle_trip.dart';
import '../providers/security_provider.dart';
import '../services/security_service.dart';
import '../theme/app_theme.dart';
import '../utils/screen_insets.dart';
import '../widgets/security_suggestion_field.dart';
import 'security_document_scan_screen.dart';

enum _GateFlowKind {
  visitorEntry,
  visitorExit,
  companyCarExit,
  companyCarReturn,
}

/// Unified vehicle gate capture — scan disc first, auto-detect entry/exit and
/// company car, operator can override direction for testing.
class SecurityVehicleGateScreen extends ConsumerStatefulWidget {
  const SecurityVehicleGateScreen({super.key});

  @override
  ConsumerState<SecurityVehicleGateScreen> createState() =>
      _SecurityVehicleGateScreenState();
}

class _SecurityVehicleGateScreenState
    extends ConsumerState<SecurityVehicleGateScreen> {
  final _service = SecurityService();
  final _driverCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _purposeCtrl = TextEditingController();
  final _overrideCtrl = TextEditingController();
  final _licenceMissingNoteCtrl = TextEditingController();
  final _discrepancyNoteCtrl = TextEditingController();
  final _clockNoCtrl = TextEditingController();
  final _odometerCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  ParsedDocument? _disc;
  ParsedDocument? _driverLicence;
  SecurityEntry? _onSiteEntry;
  SecurityVehicle? _companyVehicle;
  SecurityContractor? _contractor;
  SecurityEntryType _entryType = SecurityEntryType.visitor;

  SecurityDirection _direction = SecurityDirection.in_;
  SecurityDirection? _autoDirection;
  bool _directionOverridden = false;

  bool _licenceUnavailable = false;
  bool _discDamaged = false;
  int _occupantCount = 1;
  int _occupantsLeaving = 1;
  final List<String> _photoPaths = [];
  Employee? _resolvedEmployee;
  bool _resolvingEmployee = false;
  bool _submitting = false;

  @override
  void dispose() {
    _driverCtrl.dispose();
    _hostCtrl.dispose();
    _companyCtrl.dispose();
    _purposeCtrl.dispose();
    _overrideCtrl.dispose();
    _licenceMissingNoteCtrl.dispose();
    _discrepancyNoteCtrl.dispose();
    _clockNoCtrl.dispose();
    _odometerCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  _GateFlowKind get _flowKind {
    if (_companyVehicle != null) {
      return _direction == SecurityDirection.out
          ? _GateFlowKind.companyCarExit
          : _GateFlowKind.companyCarReturn;
    }
    return _direction == SecurityDirection.out
        ? _GateFlowKind.visitorExit
        : _GateFlowKind.visitorEntry;
  }

  String get _flowLabel => switch (_flowKind) {
        _GateFlowKind.visitorEntry => 'Visitor / contractor entry',
        _GateFlowKind.visitorExit => 'Visitor / contractor exit',
        _GateFlowKind.companyCarExit => 'Company car exit',
        _GateFlowKind.companyCarReturn => 'Company car return',
      };

  String get _submitLabel => switch (_flowKind) {
        _GateFlowKind.visitorEntry => 'Log entry',
        _GateFlowKind.visitorExit => 'Log exit',
        _GateFlowKind.companyCarExit => 'Log company car exit',
        _GateFlowKind.companyCarReturn => 'Log company car return',
      };

  void _applyDiscContext({
    required ParsedDocument disc,
    List<SecurityEntry>? onSite,
    List<SecurityVehicle>? vehicles,
  }) {
    final reg = SecurityVehicle.normalizeReg(disc.vehicleReg);
    final onSiteList = onSite ?? [];
    final vehicleList = vehicles ?? [];
    final match = _service.findOnSiteByReg(onSiteList, reg);
    final company = _service.findCompanyVehicle(vehicleList, reg);
    final suggested =
        match != null ? SecurityDirection.out : SecurityDirection.in_;

    setState(() {
      _disc = disc;
      _onSiteEntry = match;
      _companyVehicle = company;
      _autoDirection = suggested;
      if (!_directionOverridden) {
        _direction = suggested;
      }
      _occupantsLeaving = match?.occupantCount ?? 1;
      _discrepancyNoteCtrl.clear();
      if (company != null) {
        _discDamaged = false;
      }
    });
  }

  void _setDirection(SecurityDirection direction) {
    setState(() {
      _direction = direction;
      _directionOverridden = _autoDirection != null && direction != _autoDirection;
    });
  }

  void _resetDirectionToAuto() {
    if (_autoDirection == null) return;
    setState(() {
      _direction = _autoDirection!;
      _directionOverridden = false;
    });
  }

  Future<void> _scanDisc(
    List<SecurityEntry> onSite,
    List<SecurityVehicle> vehicles,
  ) async {
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
    _applyDiscContext(disc: result, onSite: onSite, vehicles: vehicles);
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
    if (result == null || !mounted) return;
    setState(() {
      _driverLicence = result;
      _licenceUnavailable = false;
      if (result.fullName != null && _driverCtrl.text.isEmpty) {
        _driverCtrl.text = result.fullName!;
      }
    });
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

  Future<void> _addContractor() async {
    final nameCtrl = TextEditingController();
    final added = await showDialog<SecurityContractor>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add contractor'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Contractor name',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              try {
                final created = await _service.addContractor(name: name);
                if (ctx.mounted) Navigator.pop(ctx, created);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Failed to add contractor: $e')),
                  );
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    if (added != null) setState(() => _contractor = added);
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (picked != null) setState(() => _photoPaths.add(picked.path));
  }

  void _selectOnSite(SecurityEntry entry) {
    setState(() {
      _onSiteEntry = entry;
      _occupantsLeaving = entry.occupantCount ?? 1;
      _discrepancyNoteCtrl.clear();
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  Future<void> _submit(
    SecuritySettings settings,
    SecurityGate? gate,
    List<SecurityDenyEntry> denyList,
    List<SecurityVehicle> vehicles,
    List<SecurityEntry> onSite,
    List<SecurityContractor> contractors,
  ) async {
    final emp = currentEmployee;
    if (emp == null || gate == null) return;

    if (_disc == null && !_discDamaged) {
      _showError('Scan the vehicle licence disc first.');
      return;
    }

    switch (_flowKind) {
      case _GateFlowKind.visitorEntry:
        await _submitVisitorEntry(settings, gate, denyList, vehicles);
      case _GateFlowKind.visitorExit:
        await _submitVisitorExit(gate, onSite);
      case _GateFlowKind.companyCarExit:
        await _submitCompanyCarExit(gate);
      case _GateFlowKind.companyCarReturn:
        await _submitCompanyCarReturn(gate);
    }
  }

  Future<void> _submitVisitorEntry(
    SecuritySettings settings,
    SecurityGate gate,
    List<SecurityDenyEntry> denyList,
    List<SecurityVehicle> vehicles,
  ) async {
    final emp = currentEmployee!;

    if (!gate.allowsEntryType(_entryType)) {
      _showError('This gate does not allow ${_entryType.label} entries.');
      return;
    }

    if (_disc == null) {
      _showError('Scan the vehicle licence disc first.');
      return;
    }

    final licenceCaptured = _driverLicence != null;
    if (settings.driverLicenceScanRequired && !licenceCaptured) {
      _showError("Scan the driver's licence (back PDF417) first.");
      return;
    }
    if (!settings.driverLicenceScanRequired &&
        !licenceCaptured &&
        !_licenceUnavailable) {
      _showError("Scan the driver's licence or mark it as unavailable.");
      return;
    }
    if (_licenceUnavailable && _licenceMissingNoteCtrl.text.trim().isEmpty) {
      _showError('Enter a note explaining why the licence was not scanned.');
      return;
    }

    final reg = SecurityVehicle.normalizeReg(_disc!.vehicleReg);
    if (reg.isEmpty) {
      _showError('Could not read registration from the scanned disc.');
      return;
    }

    if (_companyVehicle != null) {
      _showError(
        '$reg is a registered company car. Switch to EXIT for a company car trip, '
        'or ENTRY for a return.',
      );
      return;
    }

    if (_occupantCount < 1) {
      _showError('Occupant count must be at least 1.');
      return;
    }

    if (settings.purposeOfVisitRequired && _purposeCtrl.text.trim().isEmpty) {
      _showError('Purpose of visit is required.');
      return;
    }

    if (_entryType == SecurityEntryType.contractor && _contractor == null) {
      _showError('Select a contractor from the list or add a new one.');
      return;
    }

    final driverName = _driverCtrl.text.trim().isEmpty
        ? _driverLicence?.fullName
        : _driverCtrl.text.trim();
    if (driverName == null || driverName.isEmpty) {
      _showError('Driver name is required.');
      return;
    }

    final deny = _service.matchDenyList(
      denyList,
      vehicleReg: reg,
      driverName: driverName,
    );
    if (deny != null) {
      await _logDenyBlocked(gate, reg, deny, emp);
      return;
    }

    final licenceExpiry = _driverLicence?.expiryDate;
    final compliance = _service.evaluateCompliance(
      entryType: _entryType,
      discExpiry: _disc?.expiryDate,
      idExpiry: licenceExpiry,
      warnDays: settings.licenseExpiryWarnDays,
    );

    if (compliance.blocked) {
      _showError(compliance.message ?? 'Transporter compliance failed.');
      return;
    }

    if (compliance.warn && _overrideCtrl.text.trim().isEmpty) {
      _showError(
        '${compliance.message}. Enter an override reason to continue.',
      );
      return;
    }

    final sessionId = const Uuid().v4();
    final host = _hostCtrl.text.trim();
    final company = _companyCtrl.text.trim();
    final complianceNotes = <String>[
      if (compliance.message != null) compliance.message!,
      if (_licenceUnavailable)
        'Driver licence not scanned: ${_licenceMissingNoteCtrl.text.trim()}',
    ];

    setState(() => _submitting = true);
    try {
      final result = await _service.createEntry(
        data: {
          'gate_id': gate.id,
          'gate_name': gate.name,
          'direction': SecurityDirection.in_.value,
          'entry_type': _entryType.value,
          'vehicle_reg': reg,
          'session_id': sessionId,
          'occupant_count': _occupantCount,
          'driver_name': driverName,
          if (_contractor != null) 'contractor_id': _contractor!.id,
          if (_contractor != null) 'contractor_name': _contractor!.name,
          'purpose': _purposeCtrl.text.trim().isEmpty
              ? null
              : _purposeCtrl.text.trim(),
          if (host.isNotEmpty) 'host_name': host,
          if (company.isNotEmpty) 'company_name': company,
          'logged_by_clock_no': emp.clockNo,
          'logged_by_name': emp.name,
          'logged_at': DateTime.now().toIso8601String(),
          'disc_scan_captured': true,
          'driver_licence_scan_captured': licenceCaptured,
          'driver_licence_missing_flag': _licenceUnavailable,
          'id_scan_captured': licenceCaptured,
          if (_driverLicence?.idNumber != null)
            'driver_id_number': _driverLicence!.idNumber,
          if (_disc?.expiryDate != null)
            'disc_expiry': _disc!.expiryDate!.toIso8601String(),
          if (licenceExpiry != null)
            'driver_licence_expiry': licenceExpiry.toIso8601String(),
          if (licenceExpiry != null) 'id_expiry': licenceExpiry.toIso8601String(),
          if (_disc?.vehicleMake != null) 'vehicle_make': _disc!.vehicleMake,
          if (_disc?.vehicleModel != null) 'vehicle_model': _disc!.vehicleModel,
          if (_disc?.vehicleColour != null)
            'vehicle_colour': _disc!.vehicleColour,
          'transporter_compliant': _entryType == SecurityEntryType.transporter,
          if (complianceNotes.isNotEmpty)
            'compliance_notes': complianceNotes.join('; '),
          if (_overrideCtrl.text.trim().isNotEmpty)
            'override_reason': _overrideCtrl.text.trim(),
        },
        photoLocalPaths: _photoPaths,
      );

      if (host.isNotEmpty) {
        await _service.ensureLookupOption(
          type: 'host',
          value: host,
          createdByClockNo: emp.clockNo,
        );
      }
      if (company.isNotEmpty) {
        await _service.ensureLookupOption(
          type: 'company',
          value: company,
          createdByClockNo: emp.clockNo,
        );
      }

      if (!mounted) return;
      _showSuccess(result, 'Entry logged');
    } catch (e) {
      _showError('Failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitVisitorExit(
    SecurityGate gate,
    List<SecurityEntry> onSite,
  ) async {
    final emp = currentEmployee!;

    if (_onSiteEntry == null) {
      _showError('Select or scan to match an on-site vehicle.');
      return;
    }

    final reg = SecurityVehicle.normalizeReg(
      _disc?.vehicleReg ?? _onSiteEntry!.vehicleReg,
    );
    if (reg.isEmpty) {
      _showError('Vehicle registration is missing.');
      return;
    }

    if (_disc != null &&
        SecurityVehicle.normalizeReg(_onSiteEntry!.vehicleReg ?? '') != reg) {
      _showError(
        'Disc reg $reg does not match on-site vehicle ${_onSiteEntry!.vehicleReg}.',
      );
      return;
    }

    final recorded = _onSiteEntry!.occupantCount ?? 1;
    final discrepancy = _occupantsLeaving != recorded;
    if (discrepancy && _discrepancyNoteCtrl.text.trim().isEmpty) {
      _showError(
        recorded > _occupantsLeaving
            ? 'Explain why $recorded occupant(s) were recorded but only '
                '$_occupantsLeaving leaving.'
            : 'Explain why more people are leaving than were logged in.',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final result = await _service.scanOut(
        onSiteEntry: _onSiteEntry!,
        gateId: gate.id,
        gateName: gate.name,
        loggedByClockNo: emp.clockNo,
        loggedByName: emp.name,
        discScan: _disc,
        occupantsLeaving: _occupantsLeaving,
        occupantDiscrepancyNote: discrepancy
            ? _discrepancyNoteCtrl.text.trim()
            : null,
        discScanMissingFlag: _disc == null,
      );

      if (!mounted) return;
      final partial = _occupantsLeaving < recorded;
      _showSuccess(
        result,
        partial ? 'Exit logged (partial exit flagged)' : 'Exit logged',
        partial: partial,
      );
    } catch (e) {
      _showError('Failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitCompanyCarExit(SecurityGate gate) async {
    final emp = currentEmployee!;

    if (_companyVehicle == null) {
      _showError('Scan a registered company car licence disc.');
      return;
    }

    if (!_discDamaged) {
      if (_disc == null) {
        _showError('Scan the licence disc on the vehicle first.');
        return;
      }
      final discReg = SecurityVehicle.normalizeReg(_disc!.vehicleReg);
      if (discReg != _companyVehicle!.vehicleReg) {
        _showError(
          'Disc reg $discReg does not match company car ${_companyVehicle!.vehicleReg}.',
        );
        return;
      }
    }

    if (_driverLicence == null) {
      _showError("Scan the driver's licence before exit.");
      return;
    }

    final odometer = double.tryParse(_odometerCtrl.text.trim());
    if (odometer == null) {
      _showError('Enter a valid exit odometer reading (km).');
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

    final sessionId = const Uuid().v4();
    setState(() => _submitting = true);
    try {
      final entryData = <String, dynamic>{
        'gate_id': gate.id,
        'gate_name': gate.name,
        'direction': SecurityDirection.out.value,
        'entry_type': SecurityEntryType.companyCar.value,
        'vehicle_reg': _companyVehicle!.vehicleReg,
        'driver_name': _resolvedEmployee!.name,
        'disc_scan_captured': _disc != null,
        'disc_scan_missing_flag': _discDamaged || _disc == null,
        if (_disc?.expiryDate != null)
          'disc_expiry': _disc!.expiryDate!.toIso8601String(),
        if (_disc?.vehicleMake != null) 'vehicle_make': _disc!.vehicleMake,
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
        'logged_by_clock_no': emp.clockNo,
        'logged_by_name': emp.name,
        'logged_at': DateTime.now().toIso8601String(),
      };

      final result = await _service.createEntry(data: entryData);

      await _service.recordCompanyCarTrip(
        trip: SecurityVehicleTrip(
          id: '',
          vehicleReg: _companyVehicle!.vehicleReg,
          gateId: gate.id,
          direction: SecurityDirection.out,
          entryId: result.id,
          loggedAt: DateTime.now(),
          driverName: _resolvedEmployee!.name,
          odometerStart: odometer,
          sessionId: sessionId,
        ),
      );

      await _service.updateCompanyVehicleOdometer(
        vehicleId: _companyVehicle!.id,
        odometer: odometer,
      );

      if (!mounted) return;
      _showSuccess(result, 'Company car exit logged');
    } catch (e) {
      _showError('Failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitCompanyCarReturn(SecurityGate gate) async {
    final emp = currentEmployee!;

    if (_companyVehicle == null) {
      _showError('Scan a registered company car licence disc.');
      return;
    }

    if (!_discDamaged) {
      if (_disc == null) {
        _showError('Scan the licence disc on the vehicle first.');
        return;
      }
      final discReg = SecurityVehicle.normalizeReg(_disc!.vehicleReg);
      if (discReg != _companyVehicle!.vehicleReg) {
        _showError(
          'Disc reg $discReg does not match company car ${_companyVehicle!.vehicleReg}.',
        );
        return;
      }
    }

    final odometer = double.tryParse(_odometerCtrl.text.trim());
    if (odometer == null) {
      _showError('Enter a valid return odometer reading (km).');
      return;
    }

    final mileage = _companyVehicle!.odometerLast != null
        ? (odometer - _companyVehicle!.odometerLast!)
            .clamp(0, double.infinity)
            .toDouble()
        : null;

    setState(() => _submitting = true);
    try {
      final entryData = <String, dynamic>{
        'gate_id': gate.id,
        'gate_name': gate.name,
        'direction': SecurityDirection.in_.value,
        'entry_type': SecurityEntryType.companyCar.value,
        'vehicle_reg': _companyVehicle!.vehicleReg,
        'driver_name':
            _companyVehicle!.assignedDriver ?? _companyVehicle!.description,
        'disc_scan_captured': _disc != null,
        'disc_scan_missing_flag': _discDamaged || _disc == null,
        if (_disc?.expiryDate != null)
          'disc_expiry': _disc!.expiryDate!.toIso8601String(),
        if (_disc?.vehicleMake != null) 'vehicle_make': _disc!.vehicleMake,
        'odometer_end': odometer,
        if (mileage != null) 'mileage_km': mileage,
        'logged_by_clock_no': emp.clockNo,
        'logged_by_name': emp.name,
        'logged_at': DateTime.now().toIso8601String(),
      };

      final result = await _service.createEntry(data: entryData);

      await _service.recordCompanyCarTrip(
        trip: SecurityVehicleTrip(
          id: '',
          vehicleReg: _companyVehicle!.vehicleReg,
          gateId: gate.id,
          direction: SecurityDirection.in_,
          entryId: result.id,
          loggedAt: DateTime.now(),
          driverName: _companyVehicle!.assignedDriver,
          odometerStart: _companyVehicle!.odometerLast,
          odometerEnd: odometer,
          mileageKm: mileage,
        ),
      );

      await _service.updateCompanyVehicleOdometer(
        vehicleId: _companyVehicle!.id,
        odometer: odometer,
      );

      if (!mounted) return;
      _showSuccess(
        result,
        'Company car return logged'
        '${mileage != null ? ' · ${mileage.toStringAsFixed(0)} km' : ''}',
      );
    } catch (e) {
      _showError('Failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _logDenyBlocked(
    SecurityGate gate,
    String reg,
    SecurityDenyEntry deny,
    dynamic emp,
  ) async {
    final result = await _service.createEntry(
      data: {
        'gate_id': gate.id,
        'gate_name': gate.name,
        'direction': SecurityDirection.in_.value,
        'entry_type': _entryType.value,
        'vehicle_reg': reg,
        'driver_name':
            _driverCtrl.text.trim().isEmpty ? null : _driverCtrl.text.trim(),
        'deny_blocked': true,
        'deny_reason': deny.reason,
        'logged_by_clock_no': emp.clockNo,
        'logged_by_name': emp.name,
        'logged_at': DateTime.now().toIso8601String(),
      },
    );

    await _service.notifyDenyEntry(
      gateId: gate.id,
      gateName: gate.name,
      vehicleReg: reg,
      driverName: _driverCtrl.text.trim().isEmpty
          ? null
          : _driverCtrl.text.trim(),
      denyReason: deny.reason,
      entryId: result.id,
    );

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deny list — entry blocked'),
        content: Text('$reg is on the deny list.\n\nReason: ${deny.reason}'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  void _showSuccess(
    ({String id, String? entryNumber, bool queuedOffline}) result,
    String message, {
    bool partial = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.queuedOffline
              ? '$message (queued ${result.entryNumber ?? result.id})'
              : '$message: ${result.entryNumber ?? result.id}',
        ),
        backgroundColor: partial ? Colors.orange.shade800 : kBrandOrange,
      ),
    );
    Navigator.pop(context);
  }

  String? _autoDetectHint(List<SecurityEntry> onSite) {
    if (_disc == null) {
      return 'Scan the licence disc to auto-detect entry or exit.';
    }
    final reg = SecurityVehicle.normalizeReg(_disc!.vehicleReg);
    if (_companyVehicle != null) {
      final onSiteMatch = _onSiteEntry != null;
      return onSiteMatch
          ? 'Company car $reg is on site → suggested EXIT (trip out)'
          : 'Company car $reg not on site → suggested ENTRY (return)';
    }
    if (_onSiteEntry != null) {
      return '$reg is on site → suggested EXIT';
    }
    return '$reg not on site → suggested ENTRY';
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(securitySettingsProvider).valueOrNull;
    final gate = ref.watch(selectedSecurityGateProvider);

    if (settings == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle at Gate')),
      body: StreamBuilder<List<SecurityEntry>>(
        stream: _service.watchRecentEntries(limit: 200),
        builder: (context, entriesSnap) {
          final onSite =
              _service.computeOnSite(entriesSnap.data ?? []);
          return StreamBuilder<List<SecurityDenyEntry>>(
            stream: _service.watchDenyList(),
            builder: (context, denySnap) {
              return StreamBuilder<List<SecurityVehicle>>(
                stream: _service.watchVehicles(),
                builder: (context, vehicleSnap) {
                  return StreamBuilder<List<SecurityContractor>>(
                    stream: _service.watchContractors(),
                    builder: (context, contractorSnap) {
                      return StreamBuilder<List<String>>(
                        stream: _service.watchLookupSuggestions('host'),
                        builder: (context, hostSnap) {
                          return StreamBuilder<List<String>>(
                            stream: _service.watchLookupSuggestions('company'),
                            builder: (context, companySnap) {
                              final vehicles = vehicleSnap.data ?? [];
                              final contractors =
                                  contractorSnap.data ?? [];
                              final licenceRequired =
                                  settings.driverLicenceScanRequired;
                              final recorded =
                                  _onSiteEntry?.occupantCount ?? 1;
                              final discrepancy = _flowKind ==
                                      _GateFlowKind.visitorExit &&
                                  _onSiteEntry != null &&
                                  _occupantsLeaving != recorded;
                              final partial = discrepancy &&
                                  _occupantsLeaving < recorded;

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
                                  _DirectionPanel(
                                    direction: _direction,
                                    autoDirection: _autoDirection,
                                    overridden: _directionOverridden,
                                    hint: _autoDetectHint(onSite),
                                    onChanged: _setDirection,
                                    onResetAuto: _directionOverridden
                                        ? _resetDirectionToAuto
                                        : null,
                                  ),
                                  const SizedBox(height: 12),
                                  Card(
                                    color: kBrandOrange.withValues(alpha: 0.08),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            _direction ==
                                                    SecurityDirection.in_
                                                ? Icons.login
                                                : Icons.logout,
                                            color: kBrandOrange,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _flowLabel,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: gate == null
                                        ? null
                                        : () => _scanDisc(onSite, vehicles),
                                    icon: Icon(
                                      _disc != null
                                          ? Icons.check_circle
                                          : Icons.qr_code_scanner,
                                      color: _disc != null
                                          ? Colors.green
                                          : null,
                                    ),
                                    label: Text(
                                      _disc != null
                                          ? 'Disc scanned: '
                                              '${SecurityVehicle.normalizeReg(_disc!.vehicleReg)}'
                                          : 'Scan licence disc *',
                                    ),
                                  ),
                                  if (_disc != null) ...[
                                    const SizedBox(height: 8),
                                    _DiscSummaryCard(disc: _disc!),
                                  ],
                                  if (_companyVehicle != null) ...[
                                    const SizedBox(height: 12),
                                    _CompanyCarCard(
                                      vehicle: _companyVehicle!,
                                      discDamaged: _discDamaged,
                                      onDiscDamagedChanged: (v) => setState(() {
                                        _discDamaged = v;
                                        if (v) _disc = null;
                                      }),
                                      vehicles: vehicles
                                          .where((v) => v.isCompanyCar)
                                          .toList(),
                                      selected: _companyVehicle,
                                      onSelect: (v) =>
                                          setState(() => _companyVehicle = v),
                                    ),
                                  ],
                                  ..._buildFlowFields(
                                    context: context,
                                    settings: settings,
                                    licenceRequired: licenceRequired,
                                    contractors: contractors,
                                    hostSuggestions: hostSnap.data ?? [],
                                    companySuggestions:
                                        companySnap.data ?? [],
                                    onSite: onSite,
                                    recorded: recorded,
                                    discrepancy: discrepancy,
                                    partial: partial,
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
      bottomNavigationBar: gate == null
          ? null
          : StreamBuilder<List<SecurityDenyEntry>>(
              stream: _service.watchDenyList(),
              builder: (context, denySnap) {
                return StreamBuilder<List<SecurityVehicle>>(
                  stream: _service.watchVehicles(),
                  builder: (context, vehicleSnap) {
                    return StreamBuilder<List<SecurityEntry>>(
                      stream: _service.watchRecentEntries(limit: 200),
                      builder: (context, entriesSnap) {
                        final onSite = _service.computeOnSite(
                          entriesSnap.data ?? [],
                        );
                        return StreamBuilder<List<SecurityContractor>>(
                          stream: _service.watchContractors(),
                          builder: (context, contractorSnap) {
                            return SafeBottomBar(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 8, 16, 12),
                              child: FilledButton(
                                onPressed: _submitting
                                    ? null
                                    : () => _submit(
                                          settings,
                                          gate,
                                          denySnap.data ?? [],
                                          vehicleSnap.data ?? [],
                                          onSite,
                                          contractorSnap.data ?? [],
                                        ),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                  backgroundColor: kBrandOrange,
                                ),
                                child: _submitting
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(_submitLabel),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }

  List<Widget> _buildFlowFields({
    required BuildContext context,
    required SecuritySettings settings,
    required bool licenceRequired,
    required List<SecurityContractor> contractors,
    required List<String> hostSuggestions,
    required List<String> companySuggestions,
    required List<SecurityEntry> onSite,
    required int recorded,
    required bool discrepancy,
    required bool partial,
  }) {
    return switch (_flowKind) {
      _GateFlowKind.visitorEntry => _visitorEntryFields(
          settings: settings,
          licenceRequired: licenceRequired,
          contractors: contractors,
          hostSuggestions: hostSuggestions,
          companySuggestions: companySuggestions,
        ),
      _GateFlowKind.visitorExit => _visitorExitFields(
          onSite: onSite,
          recorded: recorded,
          discrepancy: discrepancy,
          partial: partial,
        ),
      _GateFlowKind.companyCarExit => _companyCarExitFields(),
      _GateFlowKind.companyCarReturn => _companyCarReturnFields(),
    };
  }

  List<Widget> _visitorEntryFields({
    required SecuritySettings settings,
    required bool licenceRequired,
    required List<SecurityContractor> contractors,
    required List<String> hostSuggestions,
    required List<String> companySuggestions,
  }) {
    return [
      const SizedBox(height: 16),
      DropdownButtonFormField<SecurityEntryType>(
        key: ValueKey(_entryType),
        initialValue: _entryType,
        decoration: const InputDecoration(
          labelText: 'Entry type',
          border: OutlineInputBorder(),
        ),
        items: SecurityEntryType.values
            .where(
              (t) =>
                  t != SecurityEntryType.companyCar &&
                  t != SecurityEntryType.onFootVisitor,
            )
            .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
            .toList(),
        onChanged: (v) {
          if (v != null) {
            setState(() {
              _entryType = v;
              if (v != SecurityEntryType.contractor) _contractor = null;
            });
          }
        },
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _licenceUnavailable ? null : _scanDriverLicence,
              icon: Icon(
                _driverLicence != null
                    ? Icons.check_circle
                    : Icons.badge_outlined,
                color: _driverLicence != null ? Colors.green : null,
              ),
              label: Text(
                licenceRequired ? "Scan driver's licence *" : "Scan driver's licence",
              ),
            ),
          ),
        ],
      ),
      if (!licenceRequired) ...[
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _licenceUnavailable,
          onChanged: (v) => setState(() {
            _licenceUnavailable = v ?? false;
            if (_licenceUnavailable) _driverLicence = null;
          }),
          title: const Text("Driver's licence not available (flags entry)"),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        if (_licenceUnavailable)
          TextField(
            controller: _licenceMissingNoteCtrl,
            decoration: const InputDecoration(
              labelText: 'Why not scanned? *',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
      ],
      const SizedBox(height: 12),
      _OccupantStepper(
        label: 'Occupants entering',
        value: _occupantCount,
        onChanged: (v) => setState(() => _occupantCount = v),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _driverCtrl,
        decoration: const InputDecoration(
          labelText: 'Driver name *',
          border: OutlineInputBorder(),
          helperText: 'Filled from licence scan when available',
        ),
      ),
      const SizedBox(height: 12),
      SecuritySuggestionField(
        controller: _hostCtrl,
        label: 'Host or department',
        suggestions: hostSuggestions,
      ),
      const SizedBox(height: 12),
      SecuritySuggestionField(
        controller: _companyCtrl,
        label: 'Company',
        suggestions: companySuggestions,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _purposeCtrl,
        decoration: InputDecoration(
          labelText: settings.purposeOfVisitRequired
              ? 'Purpose of visit *'
              : 'Purpose of visit',
          border: const OutlineInputBorder(),
        ),
        maxLines: 2,
      ),
      if (_entryType == SecurityEntryType.contractor) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<SecurityContractor>(
          key: ValueKey(_contractor?.id),
          initialValue: _contractor,
          decoration: const InputDecoration(
            labelText: 'Contractor *',
            border: OutlineInputBorder(),
          ),
          items: contractors
              .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
              .toList(),
          onChanged: (c) => setState(() => _contractor = c),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addContractor,
            icon: const Icon(Icons.add),
            label: const Text('Add contractor'),
          ),
        ),
      ],
      const SizedBox(height: 12),
      TextField(
        controller: _overrideCtrl,
        decoration: const InputDecoration(
          labelText: 'Override reason (if disc/licence expired)',
          border: OutlineInputBorder(),
        ),
        maxLines: 2,
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _pickPhoto,
        icon: const Icon(Icons.camera_alt_outlined),
        label: Text(
          _photoPaths.isEmpty
              ? 'Add photo (optional)'
              : '${_photoPaths.length} photo(s) attached',
        ),
      ),
    ];
  }

  List<Widget> _visitorExitFields({
    required List<SecurityEntry> onSite,
    required int recorded,
    required bool discrepancy,
    required bool partial,
  }) {
    return [
      const SizedBox(height: 16),
      if (_onSiteEntry != null) ...[
        Card(
          color: kBrandOrange.withValues(alpha: 0.1),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Matched on-site vehicle',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  _onSiteEntry!.vehicleReg ?? '—',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  _onSiteEntry!.driverName ??
                      _onSiteEntry!.contractorName ??
                      '—',
                ),
                const SizedBox(height: 12),
                Text('Recorded on entry: $recorded occupant'
                    '${recorded == 1 ? '' : 's'}'),
                const SizedBox(height: 8),
                _OccupantStepper(
                  label: 'Leaving now',
                  value: _occupantsLeaving,
                  onChanged: (v) => setState(() => _occupantsLeaving = v),
                ),
                if (partial)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${recorded - _occupantsLeaving} may still be on site — '
                      'exit will be flagged.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                if (discrepancy) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _discrepancyNoteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Discrepancy note *',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ],
            ),
          ),
        ),
      ] else if (_disc != null) ...[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'No on-site record for '
              '${SecurityVehicle.normalizeReg(_disc!.vehicleReg)}. '
              'Pick a vehicle below or switch to ENTRY.',
            ),
          ),
        ),
      ],
      const SizedBox(height: 12),
      Text(
        'On-site vehicles (manual match)',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: 8),
      if (onSite.isEmpty) const Text('No vehicles currently on site.'),
      ...onSite.map((e) {
        final selected = _onSiteEntry?.id == e.id;
        return Card(
          color: selected ? kBrandOrange.withValues(alpha: 0.12) : null,
          child: ListTile(
            title: Text(e.vehicleReg ?? '—'),
            subtitle: Text(
              '${e.driverName ?? e.contractorName ?? '—'} · '
              '${e.entryType?.label ?? ''}',
            ),
            trailing: selected
                ? const Icon(Icons.check_circle, color: kBrandOrange)
                : null,
            onTap: () => _selectOnSite(e),
          ),
        );
      }),
    ];
  }

  List<Widget> _companyCarExitFields() {
    return [
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: _scanDriverLicence,
        icon: Icon(
          _driverLicence != null ? Icons.check_circle : Icons.badge_outlined,
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
                ),
          helperText: _resolvedEmployee?.displayName ??
              'Clock number on driver ID badge',
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
        ),
        maxLines: 2,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _odometerCtrl,
        decoration: InputDecoration(
          labelText: 'Exit odometer (km) *',
          border: const OutlineInputBorder(),
          helperText: _companyVehicle?.odometerLast != null
              ? 'Last recorded: '
                  '${_companyVehicle!.odometerLast!.toStringAsFixed(0)} km'
              : 'Read odometer in vehicle',
        ),
        keyboardType: TextInputType.number,
      ),
    ];
  }

  List<Widget> _companyCarReturnFields() {
    return [
      const SizedBox(height: 16),
      TextField(
        controller: _odometerCtrl,
        decoration: InputDecoration(
          labelText: 'Return odometer (km) *',
          border: const OutlineInputBorder(),
          helperText: _companyVehicle?.odometerLast != null
              ? 'Last recorded: '
                  '${_companyVehicle!.odometerLast!.toStringAsFixed(0)} km'
              : 'Read odometer in vehicle',
        ),
        keyboardType: TextInputType.number,
      ),
    ];
  }
}

class _DirectionPanel extends StatelessWidget {
  const _DirectionPanel({
    required this.direction,
    required this.autoDirection,
    required this.overridden,
    required this.hint,
    required this.onChanged,
    this.onResetAuto,
  });

  final SecurityDirection direction;
  final SecurityDirection? autoDirection;
  final bool overridden;
  final String? hint;
  final ValueChanged<SecurityDirection> onChanged;
  final VoidCallback? onResetAuto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: direction == SecurityDirection.in_
              ? Colors.green.shade600
              : Colors.deepOrange.shade600,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Direction',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            SegmentedButton<SecurityDirection>(
              segments: const [
                ButtonSegment(
                  value: SecurityDirection.in_,
                  label: Text('ENTRY'),
                  icon: Icon(Icons.login),
                ),
                ButtonSegment(
                  value: SecurityDirection.out,
                  label: Text('EXIT'),
                  icon: Icon(Icons.logout),
                ),
              ],
              selected: {direction},
              onSelectionChanged: (s) => onChanged(s.first),
            ),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(
                hint!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
            if (overridden && autoDirection != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.edit, size: 14, color: Colors.orange.shade800),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Changed manually (auto was '
                      '${autoDirection!.label.toUpperCase()})',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                  if (onResetAuto != null)
                    TextButton(
                      onPressed: onResetAuto,
                      child: const Text('Use auto'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DiscSummaryCard extends StatelessWidget {
  const _DiscSummaryCard({required this.disc});

  final ParsedDocument disc;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'From disc scan',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            if (disc.vehicleReg != null)
              Text('Reg: ${SecurityVehicle.normalizeReg(disc.vehicleReg)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            if (disc.expiryDate != null)
              Text(
                'Disc expiry: '
                '${disc.expiryDate!.toLocal().toString().split(' ').first}',
              ),
            if (disc.vehicleMake != null) Text('Make: ${disc.vehicleMake}'),
            if (disc.vehicleModel != null) Text('Model: ${disc.vehicleModel}'),
            if (disc.vehicleColour != null)
              Text('Colour: ${disc.vehicleColour}'),
          ],
        ),
      ),
    );
  }
}

class _CompanyCarCard extends StatelessWidget {
  const _CompanyCarCard({
    required this.vehicle,
    required this.discDamaged,
    required this.onDiscDamagedChanged,
    required this.vehicles,
    required this.selected,
    required this.onSelect,
  });

  final SecurityVehicle vehicle;
  final bool discDamaged;
  final ValueChanged<bool> onDiscDamagedChanged;
  final List<SecurityVehicle> vehicles;
  final SecurityVehicle? selected;
  final ValueChanged<SecurityVehicle?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: kBrandOrange.withValues(alpha: 0.08),
          child: ListTile(
            leading: const Icon(Icons.directions_car, color: kBrandOrange),
            title: Text(vehicle.vehicleReg),
            subtitle: Text(vehicle.description ?? 'Registered company car'),
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: discDamaged,
          onChanged: (v) => onDiscDamagedChanged(v ?? false),
          title: const Text('Disc damaged / cannot scan'),
          subtitle: const Text('Select company car manually — flagged'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        if (discDamaged)
          DropdownButtonFormField<SecurityVehicle>(
            key: ValueKey(selected?.id),
            initialValue: selected,
            decoration: const InputDecoration(
              labelText: 'Company car *',
              border: OutlineInputBorder(),
            ),
            items: vehicles
                .map(
                  (v) => DropdownMenuItem(
                    value: v,
                    child: Text(v.vehicleReg),
                  ),
                )
                .toList(),
            onChanged: onSelect,
          ),
      ],
    );
  }
}

class _OccupantStepper extends StatelessWidget {
  const _OccupantStepper({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label),
        const SizedBox(width: 12),
        IconButton(
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text('$value', style: Theme.of(context).textTheme.titleMedium),
        IconButton(
          onPressed: value < 20 ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}