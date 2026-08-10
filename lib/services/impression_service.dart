import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../constants/collections.dart';
import '../models/impression_settings.dart';

class ImpressionService {
  ImpressionService._();
  static final ImpressionService instance = ImpressionService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'africa-south1');

  Stream<ImpressionSettings> watchSettings() {
    return _db
        .collection(Collections.impressionSettings)
        .doc('config')
        .snapshots()
        .map((s) => s.exists
            ? ImpressionSettings.fromFirestore(s)
            : ImpressionSettings.defaults);
  }

  Future<ImpressionSettings> getSettings() async {
    final s = await _db
        .collection(Collections.impressionSettings)
        .doc('config')
        .get();
    return s.exists
        ? ImpressionSettings.fromFirestore(s)
        : ImpressionSettings.defaults;
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchSlots(
    String pressId,
  ) {
    return _db
        .collection(Collections.impressionUnitSlots)
        .where('pressId', isEqualTo: pressId)
        .snapshots()
        .map((s) {
      final docs = s.docs.toList()
        ..sort((a, b) {
          final ua = (a.data()['unitNo'] as num?)?.toInt() ?? 0;
          final ub = (b.data()['unitNo'] as num?)?.toInt() ?? 0;
          return ua.compareTo(ub);
        });
      return docs;
    });
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchCyclesByState(
    String state, {
    String? pressId,
  }) {
    Query<Map<String, dynamic>> q = _db
        .collection(Collections.impressionCycles)
        .where('state', isEqualTo: state);
    if (pressId != null) {
      q = q.where('pressId', isEqualTo: pressId);
    }
    return q.limit(50).snapshots().map((s) => s.docs);
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final callable = _functions.httpsCallable(name);
    final res = await callable.call(data);
    final raw = res.data;
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return {'success': true};
  }

  Future<Map<String, dynamic>> startBuild({
    required String shaftNo,
    required String pressId,
    String? sleeveId,
    bool unnumbered = false,
    bool rematch = false,
    String? rematchReason,
    Map<String, dynamic>? mechanical,
    String? clientRef,
    /// Manager/admin only — ISO-8601; CF ignores for non-managers.
    DateTime? effectiveAt,
    /// Manager/admin only — who actually did the mechanical work.
    String? performedByClock,
  }) {
    return _call('startImpressionBuild', {
      'shaftNo': shaftNo,
      'pressId': pressId,
      if (sleeveId != null) 'sleeveId': sleeveId,
      'unnumbered': unnumbered,
      'rematch': rematch,
      if (rematchReason != null) 'rematchReason': rematchReason,
      if (mechanical != null) 'mechanical': mechanical,
      if (clientRef != null) 'client_ref': clientRef,
      if (effectiveAt != null) 'effectiveAt': effectiveAt.toUtc().toIso8601String(),
      if (performedByClock != null) 'performedByClock': performedByClock,
    });
  }

  Future<Map<String, dynamic>> completeElectrical({
    required String cycleId,
    required bool pass,
    required String esaSuitability,
    Map<String, dynamic>? electrical,
    /// Manager/admin only — ISO-8601; CF ignores for non-managers.
    DateTime? effectiveAt,
    /// Manager/admin only — who actually did the electrical test.
    String? performedByClock,
  }) {
    return _call('completeImpressionElectrical', {
      'cycleId': cycleId,
      'pass': pass,
      'esaSuitability': esaSuitability,
      if (electrical != null) 'electrical': electrical,
      if (effectiveAt != null) 'effectiveAt': effectiveAt.toUtc().toIso8601String(),
      if (performedByClock != null) 'performedByClock': performedByClock,
    });
  }

  Future<Map<String, dynamic>> removeRoller({
    required String pressId,
    required int unitNo,
    required String reason,
    double? revsMillions,
    String? comments,
    List<String>? photoPaths,
    /// Manager/admin only — who removed the roller.
    String? performedByClock,
  }) {
    return _call('removeImpressionRoller', {
      'pressId': pressId,
      'unitNo': unitNo,
      'reason': reason,
      if (revsMillions != null) 'revsMillions': revsMillions,
      if (comments != null) 'comments': comments,
      if (photoPaths != null) 'photoPaths': photoPaths,
      if (performedByClock != null) 'performedByClock': performedByClock,
    });
  }

  Future<Map<String, dynamic>> installRoller({
    required String pressId,
    required int unitNo,
    required String cycleId,
    bool yellowOnlyOverride = false,
    String? yellowOnlyNote,
    /// Manager/admin only — ISO-8601; CF ignores for non-managers.
    DateTime? effectiveAt,
    /// Manager/admin only — who installed the roller.
    String? performedByClock,
  }) {
    return _call('installImpressionRoller', {
      'pressId': pressId,
      'unitNo': unitNo,
      'cycleId': cycleId,
      'yellowOnlyOverride': yellowOnlyOverride,
      if (yellowOnlyNote != null) 'yellowOnlyNote': yellowOnlyNote,
      if (effectiveAt != null) 'effectiveAt': effectiveAt.toUtc().toIso8601String(),
      if (performedByClock != null) 'performedByClock': performedByClock,
    });
  }

  /// Manager/admin: correct historical who-did-what on a cycle.
  Future<Map<String, dynamic>> updateCycleActors({
    required String cycleId,
    String? mechanicalByClock,
    String? electricalByClock,
    String? installByClock,
    String? removeByClock,
    String? stripByClock,
    String? sendOutByClock,
  }) {
    return _call('updateImpressionCycleActors', {
      'cycleId': cycleId,
      if (mechanicalByClock != null) 'mechanicalByClock': mechanicalByClock,
      if (electricalByClock != null) 'electricalByClock': electricalByClock,
      if (installByClock != null) 'installByClock': installByClock,
      if (removeByClock != null) 'removeByClock': removeByClock,
      if (stripByClock != null) 'stripByClock': stripByClock,
      if (sendOutByClock != null) 'sendOutByClock': sendOutByClock,
    });
  }

  Future<Map<String, dynamic>> strip({
    required String cycleId,
    required String sleeveDisposition,
    String? sendOutType,
    String? notes,
    /// Manager/admin only — who stripped.
    String? performedByClock,
  }) {
    return _call('stripImpressionRoller', {
      'cycleId': cycleId,
      'sleeveDisposition': sleeveDisposition,
      if (sendOutType != null) 'sendOutType': sendOutType,
      if (notes != null) 'notes': notes,
      if (performedByClock != null) 'performedByClock': performedByClock,
    });
  }

  Future<Map<String, dynamic>> sendOut({
    required String cycleId,
    required String vendor,
    required String sendOutType,
    String? eta,
    /// Manager/admin only — who sent out.
    String? performedByClock,
  }) {
    return _call('sendOutImpressionSleeve', {
      'cycleId': cycleId,
      'vendor': vendor,
      'sendOutType': sendOutType,
      if (eta != null) 'eta': eta,
      if (performedByClock != null) 'performedByClock': performedByClock,
    });
  }

  Future<Map<String, dynamic>> receive({required String cycleId}) {
    return _call('receiveImpressionSleeve', {'cycleId': cycleId});
  }

  Future<Map<String, dynamic>> submitDailyIr({
    required String pressId,
    required String dateKey,
    required Map<String, Map<String, dynamic>> units,
    String? shiftColour,
    String? dayNight,
  }) {
    return _call('submitImpressionDailyIr', {
      'pressId': pressId,
      'dateKey': dateKey,
      'units': units,
      if (shiftColour != null) 'shiftColour': shiftColour,
      if (dayNight != null) 'dayNight': dayNight,
    });
  }

  Future<Map<String, dynamic>> submitDailyEsa({
    required String pressId,
    required String dateKey,
    required Map<String, Map<String, dynamic>> units,
    String? shiftColour,
    String? dayNight,
  }) {
    return _call('submitImpressionDailyEsa', {
      'pressId': pressId,
      'dateKey': dateKey,
      'units': units,
      if (shiftColour != null) 'shiftColour': shiftColour,
      if (dayNight != null) 'dayNight': dayNight,
    });
  }

  /// Today key Africa/Johannesburg approximate (device local if TZ set).
  static String todayDateKey() {
    final n = DateTime.now();
    final y = n.year.toString().padLeft(4, '0');
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
