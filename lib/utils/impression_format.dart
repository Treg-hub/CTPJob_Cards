import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Human-friendly labels and date formatting for Impression Rollers UI.
class ImpressionFormat {
  ImpressionFormat._();

  static final _dateTime = DateFormat('EEE d MMM yyyy · HH:mm');
  static final _dateOnly = DateFormat('d MMM yyyy');

  /// Parse Firestore Timestamp, DateTime, ISO string, or map with seconds.
  static DateTime? parseDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) {
      final t = DateTime.tryParse(v);
      if (t != null) return t;
    }
    if (v is Map) {
      final seconds = v['seconds'] ?? v['_seconds'];
      if (seconds is num) {
        final nanos = v['nanoseconds'] ?? v['_nanoseconds'] ?? 0;
        final n = nanos is num ? nanos.toInt() : 0;
        return DateTime.fromMillisecondsSinceEpoch(
          seconds.toInt() * 1000 + (n ~/ 1000000),
          isUtc: true,
        ).toLocal();
      }
    }
    return null;
  }

  static String dateTime(dynamic v, {String empty = '—'}) {
    final d = parseDate(v);
    if (d == null) return empty;
    return _dateTime.format(d);
  }

  static String dateOnly(dynamic v, {String empty = '—'}) {
    final d = parseDate(v);
    if (d == null) return empty;
    return _dateOnly.format(d);
  }

  static String press(String? id) {
    switch ((id ?? '').toLowerCase()) {
      case 'aurora':
        return 'Aurora';
      case 'badenia':
        return 'Badenia';
      case 'wifag':
        return 'Wifag';
      default:
        return (id == null || id.isEmpty) ? '—' : id;
    }
  }

  /// Cycle lifecycle states.
  static String state(String? raw) {
    switch (raw) {
      case 'building_mechanical':
        return 'Building (mechanical)';
      case 'mechanical_fail':
        return 'Mechanical fail — rework';
      case 'awaiting_electrical':
        return 'Waiting for electrical test';
      case 'electrical_fail':
        return 'Electrical fail — quarantine';
      case 'spare_ready':
        return 'Spare ready';
      case 'installed':
        return 'Installed on press';
      case 'removed_pending_strip':
        return 'Removed — strip needed';
      case 'sleeve_send_out_pending':
        return 'Sleeve ready to send out';
      case 'sleeve_at_vendor':
        return 'Sleeve at vendor';
      case 'sleeve_received':
        return 'Sleeve received — rebuild';
      case 'scrapped':
        return 'Scrapped';
      case 'closed':
        return 'Closed';
      default:
        return (raw == null || raw.isEmpty) ? '—' : raw.replaceAll('_', ' ');
    }
  }

  /// Unit slot occupancy on the press map.
  static String slotState(String? raw) {
    switch (raw) {
      case 'occupied':
        return 'On press';
      case 'awaiting_install':
        return 'Waiting for install';
      case 'empty':
        return 'Empty';
      default:
        return (raw == null || raw.isEmpty) ? '—' : raw.replaceAll('_', ' ');
    }
  }

  static String esa(String? raw) {
    switch (raw) {
      case 'full':
        return 'Full ESA OK';
      case 'yellow_only':
        return 'Yellow units only';
      case 'unsuitable':
        return 'Unsuitable (legacy)';
      default:
        return (raw == null || raw.isEmpty) ? '—' : raw;
    }
  }

  /// Prefer electrical.pass === false → hard yellow-only wording.
  static String esaFromCycle(Map<String, dynamic>? cycle) {
    if (cycle == null) return '—';
    final elec = cycle['electrical'];
    if (elec is Map && elec['pass'] == false) {
      return 'Electrical FAIL · yellow units only';
    }
    return esa(cycle['esaSuitability']?.toString());
  }

  static String eventType(String? raw) {
    switch (raw) {
      case 'start_build':
        return 'Build started';
      case 'mechanical_pass':
        return 'Mechanical pass';
      case 'mechanical_fail':
        return 'Mechanical fail';
      case 'electrical_pass':
        return 'Electrical pass';
      case 'electrical_fail':
        return 'Electrical fail';
      case 'install':
        return 'Installed on press';
      case 'remove':
        return 'Removed from press';
      case 'strip':
        return 'Stripped';
      case 'send_out':
        return 'Sent to vendor';
      case 'receive':
        return 'Sleeve received';
      default:
        return (raw == null || raw.isEmpty) ? 'Event' : raw.replaceAll('_', ' ');
    }
  }

  static String removalReason(String? raw) {
    switch (raw) {
      case 'planned_change':
        return 'Planned change';
      case 'rubber_split':
      case 'rubber_split_a_side':
        return 'Rubber split (A-side)';
      case 'pressure_high':
        return 'High pressure';
      case 'electrical_fault':
        return 'Electrical fault';
      case 'end_of_life':
        return 'End of life';
      case 'damage':
        return 'Damage';
      case 'other':
        return 'Other';
      default:
        if (raw == null || raw.isEmpty) return '—';
        return raw.replaceAll('_', ' ');
    }
  }

  static String sendOutType(String? raw) {
    switch (raw) {
      case 'recover':
        return 'Recover';
      case 'regrind':
        return 'Regrind';
      default:
        return (raw == null || raw.isEmpty) ? '—' : raw.replaceAll('_', ' ');
    }
  }

  static String yesNo(dynamic v, {String yes = 'Yes', String no = 'No'}) {
    if (v == true) return yes;
    if (v == false) return no;
    return '—';
  }

  static String passFail(dynamic v) {
    if (v == true) return 'PASS';
    if (v == false) return 'FAIL';
    return '—';
  }

  static String person(Map? m) {
    if (m == null) return '—';
    final name = '${m['byName'] ?? ''}'.trim();
    final clock = '${m['byClock'] ?? ''}'.trim();
    if (name.isNotEmpty && clock.isNotEmpty) return '$name ($clock)';
    if (name.isNotEmpty) return name;
    if (clock.isNotEmpty) return 'Clock $clock';
    return '—';
  }

  /// Join non-empty L/M/R (or left/middle/right) values: "237.5 / 237.5 / 237.5"
  static String triad(dynamic map, {List<String>? keys}) {
    if (map is! Map) return '—';
    final k = keys ?? ['left', 'middle', 'right'];
    final parts = k.map((key) {
      final v = map[key];
      if (v == null) return '';
      final s = '$v'.trim();
      return s;
    }).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '—';
    return parts.join(' / ');
  }

  static String pair(dynamic map, {List<String> keys = const ['left', 'right']}) {
    return triad(map, keys: keys);
  }

  static String display(dynamic v, {String empty = '—'}) {
    if (v == null) return empty;
    if (v is String) {
      final t = v.trim();
      return t.isEmpty ? empty : t;
    }
    if (v is bool) return yesNo(v);
    if (v is num) return v.toString();
    final asDate = parseDate(v);
    if (asDate != null) return _dateTime.format(asDate);
    return v.toString();
  }

  /// Non-empty trimmed string or null.
  static String? nonEmpty(dynamic v) {
    if (v == null) return null;
    final s = '$v'.trim();
    return s.isEmpty ? null : s;
  }
}
