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

  // Waste Types — flat production catalogue (no Paper Waste / Copper Waste parents)
  final types = [
    {'mainType': 'Reelends', 'subtypes': [], 'quantityLabels': {'default': 'Quantity (reels)'}},
    {'mainType': 'Slab Waste', 'subtypes': [], 'quantityLabels': {'default': 'Quantity (pallets)'}},
    {'mainType': 'Scrap Reels', 'subtypes': [], 'quantityLabels': {'default': 'Quantity (reels)'}},
    {'mainType': 'Copper Nuggets', 'subtypes': [], 'quantityLabels': {}},
    {'mainType': 'Copper Rods', 'subtypes': [], 'quantityLabels': {}},
    {
      'mainType': 'Copper Skins',
      'subtypes': [],
      'quantityLabels': {'default': 'Quantity (bins)'},
      'isFixedTareDualBin': true,
    },
    {'mainType': 'Open Bin', 'subtypes': [], 'quantityLabels': {}, 'noSiteWeight': true},
    {'mainType': 'Open Bin(Board K4)', 'subtypes': [], 'quantityLabels': {}, 'noSiteWeight': true},
    {
      'mainType': 'Compactor Bin',
      'subtypes': [],
      'quantityLabels': {'default': 'Quantity (bins)'},
      'noSiteWeight': true,
    },
    {
      'mainType': 'Scrap Metal',
      'subtypes': ['Scrap'],
      'quantityLabels': {},
      'noSiteWeight': true,
    },
    {'mainType': 'IBC Bins', 'subtypes': [], 'quantityLabels': {'default': 'Quantity (bins)'}, 'isQuantityOnly': true},
    {'mainType': 'Waste Bin', 'subtypes': [], 'quantityLabels': {'default': 'Quantity (bins)'}, 'isQuantityOnly': true},
    {
      'mainType': 'Used Oil',
      'subtypes': [],
      'quantityLabels': {'default': 'Litres'},
      'isQuantityOnly': true,
    },
    {
      'mainType': 'Contaminated Oil',
      'subtypes': [],
      'quantityLabels': {'default': 'Litres'},
      'isQuantityOnly': true,
    },
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
