import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:uuid/uuid.dart';

import '../constants/collections.dart';
import '../models/parsed_document.dart';
import '../models/security_contractor.dart';
import '../models/security_deny_entry.dart';
import '../models/security_entry.dart';
import '../models/security_gate.dart';
import '../models/security_settings.dart';
import '../models/security_vehicle.dart';
import '../models/security_vehicle_trip.dart';
import 'connectivity_service.dart';
import 'sync_service.dart';

/// Site Security operations — gate logging, compliance, offline queue.
class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'africa-south1');

  static const Duration _callableTimeout = Duration(seconds: 15);
  static const Duration _firestoreTimeout = Duration(seconds: 8);
  static const Duration _photoTimeout = Duration(seconds: 12);

  static final RegExp _properEntryNumber = RegExp(r'^SEC-\d{4,}$');

  Future<bool> _isOnline() =>
      ConnectivityService().isOnline().catchError((_) => false);

  // ---------------------------------------------------------------------------
  // SETTINGS / MASTER DATA
  // ---------------------------------------------------------------------------

  Stream<SecuritySettings> watchSettings() {
    return _db
        .collection(Collections.securitySettings)
        .doc('config')
        .snapshots()
        .map((snap) => SecuritySettings.fromFirestore(snap));
  }

  Future<SecuritySettings> getSettings() async {
    final snap = await _db
        .collection(Collections.securitySettings)
        .doc('config')
        .get();
    return SecuritySettings.fromFirestore(snap);
  }

  Stream<List<SecurityGate>> watchGates({bool activeOnly = true}) {
    return _db.collection(Collections.securityGates).snapshots().map((snap) {
      var gates = snap.docs.map(SecurityGate.fromFirestore).toList();
      if (activeOnly) gates = gates.where((g) => g.active).toList();
      gates.sort((a, b) {
        final ao = a.sortOrder ?? 999;
        final bo = b.sortOrder ?? 999;
        final cmp = ao.compareTo(bo);
        return cmp != 0 ? cmp : a.name.compareTo(b.name);
      });
      return gates;
    });
  }

  Stream<List<SecurityVehicle>> watchVehicles({bool activeOnly = true}) {
    return _db.collection(Collections.securityVehicles).snapshots().map((snap) {
      var list = snap.docs.map(SecurityVehicle.fromFirestore).toList();
      if (activeOnly) list = list.where((v) => v.active).toList();
      list.sort((a, b) => a.vehicleReg.compareTo(b.vehicleReg));
      return list;
    });
  }

  Stream<List<SecurityDenyEntry>> watchDenyList({bool activeOnly = true}) {
    return _db.collection(Collections.securityDenyList).snapshots().map((snap) {
      var list = snap.docs.map(SecurityDenyEntry.fromFirestore).toList();
      if (activeOnly) list = list.where((e) => e.active).toList();
      return list;
    });
  }

  Stream<List<SecurityContractor>> watchContractors({bool activeOnly = true}) {
    return _db.collection(Collections.securityContractors).snapshots().map((snap) {
      var list = snap.docs.map(SecurityContractor.fromFirestore).toList();
      if (activeOnly) list = list.where((c) => c.active).toList();
      list.sort((a, b) => a.name.compareTo(b.name));
      return list;
    });
  }

  Stream<List<String>> watchLookupSuggestions(String type) {
    return _db
        .collection(Collections.securityLookupOptions)
        .where('type', isEqualTo: type)
        .where('active', isEqualTo: true)
        .snapshots()
        .map((snap) {
      final values = snap.docs
          .map((d) => (d.data()['value'] as String?)?.trim() ?? '')
          .where((v) => v.isNotEmpty)
          .toSet()
          .toList();
      values.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return values;
    });
  }

  Future<void> ensureLookupOption({
    required String type,
    required String value,
    String? createdByClockNo,
  }) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    final lower = trimmed.toLowerCase();
    final existing = await _db
        .collection(Collections.securityLookupOptions)
        .where('type', isEqualTo: type)
        .where('value_lower', isEqualTo: lower)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) return;
    await _db.collection(Collections.securityLookupOptions).add({
      'type': type,
      'value': trimmed,
      'value_lower': lower,
      'active': true,
      'created_at': FieldValue.serverTimestamp(),
      if (createdByClockNo != null) 'created_by_clock_no': createdByClockNo,
    });
  }

  Future<SecurityContractor> addContractor({
    required String name,
    String? contact,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Contractor name is required');
    }
    final ref = await _db.collection(Collections.securityContractors).add({
      'name': trimmed,
      if (contact != null && contact.trim().isNotEmpty) 'contact': contact.trim(),
      'active': true,
      'created_at': FieldValue.serverTimestamp(),
    });
    final snap = await ref.get();
    return SecurityContractor.fromFirestore(snap);
  }

  Stream<List<SecurityEntry>> watchRecentEntries({int limit = 100}) {
    return _db
        .collection(Collections.securityEntries)
        .orderBy('logged_at', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(SecurityEntry.fromFirestore).toList());
  }

  // ---------------------------------------------------------------------------
  // COMPLIANCE HELPERS
  // ---------------------------------------------------------------------------

  SecurityDenyEntry? matchDenyList(
    List<SecurityDenyEntry> denyList, {
    String? vehicleReg,
    String? driverName,
  }) {
    final reg = SecurityVehicle.normalizeReg(vehicleReg);
    final driver = driverName?.trim().toLowerCase();
    for (final entry in denyList) {
      if (!entry.active) continue;
      final regMatch = reg.isNotEmpty && entry.vehicleReg == reg;
      final driverMatch = driver != null &&
          driver.isNotEmpty &&
          entry.driverName != null &&
          entry.driverName!.trim().toLowerCase() == driver;
      if (regMatch || driverMatch) return entry;
    }
    return null;
  }

  SecurityVehicle? findCompanyVehicle(
    List<SecurityVehicle> vehicles,
    String vehicleReg,
  ) {
    final reg = SecurityVehicle.normalizeReg(vehicleReg);
    for (final v in vehicles) {
      if (!v.active || !v.isCompanyCar) continue;
      if (v.vehicleReg == reg) return v;
    }
    return null;
  }

  bool isExpired(DateTime? date, [DateTime? ref]) {
    if (date == null) return false;
    final today = ref ?? DateTime.now();
    final d = DateTime(date.year, date.month, date.day);
    final t = DateTime(today.year, today.month, today.day);
    return d.isBefore(t);
  }

  bool isExpirySoon(DateTime? date, int warnDays, [DateTime? ref]) {
    if (date == null) return false;
    final today = ref ?? DateTime.now();
    final end = today.add(Duration(days: warnDays));
    return !isExpired(date, today) && !date.isAfter(end);
  }

  /// Transporter: blocks on expired disc/ID. Visitor/contractor: warn only.
  ({bool blocked, bool warn, String? message}) evaluateCompliance({
    required SecurityEntryType entryType,
    DateTime? discExpiry,
    DateTime? idExpiry,
    required int warnDays,
  }) {
    final discExpired = isExpired(discExpiry);
    final idExpired = isExpired(idExpiry);
    final discSoon = isExpirySoon(discExpiry, warnDays);
    final idSoon = isExpirySoon(idExpiry, warnDays);

    if (entryType == SecurityEntryType.transporter) {
      if (discExpired || idExpired) {
        final parts = <String>[];
        if (discExpired) parts.add('license disc expired');
        if (idExpired) parts.add('driver licence expired');
        return (
          blocked: true,
          warn: false,
          message: parts.join('; '),
        );
      }
      return (blocked: false, warn: false, message: null);
    }

    if (entryType == SecurityEntryType.visitor ||
        entryType == SecurityEntryType.contractor) {
      if (discExpired || idExpired || discSoon || idSoon) {
        final parts = <String>[];
        if (discExpired) parts.add('license disc expired');
        if (idExpired) parts.add('driver licence expired');
        if (discSoon) parts.add('license disc expiring soon');
        if (idSoon) parts.add('driver licence expiring soon');
        return (blocked: false, warn: true, message: parts.join('; '));
      }
    }

    return (blocked: false, warn: false, message: null);
  }

  /// Unique non-empty values from recent entries (most recent first).
  List<String> recentFieldValues(
    List<SecurityEntry> entries,
    String? Function(SecurityEntry) getter, {
    int limit = 30,
  }) {
    final seen = <String>{};
    final result = <String>[];
    for (final e in entries) {
      final value = getter(e)?.trim();
      if (value == null || value.isEmpty) continue;
      final key = value.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      result.add(value);
      if (result.length >= limit) break;
    }
    return result;
  }

  List<String> recentHostNames(List<SecurityEntry> entries) =>
      recentFieldValues(entries, (e) => e.hostName);

  List<String> recentCompanyNames(List<SecurityEntry> entries) =>
      recentFieldValues(entries, (e) => e.companyName);

  List<String> recentContractorNames(List<SecurityEntry> entries) =>
      recentFieldValues(entries, (e) => e.contractorName);

  /// On-site vehicle matching a normalized registration.
  SecurityEntry? findOnSiteByReg(List<SecurityEntry> onSite, String? vehicleReg) {
    final reg = SecurityVehicle.normalizeReg(vehicleReg);
    if (reg.isEmpty) return null;
    for (final e in onSite) {
      if (SecurityVehicle.normalizeReg(e.vehicleReg) == reg) return e;
    }
    return null;
  }

  /// Vehicles currently on site (latest direction per reg is in).
  List<SecurityEntry> computeOnSite(List<SecurityEntry> entries) {
    final latest = <String, SecurityEntry>{};
    final sorted = [...entries]
      ..sort((a, b) =>
          (b.loggedAt ?? DateTime(0)).compareTo(a.loggedAt ?? DateTime(0)));
    for (final e in sorted) {
      final reg = SecurityVehicle.normalizeReg(e.vehicleReg);
      if (reg.isEmpty || latest.containsKey(reg)) continue;
      latest[reg] = e;
    }
    return latest.values
        .where((e) => e.direction == SecurityDirection.in_)
        .toList()
      ..sort((a, b) =>
          (b.loggedAt ?? DateTime(0)).compareTo(a.loggedAt ?? DateTime(0)));
  }

  // ---------------------------------------------------------------------------
  // ENTRY CREATE (CF + offline)
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _callCreateEntry(
      Map<String, dynamic> data) async {
    final callable = _functions.httpsCallable('createSecurityEntry');
    final result =
        await callable.call(data).timeout(_callableTimeout);
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<String?> assignEntryNumberIfNeeded(String entryId) async {
    try {
      final result = await _functions
          .httpsCallable('assignSecurityEntryNumber')
          .call({'entryId': entryId})
          .timeout(_callableTimeout);
      final data = Map<String, dynamic>.from(result.data as Map);
      return data['entry_number'] as String?;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('assignEntryNumberIfNeeded failed for $entryId: $e');
      }
      return null;
    }
  }

  Future<void> notifyDenyEntry({
    required String gateId,
    String? gateName,
    required String vehicleReg,
    String? driverName,
    String? denyReason,
    String? entryId,
  }) async {
    try {
      await _functions.httpsCallable('notifySecurityDenyEntry').call({
        'gate_id': gateId,
        if (gateName != null) 'gate_name': gateName,
        'vehicle_reg': vehicleReg,
        if (driverName != null) 'driver_name': driverName,
        if (denyReason != null) 'deny_reason': denyReason,
        if (entryId != null) 'entry_id': entryId,
      }).timeout(_callableTimeout);
    } catch (e) {
      if (kDebugMode) debugPrint('notifySecurityDenyEntry failed: $e');
    }
  }

  /// Creates a gate entry via CF when online; queues create_cf when offline.
  Future<({String id, String? entryNumber, bool queuedOffline})> createEntry({
    required Map<String, dynamic> data,
    List<String> photoLocalPaths = const [],
  }) async {
    final online = await _isOnline();
    final queueId = const Uuid().v4();
    final provisional = 'OFFLINE-SEC-${DateTime.now().millisecondsSinceEpoch}';

    final cfData = Map<String, dynamic>.from(data)
      ..['client_ref'] = queueId;
    if (!cfData.containsKey('entry_number') ||
        (cfData['entry_number'] as String?)?.isEmpty == true) {
      cfData['entry_number'] = provisional;
    }

    final queuePayload = Map<String, dynamic>.from(cfData);
    if (photoLocalPaths.isNotEmpty) {
      queuePayload['_pending_photo_paths'] = photoLocalPaths;
    }

    await SyncService().addToQueue(
      collection: Collections.securityEntries,
      operation: 'create_cf',
      data: SyncService.sanitizeForHive(queuePayload),
      documentId: queueId,
    );

    if (!online) {
      return (id: queueId, entryNumber: provisional, queuedOffline: true);
    }

    String entryId;
    String? entryNumber;
    try {
      final result = await _callCreateEntry(cfData);
      entryId = result['id'] as String;
      entryNumber = result['entry_number'] as String?;
    } catch (_) {
      unawaited(SyncService().processNow());
      return (id: queueId, entryNumber: provisional, queuedOffline: true);
    }

    await SyncService().mutateQueuedItemData(
      collection: Collections.securityEntries,
      documentId: queueId,
      mutate: (d) => d['_created_entry_id'] = entryId,
    );

    for (final path in photoLocalPaths) {
      try {
        final url = await uploadEntryPhoto(
          localPath: path,
          entryId: entryId,
        ).timeout(_photoTimeout);
        await _db.collection(Collections.securityEntries).doc(entryId).update({
          'photos': FieldValue.arrayUnion([url]),
        }).timeout(_firestoreTimeout);
        await SyncService().mutateQueuedItemData(
          collection: Collections.securityEntries,
          documentId: queueId,
          mutate: (d) =>
              (d['_pending_photo_paths'] as List?)?.remove(path),
        );
      } catch (_) {
        await queueOfflineEntryPhoto(localPath: path, entryId: entryId);
      }
    }

    await SyncService().removeQueuedItem(
      collection: Collections.securityEntries,
      documentId: queueId,
    );

    return (id: entryId, entryNumber: entryNumber, queuedOffline: false);
  }

  /// Scan-out helper — logs an out entry for an on-site vehicle.
  Future<({String id, String? entryNumber, bool queuedOffline})> scanOut({
    required SecurityEntry onSiteEntry,
    required String gateId,
    String? gateName,
    required String loggedByClockNo,
    required String loggedByName,
    String? sessionId,
    ParsedDocument? discScan,
    required int occupantsLeaving,
    String? occupantDiscrepancyNote,
    bool discScanMissingFlag = false,
  }) async {
    final recorded = onSiteEntry.occupantCount ?? 1;
    final discrepancy = occupantsLeaving != recorded;
    final partial = occupantsLeaving < recorded;
    final remaining = partial ? recorded - occupantsLeaving : null;

    return createEntry(
      data: {
        'gate_id': gateId,
        if (gateName != null) 'gate_name': gateName,
        'direction': SecurityDirection.out.value,
        'entry_type': onSiteEntry.entryType?.value,
        'vehicle_reg': onSiteEntry.vehicleReg,
        'driver_name': onSiteEntry.driverName,
        'contractor_id': onSiteEntry.contractorId,
        'contractor_name': onSiteEntry.contractorName,
        'purpose': onSiteEntry.purpose,
        'occupant_count': recorded,
        'occupants_leaving': occupantsLeaving,
        'occupant_discrepancy': discrepancy,
        if (occupantDiscrepancyNote != null)
          'occupant_discrepancy_note': occupantDiscrepancyNote,
        'partial_occupant_exit': partial,
        if (remaining != null) 'occupants_remaining': remaining,
        'session_id': sessionId ?? onSiteEntry.sessionId,
        'logged_by_clock_no': loggedByClockNo,
        'logged_by_name': loggedByName,
        'logged_at': DateTime.now().toIso8601String(),
        'disc_scan_captured': discScan != null,
        'disc_scan_missing_flag': discScanMissingFlag,
        if (discScan?.expiryDate != null)
          'disc_expiry': discScan!.expiryDate!.toIso8601String(),
        if (discScan?.vehicleMake != null) 'vehicle_make': discScan!.vehicleMake,
        if (discScan?.vehicleColour != null)
          'vehicle_colour': discScan!.vehicleColour,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // COMPANY CAR TRIPS
  // ---------------------------------------------------------------------------

  Future<void> recordCompanyCarTrip({
    required SecurityVehicleTrip trip,
  }) async {
    await _db.collection(Collections.securityVehicleTrips).add(trip.toFirestore());
  }

  Future<void> updateCompanyVehicleOdometer({
    required String vehicleId,
    required double odometer,
  }) async {
    await _db.collection(Collections.securityVehicles).doc(vehicleId).update({
      'odometer_last': odometer,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // VEHICLE COSTS (manager)
  // ---------------------------------------------------------------------------

  Future<void> addVehicleCost({
    required String vehicleReg,
    required DateTime costDate,
    required String category,
    required String description,
    required double amountZar,
    required String enteredByClockNo,
    String? contractorId,
    String? receiptPhotoUrl,
  }) async {
    final reg = SecurityVehicle.normalizeReg(vehicleReg);
    final vehiclesSnap =
        await _db.collection(Collections.securityVehicles).get();
    final vehicles =
        vehiclesSnap.docs.map(SecurityVehicle.fromFirestore).toList();
    if (findCompanyVehicle(vehicles, reg) == null) {
      throw Exception(
        'Costs can only be recorded for registered company cars.',
      );
    }
    await _db.collection(Collections.securityVehicleCosts).add({
      'vehicle_reg': reg,
      'cost_date': Timestamp.fromDate(costDate),
      'category': category,
      'description': description,
      'amount_zar': amountZar,
      'entered_by_clock_no': enteredByClockNo,
      if (contractorId != null) 'contractor_id': contractorId,
      if (receiptPhotoUrl != null) 'receipt_photo_url': receiptPhotoUrl,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // PHOTOS
  // ---------------------------------------------------------------------------

  Future<String> uploadEntryPhoto({
    required String localPath,
    required String entryId,
  }) async {
    final file = File(localPath);
    if (!file.existsSync()) {
      throw Exception('Photo file not found: $localPath');
    }

    Uint8List? compressed;
    try {
      compressed = await FlutterImageCompress.compressWithFile(
        localPath,
        quality: 75,
        minWidth: 1280,
        minHeight: 1280,
      );
    } catch (_) {}

    final fileName = '${const Uuid().v4()}.jpg';
    final ref = _storage.ref('security_entries/$entryId/$fileName');
    final snapshot = compressed != null
        ? await ref.putData(compressed)
        : await ref.putFile(file);
    return snapshot.ref.getDownloadURL();
  }

  Future<void> queueOfflineEntryPhoto({
    required String localPath,
    required String entryId,
  }) async {
    await SyncService().addToQueue(
      collection: 'security_photos',
      operation: 'upload',
      data: SyncService.sanitizeForHive({
        'localPath': localPath,
        'entryId': entryId,
      }),
      documentId: '${entryId}_${localPath.hashCode}',
    );
  }

  void logAudit({
    required String action,
    required String actorClockNo,
    String? actorName,
    Map<String, dynamic>? details,
  }) {
    unawaited(
      _db.collection(Collections.securityAudit).add({
        'action': action,
        'actor_clock_no': actorClockNo,
        if (actorName != null) 'actor_name': actorName,
        if (details != null) 'details': details,
        'created_at': FieldValue.serverTimestamp(),
      }),
    );
  }

  bool needsEntryNumber(String? entryNumber) {
    if (entryNumber == null || entryNumber.trim().isEmpty) return true;
    if (_properEntryNumber.hasMatch(entryNumber)) return false;
    return entryNumber.startsWith('OFFLINE-SEC-');
  }
}