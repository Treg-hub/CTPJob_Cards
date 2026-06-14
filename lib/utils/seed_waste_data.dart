// One-time seeding helper for WasteTrack data.
// In production this would be run once by an Admin or via a Cloud Function / script.
//
// Seeds:
// - 4 contractors (Glenpak, Mondi, Industrial Scrap Waste, Mauser)
// - Core waste types per spec (Copper Waste, Paper Waste, etc. with subtypes)
// - Default waste_settings (5% / 50kg thresholds)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../constants/collections.dart';

Future<void> seedWasteData() async {
  final db = FirebaseFirestore.instance;

  // Contractors
  final contractors = [
    {'name': 'Glenpak', 'contact': 'glenpak@example.com'},
    {'name': 'Mondi', 'contact': 'mondi@example.com'},
    {'name': 'Industrial Scrap Waste', 'contact': 'isw@example.com'},
    {'name': 'Mauser', 'contact': 'mauser@example.com'},
  ];

  for (final c in contractors) {
    await db.collection(Collections.wasteContractors).add(c);
  }

  // Waste Types (per spec §5)
  final types = [
    {
      'mainType': 'Copper Waste',
      'subtypes': ['Nuggets', 'Rods'],
      'quantityLabels': {},
    },
    {
      'mainType': 'Paper Waste',
      'subtypes': ['Reelends', 'Slab Waste', 'Reels'],
      'quantityLabels': {
        'Reelends': 'Quantity (reels)',
        'Reels': 'Quantity (reels)',
        'Slab Waste': 'Quantity (pallets)',
      },
    },
    {'mainType': 'Open Bin', 'subtypes': [], 'quantityLabels': {}},
    {'mainType': 'Compactor Bin', 'subtypes': [], 'quantityLabels': {}},
    {'mainType': 'Scrap Metal', 'subtypes': [], 'quantityLabels': {}},
    {'mainType': 'Copper Skins', 'subtypes': [], 'quantityLabels': {}},
    {'mainType': 'IBC Bins', 'subtypes': [], 'quantityLabels': {'default': 'Quantity (bins)'}, 'isQuantityOnly': true},
  ];

  for (final t in types) {
    await db.collection(Collections.wasteTypes).add(t);
  }

  // Default settings
  await db.collection(Collections.wasteSettings).doc('global').set({
    'deviationPercent': 5,
    'deviationKg': 50,
    'notificationConfig': {
      'adminOnComplete': true,
      'managerPendingWeighbridgeDays': 3,
    },
  });

  // Sample rates (Phase 3 admin tools demo data)
  final sampleRates = [
    {'contractor_id': 'Glenpak', 'subtype': 'Nuggets', 'cost_per_kg': 12.50, 'set_by': 'seed'},
    {'contractor_id': 'Mondi', 'subtype': 'Reelends', 'cost_per_kg': 3.25, 'set_by': 'seed'},
    {'contractor_id': 'Industrial Scrap Waste', 'subtype': 'default', 'cost_per_kg': 8.75, 'set_by': 'seed'},
  ];
  for (final r in sampleRates) {
    await db.collection(Collections.wasteRates).add({
      ...r,
      'set_at': FieldValue.serverTimestamp(),
    });
  }

  debugPrint('WasteTrack seed data inserted successfully (incl. sample rates).');
}
