import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/lurgi_daily_round.dart';
import '../providers/lurgi_drafts.dart';

/// Disk-backed Lurgi form drafts. Hydrate only when [dateKey] matches today.
class LurgiDraftStore {
  static const _prefix = 'lurgi.draft.v1.';

  static Future<void> saveSection(String sectionName, LurgiSectionFormDraft? d) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefix$sectionName';
    if (d == null || d.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(
      key,
      jsonEncode({
        'dateKey': lurgiDateKey(),
        'gasMech': d.gasMech,
        'gasElec': d.gasElec,
        'boiler': d.boiler,
        'softener': d.softener,
        'fresh': d.fresh,
        'effluent': d.effluent,
        'air1': d.air1,
        'air2': d.air2,
        'geyserTemp': d.geyserTemp,
        'geyserComments': d.geyserComments,
        'tank1': d.tank1,
        'tank2': d.tank2,
        'tank3': d.tank3,
        'tank1Dir': d.tank1Dir,
        'tank2Dir': d.tank2Dir,
        'tank3Dir': d.tank3Dir,
        'gasMechReset': d.gasMechReset,
        'gasElecReset': d.gasElecReset,
        'boilerReset': d.boilerReset,
        'softenerReset': d.softenerReset,
        'freshReset': d.freshReset,
        'effluentReset': d.effluentReset,
        'air1Reset': d.air1Reset,
        'air2Reset': d.air2Reset,
        'effectiveAtMs': d.effectiveAtMs,
        'spanComment': d.spanComment,
      }),
    );
  }

  static Future<LurgiSectionFormDraft?> loadSection(String sectionName) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$sectionName');
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (m['dateKey'] != lurgiDateKey()) {
        await prefs.remove('$_prefix$sectionName');
        return null;
      }
      return LurgiSectionFormDraft(
        gasMech: m['gasMech'] as String? ?? '',
        gasElec: m['gasElec'] as String? ?? '',
        boiler: m['boiler'] as String? ?? '',
        softener: m['softener'] as String? ?? '',
        fresh: m['fresh'] as String? ?? '',
        effluent: m['effluent'] as String? ?? '',
        air1: m['air1'] as String? ?? '',
        air2: m['air2'] as String? ?? '',
        geyserTemp: m['geyserTemp'] as String? ?? '',
        geyserComments: m['geyserComments'] as String? ?? '',
        tank1: m['tank1'] as String? ?? '',
        tank2: m['tank2'] as String? ?? '',
        tank3: m['tank3'] as String? ?? '',
        tank1Dir: m['tank1Dir'] as String?,
        tank2Dir: m['tank2Dir'] as String?,
        tank3Dir: m['tank3Dir'] as String?,
        gasMechReset: m['gasMechReset'] as bool? ?? false,
        gasElecReset: m['gasElecReset'] as bool? ?? false,
        boilerReset: m['boilerReset'] as bool? ?? false,
        softenerReset: m['softenerReset'] as bool? ?? false,
        freshReset: m['freshReset'] as bool? ?? false,
        effluentReset: m['effluentReset'] as bool? ?? false,
        air1Reset: m['air1Reset'] as bool? ?? false,
        air2Reset: m['air2Reset'] as bool? ?? false,
        effectiveAtMs: (m['effectiveAtMs'] as num?)?.toInt(),
        spanComment: m['spanComment'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveChemicals(LurgiChemicalsDraft? d) async {
    final prefs = await SharedPreferences.getInstance();
    const key = '${_prefix}chemicals';
    if (d == null || d.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(
      key,
      jsonEncode({
        'dateKey': lurgiDateKey(),
        'caustic': d.caustic,
        'hcl': d.hcl,
        'salt': d.salt,
        'naccolaint': d.naccolaint,
        'comments': d.comments,
        'effectiveAtMs': d.effectiveAtMs,
      }),
    );
  }

  static Future<LurgiChemicalsDraft?> loadChemicals() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${_prefix}chemicals');
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (m['dateKey'] != lurgiDateKey()) {
        await prefs.remove('${_prefix}chemicals');
        return null;
      }
      return LurgiChemicalsDraft(
        caustic: m['caustic'] as String? ?? '',
        hcl: m['hcl'] as String? ?? '',
        salt: m['salt'] as String? ?? '',
        naccolaint: m['naccolaint'] as String? ?? '',
        comments: m['comments'] as String? ?? '',
        effectiveAtMs: (m['effectiveAtMs'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveRecycling(LurgiRecyclingDraft? d) async {
    final prefs = await SharedPreferences.getInstance();
    const key = '${_prefix}recycling';
    if (d == null || d.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(
      key,
      jsonEncode({
        'dateKey': lurgiDateKey(),
        'steamTemp': d.steamTemp,
        'steamPress': d.steamPress,
        'litres': d.litres,
        'dirtyLevel': d.dirtyLevel,
        'cleaned': d.cleaned,
        'startAtMs': d.startAtMs,
        'finishAtMs': d.finishAtMs,
      }),
    );
  }

  static Future<LurgiRecyclingDraft?> loadRecycling() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${_prefix}recycling');
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (m['dateKey'] != lurgiDateKey()) {
        await prefs.remove('${_prefix}recycling');
        return null;
      }
      return LurgiRecyclingDraft(
        steamTemp: m['steamTemp'] as String? ?? '',
        steamPress: m['steamPress'] as String? ?? '',
        litres: m['litres'] as String? ?? '',
        dirtyLevel: m['dirtyLevel'] as String? ?? '',
        cleaned: m['cleaned'] as bool? ?? false,
        startAtMs: (m['startAtMs'] as num?)?.toInt(),
        finishAtMs: (m['finishAtMs'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}
