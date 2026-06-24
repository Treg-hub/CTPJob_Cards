import 'package:cloud_firestore/cloud_firestore.dart';

/// Configurable daily checklist stored in fleet_settings/daily_checklist.
class FleetDailyChecklistConfig {
  final bool enabled;
  final List<FleetDailyChecklistItem> items;
  final List<String> instructions;
  final List<String> footerNotes;

  const FleetDailyChecklistConfig({
    this.enabled = true,
    this.items = const [],
    this.instructions = const [],
    this.footerNotes = const [],
  });

  static const FleetDailyChecklistConfig defaults = FleetDailyChecklistConfig(
    enabled: true,
    items: [
      FleetDailyChecklistItem(id: '1', label: 'Engine oil level'),
      FleetDailyChecklistItem(id: '2', label: 'Transmission oil'),
      FleetDailyChecklistItem(id: '3', label: 'Hydraulic oil No 68'),
      FleetDailyChecklistItem(id: '4', label: 'Gas'),
      FleetDailyChecklistItem(id: '5', label: 'Radiator water level'),
      FleetDailyChecklistItem(id: '6', label: 'Reverse buzzer'),
      FleetDailyChecklistItem(id: '7', label: 'Brake fluid 2.5 and 3 ton'),
      FleetDailyChecklistItem(id: '8', label: 'Tyres/wheel nuts'),
      FleetDailyChecklistItem(id: '9', label: 'Foot and hand brakes'),
      FleetDailyChecklistItem(id: '10', label: 'Horn/hooter'),
      FleetDailyChecklistItem(id: '11', label: 'All lights'),
      FleetDailyChecklistItem(id: '12', label: 'Check for oil/water leaks'),
      FleetDailyChecklistItem(id: '13', label: 'Heat gauge'),
      FleetDailyChecklistItem(id: '14', label: 'Battery level'),
    ],
    instructions: [
      'Have you checked the hand over log book for any problems or damages to the machine that you are about to use?',
      'REMEMBER: If you are the first person to use any machine on any shift you are required to complete this form first and then to thoroughly check the machine and report any machine defects, paint work, body damage etc.',
      'REMEMBER: To thoroughly check and go through the machine as per all the items on this form.',
      'REMEMBER: You must report noticeable damages to machine immediately (do not move the machine until it is reported).',
      'REMEMBER: Keys must not be left on the machine when the machine is not in use.',
    ],
    footerNotes: [
      'Engine and transmission oil is at Security.',
      'No 68 hydraulic oil is outside the stores.',
    ],
  );

  factory FleetDailyChecklistConfig.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final rawItems = data['items'] as List<dynamic>? ?? [];
    return FleetDailyChecklistConfig(
      enabled: data['enabled'] as bool? ?? true,
      items: rawItems
          .map((e) => FleetDailyChecklistItem.fromMap(
              Map<String, dynamic>.from(e as Map)))
          .toList(),
      instructions: (data['instructions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      footerNotes: (data['footer_notes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'enabled': enabled,
      'items': items.map((i) => i.toMap()).toList(),
      'instructions': instructions,
      'footer_notes': footerNotes,
      'updated_at': FieldValue.serverTimestamp(),
    };
  }

  FleetDailyChecklistConfig copyWithEnabled(bool value) {
    return FleetDailyChecklistConfig(
      enabled: value,
      items: items,
      instructions: instructions,
      footerNotes: footerNotes,
    );
  }
}

class FleetDailyChecklistItem {
  final String id;
  final String label;

  const FleetDailyChecklistItem({required this.id, required this.label});

  factory FleetDailyChecklistItem.fromMap(Map<String, dynamic> data) {
    return FleetDailyChecklistItem(
      id: data['id']?.toString() ?? '',
      label: data['label'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {'id': id, 'label': label};
}