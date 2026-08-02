import 'package:cloud_firestore/cloud_firestore.dart';

/// impression_settings/config
class ImpressionPressConfig {
  final String label;
  final int unitCount;
  final List<int> noEsaUnits;
  final String esaChargeStyle;
  final String esaChargeLabel;
  final String esaDischargeLabel;
  final double aSideBarMax;
  final double bSideBarMax;
  final double bladderBarMax;
  final double? outletCTarget;
  final double? inletCTarget;

  const ImpressionPressConfig({
    required this.label,
    this.unitCount = 8,
    this.noEsaUnits = const [],
    this.esaChargeStyle = 'external',
    this.esaChargeLabel = 'ESA charge bar',
    this.esaDischargeLabel = 'ESA discharge bar',
    this.aSideBarMax = 15,
    this.bSideBarMax = 15,
    this.bladderBarMax = 2,
    this.outletCTarget,
    this.inletCTarget,
  });

  factory ImpressionPressConfig.fromMap(String pressId, Map<String, dynamic>? raw) {
    final m = raw ?? {};
    final labels = (m['esa_labels'] as Map?)?.cast<String, dynamic>() ?? {};
    return ImpressionPressConfig(
      label: (m['label'] as String?) ?? pressId,
      unitCount: (m['unit_count'] as num?)?.toInt() ?? 8,
      noEsaUnits: (m['no_esa_units'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
      esaChargeStyle: (m['esa_charge_style'] as String?) ?? 'external',
      esaChargeLabel: (labels['charge'] as String?) ?? 'ESA charge bar',
      esaDischargeLabel: (labels['discharge'] as String?) ?? 'ESA discharge bar',
      aSideBarMax: (m['a_side_bar_max'] as num?)?.toDouble() ?? 15,
      bSideBarMax: (m['b_side_bar_max'] as num?)?.toDouble() ?? 15,
      bladderBarMax: (m['bladder_bar_max'] as num?)?.toDouble() ?? 2,
      outletCTarget: (m['outlet_c_target'] as num?)?.toDouble(),
      inletCTarget: (m['inlet_c_target'] as num?)?.toDouble(),
    );
  }
}

class ImpressionSettings {
  final bool moduleEnabled;
  final int consecutiveOverMaxThreshold;
  final Map<String, ImpressionPressConfig> presses;
  final List<String> removalReasons;
  final List<String> sendOutTypes;
  final List<String> mechanicalClockNos;
  final List<String> electricalClockNos;
  final List<String> foremanClockNos;
  final List<String> managerClockNos;
  final List<String> pressroomExtraClockNos;
  final List<String> vendors;

  const ImpressionSettings({
    this.moduleEnabled = true,
    this.consecutiveOverMaxThreshold = 5,
    this.presses = const {},
    this.removalReasons = const [],
    this.sendOutTypes = const [],
    this.mechanicalClockNos = const [],
    this.electricalClockNos = const [],
    this.foremanClockNos = const [],
    this.managerClockNos = const [],
    this.pressroomExtraClockNos = const [],
    this.vendors = const [],
  });

  static const ImpressionSettings defaults = ImpressionSettings(
    presses: {
      'badenia': ImpressionPressConfig(
        label: 'Badenia',
        noEsaUnits: [4, 5],
        esaChargeStyle: 'internal',
        esaChargeLabel: 'ESA pressure roller / internal charge',
        outletCTarget: 22,
        inletCTarget: 15,
      ),
      'aurora': ImpressionPressConfig(label: 'Aurora', noEsaUnits: [4, 5]),
      'wifag': ImpressionPressConfig(label: 'Wifag', noEsaUnits: [1, 5]),
    },
    removalReasons: [
      'failed_electrically',
      'planned_change',
      'delaminated',
      'other',
    ],
    sendOutTypes: ['recover', 'regrind', 'other'],
    vendors: ['Rubber Engineering'],
  );

  static String normalizeClockNo(dynamic value) {
    if (value == null) return '';
    if (value is int) return value.toString();
    if (value is double && value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString().trim();
  }

  static List<String> _clocks(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map(normalizeClockNo).where((c) => c.isNotEmpty).toList();
  }

  factory ImpressionSettings.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final pressesRaw = (data['presses'] as Map?)?.cast<String, dynamic>() ?? {};
    final presses = <String, ImpressionPressConfig>{};
    for (final e in pressesRaw.entries) {
      presses[e.key] = ImpressionPressConfig.fromMap(
        e.key,
        (e.value as Map?)?.cast<String, dynamic>(),
      );
    }
    if (presses.isEmpty) {
      return ImpressionSettings.defaults.copyWith(
        moduleEnabled: data['module_enabled'] as bool? ?? true,
      );
    }
    return ImpressionSettings(
      moduleEnabled: data['module_enabled'] as bool? ?? true,
      consecutiveOverMaxThreshold:
          (data['consecutive_over_max_threshold'] as num?)?.toInt() ?? 5,
      presses: presses,
      removalReasons: (data['removal_reasons'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          ImpressionSettings.defaults.removalReasons,
      sendOutTypes: (data['send_out_types'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          ImpressionSettings.defaults.sendOutTypes,
      mechanicalClockNos: _clocks(data['mechanical_clock_nos']),
      electricalClockNos: _clocks(data['electrical_clock_nos']),
      foremanClockNos: _clocks(data['foreman_clock_nos']),
      managerClockNos: _clocks(data['manager_clock_nos']),
      pressroomExtraClockNos: _clocks(data['pressroom_extra_clock_nos']),
      vendors: (data['vendors'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['Rubber Engineering'],
    );
  }

  ImpressionSettings copyWith({bool? moduleEnabled}) {
    return ImpressionSettings(
      moduleEnabled: moduleEnabled ?? this.moduleEnabled,
      consecutiveOverMaxThreshold: consecutiveOverMaxThreshold,
      presses: presses,
      removalReasons: removalReasons,
      sendOutTypes: sendOutTypes,
      mechanicalClockNos: mechanicalClockNos,
      electricalClockNos: electricalClockNos,
      foremanClockNos: foremanClockNos,
      managerClockNos: managerClockNos,
      pressroomExtraClockNos: pressroomExtraClockNos,
      vendors: vendors,
    );
  }
}
