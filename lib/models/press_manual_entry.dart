import 'package:flutter/material.dart';

/// Where the bytes live.
enum PressManualSource {
  /// Small operator packs — bundled in the APK (markdown).
  bundledMarkdown,

  /// Full OEM PDFs — Firebase Storage; download into private app cache on demand.
  remotePdf,
}

/// One item in Press Manuals (short pack or OEM chapter).
class PressManualEntry {
  final String id;
  final String title;
  final String description;
  final String press;
  final IconData icon;
  final int sortOrder;
  final PressManualSource source;

  /// Bundled asset path (markdown only).
  final String? assetPath;

  /// Firebase Storage object path (PDF only), e.g. `press_manuals/aurora/…`.
  final String? storagePath;

  /// Expected size for UX + download progress (bytes).
  final int? sizeBytes;

  /// Optional integrity check after download.
  final String? sha256;

  final int? pageCount;

  /// UI section: short_packs | aurora_oem | badenia_oem
  final String section;

  const PressManualEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.press,
    required this.icon,
    required this.sortOrder,
    required this.source,
    required this.section,
    this.assetPath,
    this.storagePath,
    this.sizeBytes,
    this.sha256,
    this.pageCount,
  });

  bool get isRemotePdf => source == PressManualSource.remotePdf;
  bool get isBundledMarkdown => source == PressManualSource.bundledMarkdown;

  String get sizeLabel {
    final b = sizeBytes;
    if (b == null) return '';
    if (b < 1024 * 1024) {
      return '${(b / 1024).toStringAsFixed(0)} KB';
    }
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  bool matchesQuery(String q) {
    if (q.trim().isEmpty) return true;
    final n = q.trim().toLowerCase();
    return title.toLowerCase().contains(n) ||
        description.toLowerCase().contains(n) ||
        press.toLowerCase().contains(n) ||
        id.toLowerCase().contains(n);
  }
}

// ---------------------------------------------------------------------------
// Catalog: short packs (APK) + OEM PDFs (Storage on demand)
// ---------------------------------------------------------------------------

