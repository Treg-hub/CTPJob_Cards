import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../utils/persona_audit.dart';
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
import '../models/security_scan_result.dart';
import '../models/security_vehicle_trip.dart';
import '../providers/security_provider.dart';
import '../services/security_service.dart';
import '../theme/app_theme.dart';
import '../utils/screen_insets.dart';
import '../utils/security_error_messages.dart';
import '../widgets/security_gate_compact_header.dart';
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
  // Optional free-text detail for the override reason below (required only
  // when the reason is "Other").
  final _overrideCtrl = TextEditingController();
  final _discrepancyNoteCtrl = TextEditingController();
  final _clockNoCtrl = TextEditingController();
  final _odometerCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  // Manual vehicle reg when a visitor's disc can't be scanned (damaged/dirty).
  final _manualRegCtrl = TextEditingController();

  ParsedDocument? _disc;
  ParsedDocument? _driverLicence;
  SecurityEntry? _onSiteEntry;
  SecurityVehicle? _companyVehicle;
  SecurityEntry? _openCompanyCarExit;
  SecurityContractor? _contractor;
  SecurityEntryType _entryType = SecurityEntryType.visitor;

  SecurityDirection _direction = SecurityDirection.in_;
  SecurityDirection? _autoDirection;
  bool _directionOverridden = false;

  bool _licenceUnavailable = false;
  // Single structured reason covering both "licence not scanned" and an
  // expired disc/licence override. One of [_overrideReasons] or null.
  String? _overrideReason;
  static const List<String> _overrideReasons = [
    'No licence',
    'Disc expired',
    'Licence expired',
    'Other',
  ];
  bool _discDamaged = false;
  int _occupantCount = 1;
  int _occupantsLeaving = 1;
  int _occupantsReturning = 1;
  final List<String> _photoPaths = [];
  Employee? _resolvedEmployee;
  bool _resolvingEmployee = false;
  bool _submitting = false;
  bool _formReady = false;
  bool _openingScanner = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapFlow());
  }

  @override
  void dispose() {
    _driverCtrl.dispose();
    _hostCtrl.dispose();
    _companyCtrl.dispose();
    _purposeCtrl.dispose();
    _overrideCtrl.dispose();
    _discrepancyNoteCtrl.dispose();
    _clockNoCtrl.dispose();
    _odometerCtrl.dispose();
    _addressCtrl.dispose();
    _manualRegCtrl.dispose();
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
    List<SecurityEntry>? allRecent,
  }) {
    final reg = SecurityVehicle.normalizeReg(disc.vehicleReg);
    final onSiteList = onSite ?? [];
    final vehicleList = vehicles ?? [];
    final match = _service.findOnSiteByReg(onSiteList, reg);
    final company = _service.findCompanyVehicle(vehicleList, reg);
    final openExit = company != null
        ? _service.findOpenCompanyCarExit(allRecent ?? [], reg)
        : null;
    final suggested =
        match != null ? SecurityDirection.out : SecurityDirection.in_;

    setState(() {
      _disc = disc;
      _onSiteEntry = match;
      _companyVehicle = company;
      _openCompanyCarExit = openExit;
      _autoDirection = suggested;
      if (!_directionOverridden) {
        _direction = suggested;
      }
      _occupantsLeaving = match?.occupantCount ?? 1;
      _occupantsReturning = openExit?.occupantCount ?? 1;
      _discrepancyNoteCtrl.clear();
      if (company != null) {
        _discDamaged = false;
        _occupantCount = 1;
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

  bool get _needsLicenceScan => switch (_flowKind) {
        _GateFlowKind.visitorEntry =>
          !_licenceUnavailable && _driverLicence == null,
        _GateFlowKind.companyCarExit => _driverLicence == null,
        _ => false,
      };

  bool get _showLicenceInHeader => switch (_flowKind) {
        _GateFlowKind.visitorEntry => true,
        _GateFlowKind.companyCarExit => true,
        _ => false,
      };

  Future<void> _bootstrapFlow() async {
    if (!mounted) return;
    final gate = ref.read(selectedSecurityGateProvider);
    if (gate == null) {
      setState(() => _formReady = true);
      return;
    }
    await _openDiscScanner();
  }

  Future<List<SecurityEntry>> _loadRecentEntries() async {
    return _service.watchRecentEntries(limit: 200).first;
  }

  Future<List<SecurityVehicle>> _loadVehicles() async {
    return _service.watchVehicles().first;
  }

  Future<void> _openDiscScanner() async {
    if (_openingScanner || !mounted) return;
    _openingScanner = true;
    SecurityScanResult? result;
    try {
      result = await Navigator.push<SecurityScanResult>(
        context,
        MaterialPageRoute(
          builder: (_) => const SecurityDocumentScanScreen(
            title: 'Scan Licence Disc',
            expectedType: SecurityDocumentType.licenseDisc,
            autoConfirmOnDetect: true,
            structuredResult: true,
            showCantScanDisc: true,
          ),
        ),
      );
    } finally {
      // Release the re-entrancy guard BEFORE the chained licence scan below:
      // _openLicenceScanner() also checks `_openingScanner` and would bail
      // while this is still true, so the disc→licence auto-transition never
      // fired on the INITIAL scan (it only worked from _rescanDisc, which
      // doesn't set the guard).
      _openingScanner = false;
    }
    if (!mounted) return;

    if (result == null) {
      setState(() => _formReady = true);
      return;
    }

    if (result.cantScan) {
      setState(() {
        _disc = null;
        _discDamaged = true;
        _formReady = true;
      });
      return;
    }

    if (result.hasDocument) {
      final entries = await _loadRecentEntries();
      final onSite = _service.computeOnSite(entries);
      final vehicles = await _loadVehicles();
      if (!mounted) return;
      _applyDiscContext(
        disc: result.document!,
        onSite: onSite,
        vehicles: vehicles,
        allRecent: entries,
      );
      await _maybeChainLicenceScan();
    }

    if (mounted) setState(() => _formReady = true);
  }

  Future<void> _maybeChainLicenceScan() async {
    if (!_needsLicenceScan || !mounted) return;
    await _openLicenceScanner();
  }

  Future<void> _openLicenceScanner() async {
    if (_openingScanner || !mounted) return;
    // Visitor entry can always skip the licence scan — a driver may genuinely
    // have no licence. The `driverLicenceScanRequired` setting no longer hard-
    // blocks; instead it makes a REASON mandatory (validated in _submit).
    // Company car exit still requires a licence (allowSkip stays false).
    final allowSkip = _flowKind == _GateFlowKind.visitorEntry;

    _openingScanner = true;
    try {
      final result = await Navigator.push<SecurityScanResult>(
        context,
        MaterialPageRoute(
          builder: (_) => SecurityDocumentScanScreen(
            title: "Scan Driver's Licence",
            expectedType: SecurityDocumentType.driverLicence,
            autoConfirmOnDetect: true,
            structuredResult: true,
            allowSkip: allowSkip,
            skipLabel: "Licence not available",
          ),
        ),
      );
      if (!mounted) return;

      if (result == null) return;

      if (result.skipped && allowSkip) {
        setState(() {
          _licenceUnavailable = true;
          // Pre-select the most common reason; security can change it below.
          _overrideReason ??= 'No licence';
        });
        return;
      }

      if (result.hasDocument) {
        final doc = result.document!;
        setState(() {
          _driverLicence = doc;
          _licenceUnavailable = false;
          if (_overrideReason == 'No licence') _overrideReason = null;
          if (doc.fullName != null && _driverCtrl.text.isEmpty) {
            _driverCtrl.text = doc.fullName!;
          }
        });
      }
    } finally {
      _openingScanner = false;
    }
  }

  Future<void> _rescanDisc(
    List<SecurityEntry> onSite,
    List<SecurityVehicle> vehicles,
    List<SecurityEntry> allRecent,
  ) async {
    final result = await Navigator.push<SecurityScanResult>(
      context,
      MaterialPageRoute(
        builder: (_) => const SecurityDocumentScanScreen(
          title: 'Scan Licence Disc',
          expectedType: SecurityDocumentType.licenseDisc,
          autoConfirmOnDetect: true,
          structuredResult: true,
          showCantScanDisc: true,
        ),
      ),
    );
    if (!mounted) return;

    if (result == null) return;

    if (result.cantScan) {
      setState(() {
        _disc = null;
        _discDamaged = true;
        _companyVehicle = null;
        _openCompanyCarExit = null;
        _onSiteEntry = null;
        _autoDirection = null;
      });
      return;
    }

    if (result.hasDocument) {
      _applyDiscContext(
        disc: result.document!,
        onSite: onSite,
        vehicles: vehicles,
        allRecent: allRecent,
      );
      await _maybeChainLicenceScan();
    }
  }

  void _showCompanyRegistryDialog(
    String scannedReg,
    List<String> registeredCompanyCars,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Not a registered company car'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Disc plate: $scannedReg',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This reg is not in the company car register, or the vehicle is '
                'inactive. Job Cards will treat this as a visitor/contractor vehicle.',
              ),
              const SizedBox(height: 8),
              const Text(
                'In Pulse: Settings → Site Security → Company vehicles — add the '
                'plate exactly as on the disc.',
              ),
              if (registeredCompanyCars.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Registered company cars (${registeredCompanyCars.length}):',
                  style: Theme.of(ctx).textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                Text(registeredCompanyCars.join(', ')),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
    if (!guardPersonaSubmit(context)) return;
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
        await _submitCompanyCarExit(gate, settings: settings);
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
    if (!guardPersonaSubmit(context)) return;
    final emp = currentEmployee!;
    final actor = resolveWriteActor(emp)!;

    if (!gate.allowsEntryType(_entryType)) {
      _showError('This gate does not allow ${_entryType.label} entries.');
      return;
    }

    final manualReg = SecurityVehicle.normalizeReg(_manualRegCtrl.text);
    if (_disc == null && !_discDamaged) {
      _showError('Scan the vehicle licence disc first.');
      return;
    }
    if (_disc == null && manualReg.isEmpty) {
      _showError(
        'Enter the vehicle registration — the disc could not be scanned.',
      );
      return;
    }

    final licenceCaptured = _driverLicence != null;
    // A missing licence no longer hard-blocks — but a reason is mandatory.
    if (!licenceCaptured && !_licenceUnavailable) {
      _showError(
        "Scan the driver's licence, or tick \"Licence not scanned\" and choose a reason.",
      );
      return;
    }
    if (!licenceCaptured && _overrideReason == null) {
      _showError('Choose a reason for proceeding without a scanned licence.');
      return;
    }

    final reg = _disc != null
        ? SecurityVehicle.normalizeReg(_disc!.vehicleReg)
        : manualReg;
    if (reg.isEmpty) {
      _showError(_disc != null
          ? 'Could not read registration from the scanned disc.'
          : 'Enter the vehicle registration.');
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

    if (compliance.warn && _overrideReason == null) {
      _showError(
        '${compliance.message}. Choose an override reason to continue.',
      );
      return;
    }
    // "Other" requires a written detail so an audit note isn't just "Other".
    if (_overrideReason == 'Other' && _overrideCtrl.text.trim().isEmpty) {
      _showError('Add a short detail for the "Other" reason.');
      return;
    }

    final sessionId = const Uuid().v4();
    final host = _hostCtrl.text.trim();
    final company = _companyCtrl.text.trim();
    final overrideDetail = _overrideCtrl.text.trim();
    final complianceNotes = <String>[
      if (compliance.message != null) compliance.message!,
      if (_licenceUnavailable)
        'Driver licence not scanned'
            '${_overrideReason != null ? ' ($_overrideReason)' : ''}'
            '${overrideDetail.isNotEmpty ? ': $overrideDetail' : ''}',
    ];

    // Re-entry without a prior exit: the reg is already shown on-site, so its
    // previous OUT was skipped. Don't hold up the line — auto-close the stale
    // open with a big flag (flagged_for_review) and continue with this entry.
    final autoClosedStale = _onSiteEntry != null;

    setState(() => _submitting = true);
    try {
      if (_onSiteEntry != null) {
        try {
          await _service.forceSignOut(
            onSiteEntry: _onSiteEntry!,
            reason: 'Auto-closed on re-entry — previous exit was not captured',
            loggedByClockNo: actor.clockNo,
            loggedByName: emp.name,
            autoClosedOnReentry: true,
          );
        } catch (_) {
          // Best-effort — never block the new entry on the auto-close.
        }
      }
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
          'logged_by_clock_no': actor.clockNo,
          'logged_by_name': emp.name,
          'logged_at': DateTime.now().toIso8601String(),
          'disc_scan_captured': _disc != null,
          if (_disc == null) 'disc_scan_missing_flag': true,
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
          if (_overrideReason != null) 'override_reason': _overrideReason,
          if (overrideDetail.isNotEmpty) 'override_note': overrideDetail,
        },
        photoLocalPaths: _photoPaths,
      );

      if (host.isNotEmpty) {
        await _service.ensureLookupOption(
          type: 'host',
          value: host,
          createdByClockNo: actor.clockNo,
        );
      }
      if (company.isNotEmpty) {
        await _service.ensureLookupOption(
          type: 'company',
          value: company,
          createdByClockNo: actor.clockNo,
        );
      }

      if (!mounted) return;
      _showSuccess(
        result,
        autoClosedStale
            ? 'Entry logged — previous exit was missing, auto-closed & flagged for review'
            : 'Entry logged',
      );
    } catch (e) {
      _showError(friendlySecurityError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitVisitorExit(
    SecurityGate gate,
    List<SecurityEntry> onSite,
  ) async {
    if (!guardPersonaSubmit(context)) return;
    final emp = currentEmployee!;
    final actor = resolveWriteActor(emp)!;

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
        loggedByClockNo: actor.clockNo,
        loggedByName: emp.name,
        discScan: _disc,
        occupantsLeaving: _occupantsLeaving,
        occupantDiscrepancyNote: discrepancy
            ? _discrepancyNoteCtrl.text.trim()
            : null,
        discScanMissingFlag: _disc == null,
        photoLocalPaths: _photoPaths,
      );

      if (!mounted) return;
      final partial = _occupantsLeaving < recorded;
      _showSuccess(
        result,
        partial ? 'Exit logged (partial exit flagged)' : 'Exit logged',
        partial: partial,
      );
    } catch (e) {
      _showError(friendlySecurityError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitCompanyCarExit(
    SecurityGate gate, {
    SecuritySettings? settings,
  }) async {
    if (!guardPersonaSubmit(context)) return;
    final emp = currentEmployee!;
    final actor = resolveWriteActor(emp)!;

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

    // Expiry compliance — a company car must not leave on an expired disc or
    // licence without a recorded override reason (mirrors the visitor entry).
    final compliance = _service.evaluateCompliance(
      entryType: SecurityEntryType.companyCar,
      discExpiry: _disc?.expiryDate,
      idExpiry: _driverLicence?.expiryDate,
      warnDays: settings?.licenseExpiryWarnDays ?? 0,
    );
    if (compliance.blocked) {
      _showError(compliance.message ?? 'Vehicle compliance failed.');
      return;
    }
    if (compliance.warn && _overrideReason == null) {
      _showError(
        '${compliance.message}. Choose an override reason to continue.',
      );
      return;
    }
    if (_overrideReason == 'Other' && _overrideCtrl.text.trim().isEmpty) {
      _showError('Add a short detail for the "Other" reason.');
      return;
    }

    final odometer = double.tryParse(_odometerCtrl.text.trim());
    if (odometer == null) {
      _showError('Enter a valid exit odometer reading (km).');
      return;
    }

    final clockRequired = settings?.employeeClockRequired ?? false;
    final clockNo = _clockNoCtrl.text.trim();
    if (clockRequired || clockNo.isNotEmpty) {
      await _resolveEmployeeFromClock();
    }
    if (clockRequired && clockNo.isEmpty) {
      _showError('Enter the employee clock number.');
      return;
    }
    if (clockRequired && _resolvedEmployee == null) {
      _showError('No employee found for that clock number.');
      return;
    }

    final driverName = _resolvedEmployee?.name ??
        _driverLicence?.fullName ??
        _driverCtrl.text.trim();
    if (driverName.isEmpty) {
      _showError('Driver name is required (from licence scan).');
      return;
    }

    final employeeNotInDirectory =
        clockNo.isNotEmpty && _resolvedEmployee == null;

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
        'driver_name': driverName,
        'disc_scan_captured': _disc != null,
        'disc_scan_missing_flag': _discDamaged || _disc == null,
        if (_disc?.expiryDate != null)
          'disc_expiry': _disc!.expiryDate!.toIso8601String(),
        if (_disc?.vehicleMake != null) 'vehicle_make': _disc!.vehicleMake,
        if (clockNo.isNotEmpty) 'employee_clock_no': clockNo,
        if (_resolvedEmployee != null)
          'employee_name': _resolvedEmployee!.name
        else if (clockNo.isNotEmpty)
          'employee_name': driverName,
        if (employeeNotInDirectory) 'employee_not_in_directory': true,
        'purpose': _purposeCtrl.text.trim(),
        'destination_address': _addressCtrl.text.trim(),
        'odometer_start': odometer,
        'occupant_count': _occupantCount,
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
        'logged_by_clock_no': actor.clockNo,
        'logged_by_name': emp.name,
        'logged_at': DateTime.now().toIso8601String(),
        if (compliance.message != null) 'compliance_notes': compliance.message,
        if (_overrideReason != null) 'override_reason': _overrideReason,
        if (_overrideCtrl.text.trim().isNotEmpty)
          'override_note': _overrideCtrl.text.trim(),
      };

      final result =
          await _service.createEntry(data: entryData, photoLocalPaths: _photoPaths);

      // Trip + odometer are durably queued (fire-and-forget in the service),
      // so they survive offline and never block this submit on a server ack.
      await _service.recordCompanyCarTrip(
        trip: SecurityVehicleTrip(
          id: '',
          vehicleReg: _companyVehicle!.vehicleReg,
          gateId: gate.id,
          direction: SecurityDirection.out,
          entryId: result.id,
          loggedAt: DateTime.now(),
          driverName: driverName,
          odometerStart: odometer,
          sessionId: sessionId,
        ),
        actorClockNo: actor.clockNo,
        actorName: emp.name,
      );
      await _service.updateCompanyVehicleOdometer(
        vehicleId: _companyVehicle!.id,
        odometer: odometer,
      );

      if (!mounted) return;
      _showSuccess(
        result,
        employeeNotInDirectory
            ? 'Company car exit logged (clock not in employee directory)'
            : 'Company car exit logged',
      );
    } catch (e) {
      _showError(friendlySecurityError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitCompanyCarReturn(SecurityGate gate) async {
    if (!guardPersonaSubmit(context)) return;
    final emp = currentEmployee!;
    final actor = resolveWriteActor(emp)!;

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

    final recordedOccupants = _openCompanyCarExit?.occupantCount ?? 1;
    final occupantDiscrepancy =
        _openCompanyCarExit != null && _occupantsReturning != recordedOccupants;
    if (occupantDiscrepancy && _discrepancyNoteCtrl.text.trim().isEmpty) {
      _showError(
        recordedOccupants > _occupantsReturning
            ? 'Explain why $recordedOccupants occupant(s) left but only '
                '$_occupantsReturning are returning.'
            : 'Explain why more people are returning than left.',
      );
      return;
    }

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
        if (_openCompanyCarExit != null) ...{
          'occupant_count': recordedOccupants,
          // Reused field: on a company-car RETURN entry this means
          // "occupants present now", not "leaving" — same generic field
          // SecurityEntry already uses for the visitor-exit discrepancy
          // check (see security_entry.dart occupantsLeaving doc comment).
          'occupants_leaving': _occupantsReturning,
          'occupant_discrepancy': occupantDiscrepancy,
          if (occupantDiscrepancy)
            'occupant_discrepancy_note': _discrepancyNoteCtrl.text.trim(),
        },
        'logged_by_clock_no': actor.clockNo,
        'logged_by_name': emp.name,
        'logged_at': DateTime.now().toIso8601String(),
      };

      final result =
          await _service.createEntry(data: entryData, photoLocalPaths: _photoPaths);

      // Trip + odometer are durably queued (fire-and-forget in the service).
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
        actorClockNo: actor.clockNo,
        actorName: emp.name,
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
      _showError(friendlySecurityError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _logDenyBlocked(
    SecurityGate gate,
    String reg,
    SecurityDenyEntry deny,
    Employee emp,
  ) async {
    final actor = resolveWriteActor(emp)!;
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
        'logged_by_clock_no': actor.clockNo,
        'logged_by_name': actor.name,
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

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(securitySettingsProvider).valueOrNull;
    final gate = ref.watch(selectedSecurityGateProvider);

    if (settings == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_formReady && gate != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Vehicle at Gate')),
        body: const SizedBox.shrink(),
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

                              final scannedReg = _disc != null
                                  ? SecurityVehicle.normalizeReg(_disc!.vehicleReg)
                                  : null;
                              final companyCarRegs = vehicles
                                  .where((v) => v.isCompanyCar && v.active)
                                  .map((v) => v.vehicleReg)
                                  .toList();

                              return ListView(
                                padding: EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  ScreenInsets.scrollBottomInHomeShell(),
                                ),
                                children: [
                                  if (gate == null)
                                    Card(
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text('No gate selected.'),
                                            const SizedBox(height: 8),
                                            OutlinedButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              child: const Text('Choose a gate'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  SecurityGateCompactHeader(
                                    direction: _direction,
                                    autoDirection: _autoDirection,
                                    directionOverridden: _directionOverridden,
                                    flowLabel: _flowLabel,
                                    onDirectionChanged: _setDirection,
                                    onResetAuto: _directionOverridden
                                        ? _resetDirectionToAuto
                                        : null,
                                    disc: _disc,
                                    driverLicence: _driverLicence,
                                    companyVehicle: _companyVehicle,
                                    showLicenceRow: _showLicenceInHeader,
                                    onRescanDisc: gate == null
                                        ? null
                                        : () => _rescanDisc(
                                              onSite,
                                              vehicles,
                                              entriesSnap.data ?? [],
                                            ),
                                    onRescanLicence: _showLicenceInHeader
                                        ? _openLicenceScanner
                                        : null,
                                    onShowCompanyRegistryInfo:
                                        scannedReg != null &&
                                                _companyVehicle == null
                                            ? () => _showCompanyRegistryDialog(
                                                  scannedReg,
                                                  companyCarRegs,
                                                )
                                            : null,
                                  ),
                                  if (_disc == null) ...[
                                    const SizedBox(height: 8),
                                    _CompanyCarManualSection(
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

  /// Add-photo button, shared by the visitor-entry and company-car flows.
  Widget _photoButton() {
    return OutlinedButton.icon(
      onPressed: _pickPhoto,
      icon: const Icon(Icons.camera_alt_outlined),
      label: Text(
        _photoPaths.isEmpty
            ? 'Add photo (optional)'
            : '${_photoPaths.length} photo(s) attached',
      ),
    );
  }

  /// Reason / override chips + optional detail, shared by visitor entry and
  /// company-car exit. [includeNoLicence] adds the "No licence" option (visitor
  /// entry only — a company-car driver must carry a licence).
  List<Widget> _overrideReasonSection({required bool includeNoLicence}) {
    final reasons = includeNoLicence
        ? _overrideReasons
        : _overrideReasons.where((r) => r != 'No licence').toList();
    return [
      const SizedBox(height: 16),
      Text('Reason / override', style: Theme.of(context).textTheme.titleSmall),
      Text(
        includeNoLicence
            ? 'Required when the licence is not scanned, or the disc / licence is expired.'
            : 'Required when the disc or licence is expired.',
        style: const TextStyle(fontSize: 12.5, color: Colors.grey),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: reasons.map((reason) {
          return ChoiceChip(
            label: Text(reason),
            selected: _overrideReason == reason,
            onSelected: (sel) => setState(() {
              _overrideReason = sel ? reason : null;
              if (includeNoLicence && reason == 'No licence') {
                _licenceUnavailable = sel;
                if (sel) _driverLicence = null;
              }
            }),
          );
        }).toList(),
      ),
      if (_overrideReason != null) ...[
        const SizedBox(height: 8),
        TextField(
          controller: _overrideCtrl,
          decoration: InputDecoration(
            labelText:
                _overrideReason == 'Other' ? 'Detail *' : 'Detail (optional)',
            border: const OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
      ],
    ];
  }

  /// Manual registration entry shown on a visitor entry when the disc could
  /// not be scanned (damaged/dirty). Company cars use the registry dropdown.
  List<Widget> _manualRegField() {
    if (!_discDamaged || _disc != null || _companyVehicle != null) return [];
    return [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
        ),
        child: const Text(
          "Disc couldn't be scanned — type the registration. The entry is flagged as a missing disc scan.",
          style: TextStyle(fontSize: 12.5),
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _manualRegCtrl,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(
          labelText: 'Vehicle registration (manual) *',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
    ];
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
      _GateFlowKind.companyCarExit => _companyCarExitFields(settings),
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
      ..._manualRegField(),
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
      const SizedBox(height: 8),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _licenceUnavailable,
        onChanged: (v) => setState(() {
          _licenceUnavailable = v ?? false;
          if (_licenceUnavailable) {
            _driverLicence = null;
            _overrideReason ??= 'No licence';
          } else if (_overrideReason == 'No licence') {
            _overrideReason = null;
          }
        }),
        title: const Text("Driver's licence not scanned"),
        subtitle: Text(
          licenceRequired
              ? 'Pick a reason below to proceed without it'
              : 'Pick a reason below',
        ),
        controlAffinity: ListTileControlAffinity.leading,
      ),
      const SizedBox(height: 16),
      Text(
        'Visitor details',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: 8),
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
      ..._overrideReasonSection(includeNoLicence: true),
      const SizedBox(height: 12),
      _photoButton(),
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
      const SizedBox(height: 12),
      _photoButton(),
    ];
  }

  List<Widget> _companyCarExitFields(SecuritySettings settings) {
    final clockRequired = settings.employeeClockRequired;
    return [
      const SizedBox(height: 12),
      TextField(
        controller: _clockNoCtrl,
        decoration: InputDecoration(
          labelText: clockRequired
              ? 'Employee clock number *'
              : 'Employee clock number',
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
              (clockRequired
                  ? 'Clock number on driver ID badge'
                  : 'Optional — saved even if not in employee list'),
        ),
        keyboardType: TextInputType.number,
        onSubmitted: (_) => _resolveEmployeeFromClock(),
      ),
      const SizedBox(height: 12),
      _OccupantStepper(
        label: 'Occupants leaving',
        value: _occupantCount,
        onChanged: (v) => setState(() => _occupantCount = v),
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
      ..._overrideReasonSection(includeNoLicence: false),
      const SizedBox(height: 12),
      _photoButton(),
    ];
  }

  List<Widget> _companyCarReturnFields() {
    final recorded = _openCompanyCarExit?.occupantCount ?? 1;
    final discrepancy = _openCompanyCarExit != null && _occupantsReturning != recorded;
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
      const SizedBox(height: 16),
      if (_openCompanyCarExit != null) ...[
        Text('Recorded on exit: $recorded occupant${recorded == 1 ? '' : 's'}'),
        const SizedBox(height: 8),
        _OccupantStepper(
          label: 'Returning now',
          value: _occupantsReturning,
          onChanged: (v) => setState(() => _occupantsReturning = v),
        ),
        if (discrepancy) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _occupantsReturning < recorded
                  ? '${recorded - _occupantsReturning} may still be out — exit will be flagged.'
                  : 'More occupants returning than left — flagged.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
            ),
          ),
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
      ] else
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            'No matching exit trip found for this vehicle — occupant count not tracked for this return.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      const SizedBox(height: 12),
      _photoButton(),
    ];
  }
}

class _CompanyCarManualSection extends StatelessWidget {
  const _CompanyCarManualSection({
    required this.discDamaged,
    required this.onDiscDamagedChanged,
    required this.vehicles,
    required this.selected,
    required this.onSelect,
  });

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
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: discDamaged,
          onChanged: (v) => onDiscDamagedChanged(v ?? false),
          title: const Text('Disc damaged / cannot scan'),
          subtitle: const Text('Select company car manually — flagged'),
          controlAffinity: ListTileControlAffinity.leading,
          visualDensity: VisualDensity.compact,
        ),
        if (discDamaged && vehicles.isNotEmpty)
          DropdownButtonFormField<SecurityVehicle>(
            key: ValueKey(selected?.id),
            initialValue: selected,
            decoration: const InputDecoration(
              labelText: 'Company car *',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: vehicles
                .map(
                  (v) => DropdownMenuItem(
                    value: v,
                    child: Text(
                      v.assignedDriver != null && v.assignedDriver!.isNotEmpty
                          ? '${v.vehicleReg} · ${v.assignedDriver}'
                          : v.vehicleReg,
                      style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                  ),
                )
                .toList(),
            selectedItemBuilder: (context) => vehicles
                .map(
                  (v) => Text(
                    v.assignedDriver != null && v.assignedDriver!.isNotEmpty
                        ? '${v.vehicleReg} · ${v.assignedDriver}'
                        : v.vehicleReg,
                    style: const TextStyle(fontWeight: FontWeight.w500),
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