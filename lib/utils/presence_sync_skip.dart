import 'dart:convert';

/// Cost discipline: decide when [updateMyPresence] may skip the
/// `updateEmployeePresence` callable without changing geofence behaviour.
///
/// Rules (must hold forever):
/// - Payloads that include `isOnSite` are **never** skipped here — callers that
///   pass it have already decided a transition (or correction) is needed, and
///   server-side stale clears can diverge from the last client-sent value.
/// - Non-presence payloads (FCM token, platform, permissions, delivery mode)
///   may skip when the fingerprint matches a recent successful sync.
/// - [force] always calls through.
class PresenceSyncSkip {
  PresenceSyncSkip._();

  /// Warm resume TTL for non-presence payloads (same order as claims TTL).
  static const Duration ttl = Duration(minutes: 45);

  /// Stable fingerprint of the CF payload (excluding `source`, which is only
  /// meaningful with `isOnSite` and is not used for skip decisions).
  static String fingerprint(Map<String, dynamic> payload) {
    final keys = payload.keys.where((k) => k != 'source').toList()..sort();
    final normalized = <String, dynamic>{};
    for (final key in keys) {
      normalized[key] = _normalize(payload[key]);
    }
    return jsonEncode(normalized);
  }

  static dynamic _normalize(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      return {
        for (final k in keys) k: _normalize(value[k]),
      };
    }
    if (value is List) {
      return value.map(_normalize).toList();
    }
    return value;
  }

  /// Returns true when the callable can be skipped safely.
  static bool shouldSkip({
    required Map<String, dynamic> payload,
    required bool force,
    required String? lastFingerprint,
    required DateTime? lastSuccessAt,
    DateTime? now,
  }) {
    if (force) return false;
    if (payload.isEmpty) return true;
    // Geofence / stale-clear corrections must always reach the CF.
    if (payload.containsKey('isOnSite')) return false;
    if (lastFingerprint == null || lastSuccessAt == null) return false;
    final age = (now ?? DateTime.now()).difference(lastSuccessAt);
    if (age < Duration.zero || age > ttl) return false;
    return fingerprint(payload) == lastFingerprint;
  }
}