const List<PressManualEntry> pressManualCatalog = [
  // ----- Short packs (always offline, tiny) -----
  PressManualEntry(
    id: 'aurora_arl_safety',
    title: 'Aurora — Reelstand ARL safety',
    description: 'Auto vs Maint, scanners, barriers, never defeat safety.',
    press: 'Aurora',
    icon: Icons.warning_amber_rounded,
    sortOrder: 10,
    source: PressManualSource.bundledMarkdown,
    section: 'short_packs',
    assetPath: 'docs/press_manuals/aurora_arl_safety.md',
  ),
  PressManualEntry(
    id: 'aurora_cps_quick',
    title: 'Aurora — CPS console quick ref',
    description: 'Where to find slitters, folder, presets, tension.',
    press: 'Aurora',
    icon: Icons.monitor,
    sortOrder: 20,
    source: PressManualSource.bundledMarkdown,
    section: 'short_packs',
    assetPath: 'docs/press_manuals/aurora_cps_quick.md',
  ),
  PressManualEntry(
    id: 'badenia_folder_weekly_walk',
    title: 'Badenia — Folder weekly walk',
    description: 'Weekly checks for 5/5 & 7/7 folders, gates, gauges.',
    press: 'Badenia',
    icon: Icons.checklist_rtl,
    sortOrder: 30,
    source: PressManualSource.bundledMarkdown,
    section: 'short_packs',
    assetPath: 'docs/press_manuals/badenia_folder_weekly_walk.md',
  ),
  PressManualEntry(
    id: 'badenia_lube_rules',
    title: 'Badenia — Lubrication rules',
    description: 'Never mix greases/oils; over-grease flags; hour bands.',
    press: 'Badenia',
    icon: Icons.water_drop_outlined,
    sortOrder: 40,
    source: PressManualSource.bundledMarkdown,
    section: 'short_packs',
    assetPath: 'docs/press_manuals/badenia_lube_rules.md',
  ),
  PressManualEntry(
    id: 'badenia_safety_loto_basics',
    title: 'Badenia — Safety & isolation basics',
    description: 'Stop, isolate, guards — before hands-on work.',
    press: 'Badenia',
    icon: Icons.health_and_safety_outlined,
    sortOrder: 50,
    source: PressManualSource.bundledMarkdown,
    section: 'short_packs',
    assetPath: 'docs/press_manuals/badenia_safety_loto_basics.md',
  ),
  PressManualEntry(
    id: 'pressroom_job_card_quality',
    title: 'Pressroom — Job card quality',
    description: 'Machine / location / description that help maintenance.',
    press: 'All',
    icon: Icons.assignment_outlined,
    sortOrder: 60,
    source: PressManualSource.bundledMarkdown,
    section: 'short_packs',
    assetPath: 'docs/press_manuals/pressroom_job_card_quality.md',
  ),

  // ----- Aurora OEM (download on demand) -----
  PressManualEntry(
    id: 'oem_aurora_arl',
    title: 'Aurora — Reelstand ARL (full OEM PDF)',
    description: 'vR handling ARL — safety, alarms list, loading sequence (~26 pp).',
    press: 'Aurora',
    icon: Icons.picture_as_pdf_outlined,
    sortOrder: 100,
    source: PressManualSource.remotePdf,
    section: 'aurora_oem',
    storagePath: 'press_manuals/aurora/aurora_reelstand_arl_vr_handling.pdf',
    sizeBytes: 650401,
    pageCount: 26,
    sha256: '91554e0912783917ebc7446402e15238ea341db7cd0c9aa203a29e49591b0f76',
  ),
  PressManualEntry(
    id: 'oem_aurora_cps',
    title: 'Aurora — CPS / console handbook (full OEM PDF)',
    description: 'Cerutti R530 Job 4080 — HMI, slitters, folder, presets (~83 pp).',
    press: 'Aurora',
    icon: Icons.picture_as_pdf_outlined,
    sortOrder: 110,
    source: PressManualSource.remotePdf,
    section: 'aurora_oem',
    storagePath:
        'press_manuals/aurora/aurora_cerutti_r530_job4080_cps_handbook.pdf',
    sizeBytes: 10420965,
    pageCount: 83,
    sha256: 'a8539c11edc9f7bb7fbf106a16f28ce18c7ee45ec2dee2acb233e4d0ae49614a',
  ),

  // ----- Badenia OEM chapters (download on demand) -----
  PressManualEntry(
    id: 'oem_badenia_01_introduction_safety',
    title: 'Badenia — Introduction & general safety',
    description: 'Roles, IPD, residual risks (OEM ch.1).',
    press: 'Badenia',
    icon: Icons.picture_as_pdf_outlined,
    sortOrder: 200,
    source: PressManualSource.remotePdf,
    section: 'badenia_oem',
    storagePath:
        'press_manuals/badenia/chapters/badenia_01_introduction_safety.pdf',
    sizeBytes: 381211,
    pageCount: 20,
    sha256: 'b7080f74110136c23660b2ef61eafa3813b30bb5b415838c827315e86bf24daa',
  ),
  PressManualEntry(
    id: 'oem_badenia_02_working_principle',
    title: 'Badenia — Working principle',
    description: 'Process overview & supply identification (OEM ch.2).',
    press: 'Badenia',
    icon: Icons.picture_as_pdf_outlined,
    sortOrder: 210,
    source: PressManualSource.remotePdf,
    section: 'badenia_oem',
    storagePath:
        'press_manuals/badenia/chapters/badenia_02_working_principle.pdf',
    sizeBytes: 1099865,
    pageCount: 18,
    sha256: 'b279af6680e0e867dc2636f679f6cf2d9957785a854dbeefed6cdb59c950d348',
  ),
  PressManualEntry(
    id: 'oem_badenia_03_commands_controls',
    title: 'Badenia — Main commands & controls',
    description: 'Console panels and sequences (OEM ch.3).',
    press: 'Badenia',
    icon: Icons.picture_as_pdf_outlined,
    sortOrder: 220,
    source: PressManualSource.remotePdf,
    section: 'badenia_oem',
    storagePath:
        'press_manuals/badenia/chapters/badenia_03_commands_controls.pdf',
    sizeBytes: 9573362,
    pageCount: 34,
    sha256: '16551efe60d47bdacecb202128242a7f2652c6df6d526765ef98597aff3e82cf',
  ),
  PressManualEntry(
    id: 'oem_badenia_04_unwinder',
    title: 'Badenia — Unwinder PB125',
    description: 'Unwinder + lubrication + ordinary maintenance (OEM ch.4).',
    press: 'Badenia',
    icon: Icons.picture_as_pdf_outlined,
    sortOrder: 230,
    source: PressManualSource.remotePdf,
    section: 'badenia_oem',
    storagePath: 'press_manuals/badenia/chapters/badenia_04_unwinder_pb125.pdf',
    sizeBytes: 6150188,
    pageCount: 112,
    sha256: '0ee01c48a1f715bfc0a756a462344795ae56e07b7deb926bf9756df5168d56ad',
  ),
  PressManualEntry(
    id: 'oem_badenia_05_printing_unit',
    title: 'Badenia — Printing unit ES135',
    description: 'Units + lube + ordinary maintenance (OEM ch.5).',
    press: 'Badenia',
    icon: Icons.picture_as_pdf_outlined,
    sortOrder: 240,
    source: PressManualSource.remotePdf,
    section: 'badenia_oem',
    storagePath:
        'press_manuals/badenia/chapters/badenia_05_printing_unit_es135.pdf',
    sizeBytes: 14906290,
    pageCount: 142,
    sha256: 'd3654526a0a7ea21ec371b849a31ef904da143d706189f4aeb870209a9b4cfcc',
  ),
  PressManualEntry(
    id: 'oem_badenia_06_angle_bars',
    title: 'Badenia — Angle bars / pulling units',
    description: 'DT group (OEM ch.6).',
    press: 'Badenia',
    icon: Icons.picture_as_pdf_outlined,
    sortOrder: 250,
    source: PressManualSource.remotePdf,
    section: 'badenia_oem',
    storagePath: 'press_manuals/badenia/chapters/badenia_06_angle_bars_dt.pdf',
    sizeBytes: 8400000,
    pageCount: 64,
  ),
  PressManualEntry(
    id: 'oem_badenia_07_former',
    title: 'Badenia — Former unit',
    description: 'Former unit (OEM ch.7).',
    press: 'Badenia',
    icon: Icons.picture_as_pdf_outlined,
    sortOrder: 260,
    source: PressManualSource.remotePdf,
    section: 'badenia_oem',
    storagePath: 'press_manuals/badenia/chapters/badenia_07_former_unit.pdf',
    sizeBytes: 2820747,
    pageCount: 44,
    sha256: '85275adbf0e3c6cff1cc443872d02a4527ec5a7a28baa2c9931b16dca4c80b37',
  ),
  PressManualEntry(
    id: 'oem_badenia_08_folder_pv173',
    title: 'Badenia — Folder PV173 (5/5)',
    description: 'Folder + 500/3000/6000 h maintenance (OEM ch.8).',
    press: 'Badenia',
    icon: Icons.picture_as_pdf_outlined,
    sortOrder: 270,
    source: PressManualSource.remotePdf,
    section: 'badenia_oem',
    storagePath: 'press_manuals/badenia/chapters/badenia_08_folder_pv173.pdf',
    sizeBytes: 13426684,
    pageCount: 188,
    sha256: '4c7710fa8b5c113273ee433bbec29bb341556184a0ca1b7050b47990a6fd2052',
  ),
  PressManualEntry(
    id: 'oem_badenia_09_folder_pv157',
    title: 'Badenia — Folder PV157 (7/7)',
    description: 'Folder + 500/3000/6000 h maintenance (OEM ch.9).',
    press: 'Badenia',
    icon: Icons.picture_as_pdf_outlined,
    sortOrder: 280,
    source: PressManualSource.remotePdf,
    section: 'badenia_oem',
    storagePath: 'press_manuals/badenia/chapters/badenia_09_folder_pv157.pdf',
    sizeBytes: 11139697,
    pageCount: 196,
    sha256: '6ddb59f721b7e0f0bf4c167d246ac3468fea6b0224e224920c0bfef552b103af',
  ),
  PressManualEntry(
    id: 'oem_badenia_10_stitcher_cc143',
    title: 'Badenia — Stitcher CC143S (Folder 1)',
    description: 'Stitcher with PV173 (OEM ch.10).',
    press: 'Badenia',
    icon: Icons.picture_as_pdf_outlined,
    sortOrder: 290,
    source: PressManualSource.remotePdf,
    section: 'badenia_oem',
    storagePath: 'press_manuals/badenia/chapters/badenia_10_stitcher_cc143.pdf',
    sizeBytes: 6200000,
    pageCount: 64,
  ),
  PressManualEntry(
    id: 'oem_badenia_11_stitcher_cc137',
    title: 'Badenia — Stitcher CC137S (Folder 2)',
    description: 'Stitcher with PV157 (OEM ch.11).',
    press: 'Badenia',
    icon: Icons.picture_as_pdf_outlined,
    sortOrder: 300,
    source: PressManualSource.remotePdf,
    section: 'badenia_oem',
    storagePath: 'press_manuals/badenia/chapters/badenia_11_stitcher_cc137.pdf',
    sizeBytes: 4500000,
    pageCount: 56,
  ),
  PressManualEntry(
    id: 'oem_badenia_12_appendixes',
    title: 'Badenia — Appendixes & lubricant table',
    description: 'Lube equivalence and technical tables (OEM ch.12).',
    press: 'Badenia',
    icon: Icons.picture_as_pdf_outlined,
    sortOrder: 310,
    source: PressManualSource.remotePdf,
    section: 'badenia_oem',
    storagePath:
        'press_manuals/badenia/chapters/badenia_12_appendixes_lube_table.pdf',
    sizeBytes: 1211332,
    pageCount: 86,
    sha256: 'dfda80ead3ef953371a0015316a50b6970f37c610ba7443592e9f6379eb32069',
  ),
  PressManualEntry(
    id: 'oem_badenia_full',
    title: 'Badenia — Full handbook (large)',
    description:
        'Complete Cerutti R135 Job 3570 (~1040 pp / ~44 MB). Prefer chapters on mobile.',
    press: 'Badenia',
    icon: Icons.picture_as_pdf_outlined,
    sortOrder: 900,
    source: PressManualSource.remotePdf,
    section: 'badenia_oem',
    storagePath:
        'press_manuals/badenia/full/badenia_cerutti_r135_job3570_full.pdf',
    sizeBytes: 46512219,
    pageCount: 1040,
  ),
];

