import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-session drafts for Lurgi capture forms. Survive Navigator pop/push until
/// cleared after a successful save (or when the form is empty on dispose).
///
/// Section drafts are keyed by [LurgiSection.name] (`utilities`, `tanks`, …).

// ── Morning section form ────────────────────────────────────────────────────

class LurgiSectionFormDraft {
  const LurgiSectionFormDraft({
    this.gasMech = '',
    this.gasElec = '',
    this.boiler = '',
    this.softener = '',
    this.fresh = '',
    this.effluent = '',
    this.air1 = '',
    this.air2 = '',
    this.geyserTemp = '',
    this.geyserComments = '',
    this.tank1 = '',
    this.tank2 = '',
    this.tank3 = '',
    this.tank1Dir,
    this.tank2Dir,
    this.tank3Dir,
    this.gasMechReset = false,
    this.gasElecReset = false,
    this.boilerReset = false,
    this.softenerReset = false,
    this.freshReset = false,
    this.effluentReset = false,
    this.air1Reset = false,
    this.air2Reset = false,
    this.effectiveAtMs,
  });

  final String gasMech;
  final String gasElec;
  final String boiler;
  final String softener;
  final String fresh;
  final String effluent;
  final String air1;
  final String air2;
  final String geyserTemp;
  final String geyserComments;
  final String tank1;
  final String tank2;
  final String tank3;
  final String? tank1Dir;
  final String? tank2Dir;
  final String? tank3Dir;
  final bool gasMechReset;
  final bool gasElecReset;
  final bool boilerReset;
  final bool softenerReset;
  final bool freshReset;
  final bool effluentReset;
  final bool air1Reset;
  final bool air2Reset;
  final int? effectiveAtMs;

  bool get isEmpty {
    bool blank(String s) => s.trim().isEmpty;
    return blank(gasMech) &&
        blank(gasElec) &&
        blank(boiler) &&
        blank(softener) &&
        blank(fresh) &&
        blank(effluent) &&
        blank(air1) &&
        blank(air2) &&
        blank(geyserTemp) &&
        blank(geyserComments) &&
        blank(tank1) &&
        blank(tank2) &&
        blank(tank3) &&
        tank1Dir == null &&
        tank2Dir == null &&
        tank3Dir == null &&
        !gasMechReset &&
        !gasElecReset &&
        !boilerReset &&
        !softenerReset &&
        !freshReset &&
        !effluentReset &&
        !air1Reset &&
        !air2Reset;
  }
}

/// One draft per morning section tile (`utilities`, `tanks`, `all`, …).
final lurgiSectionFormDraftProvider =
    StateProvider.family<LurgiSectionFormDraft?, String>(
  (ref, sectionName) => null,
);

// ── Effluent chemicals (add-entry form only) ────────────────────────────────

class LurgiChemicalsDraft {
  const LurgiChemicalsDraft({
    this.caustic = '',
    this.hcl = '',
    this.salt = '',
    this.naccolaint = '',
    this.comments = '',
    this.effectiveAtMs,
  });

  final String caustic;
  final String hcl;
  final String salt;
  final String naccolaint;
  final String comments;
  final int? effectiveAtMs;

  bool get isEmpty =>
      caustic.trim().isEmpty &&
      hcl.trim().isEmpty &&
      salt.trim().isEmpty &&
      naccolaint.trim().isEmpty &&
      comments.trim().isEmpty;
}

final lurgiChemicalsDraftProvider =
    StateProvider<LurgiChemicalsDraft?>((ref) => null);

// ── Recycling run form ──────────────────────────────────────────────────────

class LurgiRecyclingDraft {
  const LurgiRecyclingDraft({
    this.steamTemp = '',
    this.steamPress = '',
    this.litres = '',
    this.dirtyLevel = '',
    this.cleaned = false,
    this.startAtMs,
    this.finishAtMs,
  });

  final String steamTemp;
  final String steamPress;
  final String litres;
  final String dirtyLevel;
  final bool cleaned;
  final int? startAtMs;
  final int? finishAtMs;

  bool get isEmpty =>
      steamTemp.trim().isEmpty &&
      steamPress.trim().isEmpty &&
      litres.trim().isEmpty &&
      dirtyLevel.trim().isEmpty &&
      !cleaned;
}

final lurgiRecyclingDraftProvider =
    StateProvider<LurgiRecyclingDraft?>((ref) => null);
