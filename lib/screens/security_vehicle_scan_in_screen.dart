import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../main.dart' show currentEmployee;
import '../models/parsed_document.dart';
import '../models/security_contractor.dart';
import '../models/security_deny_entry.dart';
import '../models/security_entry.dart';
import '../models/security_gate.dart';
import '../models/security_settings.dart';
import '../models/security_vehicle.dart';
import '../providers/security_provider.dart';
import '../services/security_service.dart';
import '../theme/app_theme.dart';
import '../widgets/security_suggestion_field.dart';
import 'security_document_scan_screen.dart';

/// Vehicle scan-in: licence disc + driver licence + occupant count.
class SecurityVehicleScanInScreen extends ConsumerStatefulWidget {
  const SecurityVehicleScanInScreen({super.key});

  @override
  ConsumerState<SecurityVehicleScanInScreen> createState() =>
      _SecurityVehicleScanInScreenState();
}

class _SecurityVehicleScanInScreenState
    extends ConsumerState<SecurityVehicleScanInScreen> {
  final _service = SecurityService();
  final _driverCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _purposeCtrl = TextEditingController();
  final _overrideCtrl = TextEditingController();
  final _licenceMissingNoteCtrl = TextEditingController();

  SecurityEntryType _entryType = SecurityEntryType.visitor;
  ParsedDocument? _disc;
  ParsedDocument? _driverLicence;
  SecurityContractor? _contractor;
  bool _licenceUnavailable = false;
  int _occupantCount = 1;
  final List<String> _photoPaths = [];
  bool _submitting = false;

  @override
  void dispose() {
    _driverCtrl.dispose();
    _hostCtrl.dispose();
    _companyCtrl.dispose();
    _purposeCtrl.dispose();
    _overrideCtrl.dispose();
    _licenceMissingNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanDisc() async {
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
    setState(() => _disc = result);
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

  Future<void> _addContractor(List<SecurityContractor> contractors) async {
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

  Future<void> _submit(
    SecuritySettings settings,
    SecurityGate? gate,
    List<SecurityDenyEntry> denyList,
    List<SecurityVehicle> vehicles,
  ) async {
    final emp = currentEmployee;
    if (emp == null || gate == null) return;

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
      _showError(
        "Scan the driver's licence or mark it as unavailable.",
      );
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

    final companyVehicle = _service.findCompanyVehicle(vehicles, reg);
    if (companyVehicle != null &&
        (_entryType == SecurityEntryType.visitor ||
            _entryType == SecurityEntryType.contractor)) {
      _showError(
        '$reg is a registered company car. Use the Company Car flow instead.',
      );
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

      _service.logAudit(
        action: 'entry_created',
        actorClockNo: emp.clockNo,
        actorName: emp.name,
        details: {
          'entry_id': result.id,
          'entry_type': _entryType.value,
          'vehicle_reg': reg,
          'occupant_count': _occupantCount,
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.queuedOffline
                ? 'Entry queued offline (${result.entryNumber ?? result.id})'
                : 'Entry logged: ${result.entryNumber ?? result.id}',
          ),
          backgroundColor: kBrandOrange,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      _showError('Failed to log entry: $e');
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
        'driver_name': _driverCtrl.text.trim().isEmpty
            ? null
            : _driverCtrl.text.trim(),
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
        content: Text(
          '$reg is on the deny list.\n\nReason: ${deny.reason}',
        ),
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

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(securitySettingsProvider).valueOrNull;
    final gate = ref.watch(selectedSecurityGateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle Scan In')),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<SecurityDenyEntry>>(
              stream: _service.watchDenyList(),
              builder: (context, denySnap) {
                return StreamBuilder<List<String>>(
                  stream: _service.watchLookupSuggestions('host'),
                  builder: (context, hostSnap) {
                    return StreamBuilder<List<String>>(
                      stream: _service.watchLookupSuggestions('company'),
                      builder: (context, companySnap) {
                        return StreamBuilder<List<SecurityVehicle>>(
                          stream: _service.watchVehicles(),
                          builder: (context, vehicleSnap) {
                            return StreamBuilder<List<SecurityContractor>>(
                              stream: _service.watchContractors(),
                              builder: (context, contractorSnap) {
                                final denyList = denySnap.data ?? [];
                                final vehicles = vehicleSnap.data ?? [];
                                final contractors = contractorSnap.data ?? [];
                                final hostSuggestions = hostSnap.data ?? [];
                                final companySuggestions =
                                    companySnap.data ?? [];
                                final licenceRequired =
                                    settings.driverLicenceScanRequired;

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
                                    const Text(
                                      'Scan the licence disc on the vehicle. '
                                      "Driver's licence required when enabled in settings.",
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(height: 12),
                                    DropdownButtonFormField<SecurityEntryType>(
                                      initialValue: _entryType,
                                      decoration: const InputDecoration(
                                        labelText: 'Entry type',
                                        border: OutlineInputBorder(),
                                      ),
                                      items: SecurityEntryType.values
                                          .where(
                                            (t) =>
                                                t !=
                                                    SecurityEntryType
                                                        .companyCar &&
                                                t !=
                                                    SecurityEntryType
                                                        .onFootVisitor,
                                          )
                                          .map(
                                            (t) => DropdownMenuItem(
                                              value: t,
                                              child: Text(t.label),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) {
                                        if (v != null) {
                                          setState(() {
                                            _entryType = v;
                                            if (v !=
                                                SecurityEntryType.contractor) {
                                              _contractor = null;
                                            }
                                          });
                                        }
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: _scanDisc,
                                            icon: Icon(
                                              _disc != null
                                                  ? Icons.check_circle
                                                  : Icons.qr_code_scanner,
                                              color: _disc != null
                                                  ? Colors.green
                                                  : null,
                                            ),
                                            label: const Text('Scan disc *'),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: _licenceUnavailable
                                                ? null
                                                : _scanDriverLicence,
                                            icon: Icon(
                                              _driverLicence != null
                                                  ? Icons.check_circle
                                                  : Icons.badge_outlined,
                                              color: _driverLicence != null
                                                  ? Colors.green
                                                  : null,
                                            ),
                                            label: Text(
                                              licenceRequired
                                                  ? 'Scan licence *'
                                                  : 'Scan licence',
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
                                          if (_licenceUnavailable) {
                                            _driverLicence = null;
                                          }
                                        }),
                                        title: const Text(
                                          "Driver's licence not available (will flag entry)",
                                        ),
                                        controlAffinity:
                                            ListTileControlAffinity.leading,
                                      ),
                                      if (_licenceUnavailable) ...[
                                        TextField(
                                          controller: _licenceMissingNoteCtrl,
                                          decoration: const InputDecoration(
                                            labelText: 'Why not scanned? *',
                                            border: OutlineInputBorder(),
                                          ),
                                          maxLines: 2,
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                    ],
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        const Text('Occupants'),
                                        const SizedBox(width: 12),
                                        IconButton(
                                          onPressed: _occupantCount > 1
                                              ? () => setState(
                                                    () => _occupantCount--,
                                                  )
                                              : null,
                                          icon: const Icon(
                                            Icons.remove_circle_outline,
                                          ),
                                        ),
                                        Text(
                                          '$_occupantCount',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                        IconButton(
                                          onPressed: _occupantCount < 20
                                              ? () => setState(
                                                    () => _occupantCount++,
                                                  )
                                              : null,
                                          icon: const Icon(
                                            Icons.add_circle_outline,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    if (_disc?.vehicleReg != null)
                                      Card(
                                        color: kBrandOrange
                                            .withValues(alpha: 0.08),
                                        child: ListTile(
                                          leading: const Icon(
                                            Icons.directions_car_outlined,
                                            color: kBrandOrange,
                                          ),
                                          title: Text(
                                            SecurityVehicle.normalizeReg(
                                              _disc!.vehicleReg,
                                            ),
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                          subtitle: const Text(
                                            'From licence disc scan',
                                          ),
                                        ),
                                      )
                                    else
                                      const Card(
                                        child: Padding(
                                          padding: EdgeInsets.all(12),
                                          child: Text(
                                            'Vehicle registration appears after '
                                            'scanning the licence disc.',
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: _driverCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Driver name *',
                                        border: OutlineInputBorder(),
                                        helperText:
                                            'Filled from licence scan when available',
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SecuritySuggestionField(
                                      controller: _hostCtrl,
                                      label: 'Host or department',
                                      suggestions: hostSuggestions,
                                      helperText:
                                          'Person or area e.g. Loading Bay, Dispatch',
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
                                        labelText:
                                            settings.purposeOfVisitRequired
                                                ? 'Purpose of visit *'
                                                : 'Purpose of visit',
                                        border: const OutlineInputBorder(),
                                      ),
                                      maxLines: 2,
                                    ),
                                    if (_entryType ==
                                        SecurityEntryType.contractor) ...[
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<
                                          SecurityContractor>(
                                        initialValue: _contractor,
                                        decoration: const InputDecoration(
                                          labelText: 'Contractor *',
                                          border: OutlineInputBorder(),
                                        ),
                                        items: contractors
                                            .map(
                                              (c) => DropdownMenuItem(
                                                value: c,
                                                child: Text(c.name),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (c) =>
                                            setState(() => _contractor = c),
                                      ),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: TextButton.icon(
                                          onPressed: () =>
                                              _addContractor(contractors),
                                          icon: const Icon(Icons.add),
                                          label: const Text('Add contractor'),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: _overrideCtrl,
                                      decoration: const InputDecoration(
                                        labelText:
                                            'Override reason (if disc/licence expired)',
                                        border: OutlineInputBorder(),
                                      ),
                                      maxLines: 2,
                                    ),
                                    const SizedBox(height: 12),
                                    OutlinedButton.icon(
                                      onPressed: _pickPhoto,
                                      icon: const Icon(
                                        Icons.camera_alt_outlined,
                                      ),
                                      label: Text(
                                        _photoPaths.isEmpty
                                            ? 'Add photo (optional)'
                                            : '${_photoPaths.length} photo(s) attached',
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    FilledButton(
                                      onPressed: _submitting || gate == null
                                          ? null
                                          : () => _submit(
                                                settings,
                                                gate,
                                                denyList,
                                                vehicles,
                                              ),
                                      style: FilledButton.styleFrom(
                                        minimumSize:
                                            const Size.fromHeight(48),
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
                                          : const Text('Log vehicle in'),
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
            ),
    );
  }
}