String pressManualSectionTitle(String section) {
  switch (section) {
    case 'short_packs':
      return 'Short packs (on device)';
    case 'aurora_oem':
      return 'OEM handbooks (download when opened)';
    case 'badenia_oem':
      return 'OEM chapters (download when opened)';
    default:
      if (section.endsWith('_oem')) {
        return 'OEM documents (download when opened)';
      }
      return section;
  }
}

/// Preferred tab order for known presses. New equipment appears after these
/// when present in [pressManualCatalog] (sorted by name).
const List<String> pressManualPreferredTabOrder = [
  'Aurora',
  'Badenia',
  'Wifag',
];

/// Label for cross-press docs (`press == 'All'`).
const String pressManualGeneralTab = 'General';

/// One top-level tab in the Press Manuals library.
class PressManualTab {
  final String id;
  final String label;

  const PressManualTab({required this.id, required this.label});

  /// Whether [entry] belongs on this tab.
  bool matches(PressManualEntry entry) {
    if (id == pressManualGeneralTab) {
      return entry.press == 'All' || entry.press.isEmpty;
    }
    return entry.press.toLowerCase() == id.toLowerCase();
  }
}

/// Builds press tabs from the catalog so new equipment appears automatically.
List<PressManualTab> buildPressManualTabs([
  List<PressManualEntry> catalog = pressManualCatalog,
]) {
  final presses = <String>{};
  var hasGeneral = false;
  for (final e in catalog) {
    if (e.press == 'All' || e.press.isEmpty) {
      hasGeneral = true;
    } else {
      presses.add(e.press);
    }
  }

  final ordered = <String>[];
  for (final p in pressManualPreferredTabOrder) {
    if (presses.remove(p)) ordered.add(p);
  }
  final rest = presses.toList()..sort();
  ordered.addAll(rest);

  final tabs = ordered
      .map((p) => PressManualTab(id: p, label: p))
      .toList(growable: true);
  if (hasGeneral) {
    tabs.add(
      const PressManualTab(
        id: pressManualGeneralTab,
        label: pressManualGeneralTab,
      ),
    );
  }
  return tabs;
}

/// Within a press tab, group by section (short packs first, then OEM).
List<String> pressManualSectionOrderFor(List<PressManualEntry> items) {
  final seen = <String>{};
  for (final e in items) {
    seen.add(e.section);
  }
  final order = <String>[];
  if (seen.remove('short_packs')) order.add('short_packs');
  final rest = seen.toList()..sort();
  order.addAll(rest);
  return order;
}
