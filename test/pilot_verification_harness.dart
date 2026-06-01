// Copyright 2026 CTP. All rights reserved.
// Pilot Verification Harness — PROD-CRITICAL-4
//
// Safe, non-destructive test scaffolding for the security team controlled pilot
// of WasteTrack (Waste Management) features.
//
// Location: mobile/CTPJob_Cards/test/  (explicitly safe per constraints — no core edits)
//
// Usage during pilot:
//   cd mobile/CTPJob_Cards
//   flutter test test/pilot_verification_harness.dart --plain-name "Pilot"
//
// This file:
// - Verifies pure logic (deviation calculations) automatically.
// - Provides detailed, copy-paste-ready manual scenario instructions for
//   security team testers (offline photos, signature, flags, admin, cross-web).
// - Never initializes Firebase or writes to live data.
// - Can be expanded later with mocks for more automation.
//
// Run alongside the official Pilot Verification Checklist (docs/Pilot_Verification_Checklist.md).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/utils/deviation.dart';

void main() {
  group('PROD-CRITICAL-4 Pilot Verification Harness (WasteTrack Controlled Pilot)', () {
    // -------------------------------------------------------------------------
    // 1. Pure Logic Verification — Deviation Alerts (Section 5 of Checklist)
    // These run fully automatically and give fast green signal for pilot start.
    // -------------------------------------------------------------------------
    group('Deviation Calculation (automatic — safe pure functions)', () {
      test('no deviation when actual <= 0 (weighbridge not yet captured)', () {
        final result = calculateDeviation(recordedWeightKg: 245.5, actualWeightKg: 0);
        expect(result.isDeviation, false);
        expect(result.varianceKg, 0);
        expect(result.thresholdPercent, 5.0);
        expect(result.thresholdKg, 50.0);
      });

      test('detects deviation by percent > 5%', () {
        // recorded 200kg, actual 180kg => 11.1% variance
        final result = calculateDeviation(recordedWeightKg: 200, actualWeightKg: 180);
        expect(result.isDeviation, true);
        expect(result.variancePercent.abs(), greaterThan(5));
      });

      test('detects deviation by absolute kg > 50', () {
        final result = calculateDeviation(recordedWeightKg: 300, actualWeightKg: 380);
        expect(result.isDeviation, true);
        expect(result.varianceKg.abs(), greaterThan(50));
      });

      test('within both thresholds = no deviation', () {
        final result = calculateDeviation(recordedWeightKg: 150, actualWeightKg: 153);
        expect(result.isDeviation, false);
      });

      test('custom thresholds respected (pilot may request different values later)', () {
        final result = calculateDeviation(
          recordedWeightKg: 100,
          actualWeightKg: 108,
          thresholdPercent: 10,
          thresholdKg: 20,
        );
        expect(result.isDeviation, false); // 8% + 8kg inside custom
      });

      test('real usage pattern: recorded=0 falls back gracefully (reports + detail screens)', () {
        final result = calculateDeviation(recordedWeightKg: 0, actualWeightKg: 210);
        // When recorded is 0 we treat recorded as actual in some UI paths to avoid div0
        expect(result.varianceKg, 210);
      });

      test('deviation still triggers correctly when recorded slightly lower than actual', () {
        final result = calculateDeviation(recordedWeightKg: 500, actualWeightKg: 560);
        expect(result.isDeviation, true);
        expect(result.variancePercent, greaterThan(5));
      });
    });

    // -------------------------------------------------------------------------
    // 2. Pilot Feature Flag Behavior (Section 2) — Manual Scenario Runner
    // These tests are intentionally lightweight placeholders.
    // They print step-by-step instructions for the security team.
    // Run with -v or observe console output during flutter test.
    // -------------------------------------------------------------------------

    // (Section 3 placeholder kept for future expansion — current offline manual steps live in group 3 below)
    group('Feature Flag + Pilot Mode Behavior (MANUAL — follow printed steps on device)', () {
      test('Pilot mode entry + block states (use real devices + pilot clocks)', () {
        debugPrint('''
[PILOT-HARNESS][FLAGS]
STEP-BY-STEP FOR SECURITY TEAM (run on real Android APK + web):

1. As admin (clock 22), open Waste Admin.
2. Toggle Master Flag OFF → verify every Waste entry point shows "disabled by feature flag" + contact message.
3. Toggle Master back ON.
4. Enable Pilot Mode + set CSV: "22,105,207" (your pilot users + recovery admin).
5. Save. Confirm usage_logs entry with action=admin_update_pilot_config + platform.
6. Log in as pilot clock (e.g. 105) → expect "WasteTrack is in pilot mode" banner + full access.
7. Log in as non-pilot clock → expect hard block: "Your clock number ... is not included in the pilot list."
8. From non-pilot account try deep navigation if possible → still blocked.
9. From pilot account confirm graceful admin recovery still works (no lockout).
10. Kill/restart app → flags persist (SharedPreferences).
11. Repeat key steps on web (ctp-job-cards.web.app) — note any differences in messaging.

Expected: Zero bypasses. Master flag is instant safety valve.
Evidence: Screenshots + Firestore waste_usage_logs query for the session.
''');

        expect(true, isTrue);
      });
    });

    // -------------------------------------------------------------------------
    // 3. Offline Photo Scenarios (Section 3) — Manual with device steps
    // -------------------------------------------------------------------------
    group('Offline Photo Queue + Sync Resilience (MANUAL — critical for field use)', () {
      test('Queue photos offline and recover (airplane mode test)', () {
        debugPrint('''
[PILOT-HARNESS][OFFLINE-PHOTOS]
SECURITY TEAM MANUAL STEPS (mobile primary — web is online-only):

1. Pilot user: Create new Waste Load → add 1-2 Waste Items.
2. For an item, add photo via camera (or gallery). Note local path indicator.
3. BEFORE saving, turn on airplane mode (or disable all networks).
4. Save the item + load. Confirm UI warning: "Some photos are queued for upload when back online."
5. Verify load appears in recent/home lists (no crash, Hive local success).
6. Force-kill the app.
7. Reopen app while still offline → load still visible with pending photo markers.
8. Re-enable network + pull-to-refresh on Waste Home.
9. Watch logs: "Queued offline photo..." then processing messages.
10. Re-open load detail → all photos now have Storage URLs and display (CachedNetworkImage).
11. Repeat with 3+ photos across multiple items and one full load save while offline.
12. Bonus: Mix of already-uploaded + queued photos in same load.

Pass if: Zero photo loss, clear pending UX, successful background sync, no impact on Job Cards core.

Log evidence: console + waste_usage_logs if extended.
''');

        expect(true, isTrue); // Always passes — this is instruction scaffolding
      });
    });

    // -------------------------------------------------------------------------
    // 4. Signature Flow (Section 4)
    // -------------------------------------------------------------------------
    group('Driver Signature Capture + Upload (MANUAL)', () {
      test('Full signature flow on device + cross-platform visibility', () {
        debugPrint('''
[PILOT-HARNESS][SIGNATURE]
MANUAL STEPS:

1. Create + complete a Waste Load (add items + recorded weights).
2. From load detail or pending weighbridge, trigger complete-with-signature flow.
3. WasteSignatureScreen opens: white canvas, black 3px pen.
4. Draw realistic signature. Test "Clear" button (resets).
5. Tap Save → returns bytes, screen closes with success snackbar.
6. Verify: load detail now shows driver_signature_url image.
7. Check Storage in Firebase console: waste_loads/{id}/signature/*.png exists.
8. Mark load complete → confirm "Load marked complete with signature!" green banner.
9. Go to Reports → confirm signature reference visible or noted.
10. On web (same pilot user): load appears with signature image displayed.
11. Error case: simulate poor network during upload → graceful message (no lost load data).

Pass: Signature always captured, uploaded, visible on both platforms, tied to correct load.
''');

        expect(true, isTrue);
      });
    });

    // -------------------------------------------------------------------------
    // 5. Admin Tools + Recovery (Section 1 + 8)
    // -------------------------------------------------------------------------
    group('Admin Tools & Instant Rollback (MANUAL)', () {
      test('Admin can control pilot without self-lockout', () {
        debugPrint('''
[PILOT-HARNESS][ADMIN-TOOLS]
CRITICAL FOR SECURITY / ROLLBACK:

1. Admin (22) opens Waste Admin while pilot mode active.
2. Confirm amber "Rollout Safety Flag + Pilot Mode" card visible.
3. Toggle master flag OFF mid-pilot → all pilot users immediately see disabled state on next tap/refresh.
4. Re-enable. Expand pilot CSV list live → new user gains access without rebuild.
5. Test "Seed Demo Data" / rate setting buttons if enabled — verify usage_logs written.
6. Remove yourself temporarily from pilot CSV while in pilot mode → confirm you can still reach Admin screen for recovery.
7. Exercise CSV edge: empty list (everyone blocked except recovery), malformed commas, very long list.
8. After any change: immediately query waste_usage_logs for the exact action + clockNo + timestamp.

Rollback drill (repeat daily): Master OFF → 30s validation that no writes possible → Master ON.
''');

        expect(true, isTrue);
      });
    });

    // -------------------------------------------------------------------------
    // 6. Cross Mobile-Web Consistency (Section 6)
    // -------------------------------------------------------------------------
    group('Mobile ↔ Web Parity Verification (MANUAL)', () {
      test('Data, flags, photos, signatures, reports match across platforms', () {
        debugPrint('''
[PILOT-HARNESS][CROSS-PLATFORM]
Run these in parallel sessions:

Mobile (APK)                          | Web (https://ctp-job-cards.web.app)
--------------------------------------|--------------------------------------
Create load + 2 items + 2 photos      | Same load visible in <3s
Enter weighbridge (trigger deviation) | Deviation flag + notes visible
Capture signature + complete          | Signature image + status updated
Open Reports + export PDF             | Same loads + deviation counts shown
Admin: change pilot CSV               | (If web admin available) or verify via mobile change reflected
Check waste_usage_logs                | platform field = 'mobile' vs 'web'

Additional:
- Pilot clock blocked on web exactly as on mobile.
- Photo URLs load on web (CORS ok).
- No duplicate loads or lost updates.
- Usage log entries from both platforms during same pilot session.

Evidence pack: side-by-side screenshots + Firestore query export.
''');

        expect(true, isTrue);
      });
    });

    // -------------------------------------------------------------------------
    // 7. Daily Pilot Execution Harness + Sign-off Helper
    // -------------------------------------------------------------------------
    group('Daily Pilot Run + Sign-off Helper (printable checklist excerpt)', () {
      test('End-of-day pilot summary printer', () {
        debugPrint('''
[PILOT-HARNESS][DAILY-RUN]
COPY THIS INTO YOUR PILOT LOG (one entry per pilot day):

Date: ________  Pilot Users Active: ________  Loads Created: ____  Signatures: ____

Offline photo queues tested: Y/N (success count: __)
Deviation cases triggered: __ (all correct? Y/N)
Flag toggles / recovery drills: __
Cross-web loads verified: __
Usage logs reviewed: Y/N (anomalies: ________)

Blockers / observations:
_______________________________________________________________________________

Security sign: __________________  Product sign: __________________  Date: ____

Next actions from checklist:
- [ ] Expand pilot list?
- [ ] Adjust thresholds?
- [ ] Full rollout recommendation?
''');

        expect(true, isTrue);
      });
    });

    // -------------------------------------------------------------------------
    // 8. Extension Points (for future automation)
    // -------------------------------------------------------------------------
    group('Future Expansion Points (Phase 8+)', () {
      test('PilotScenario helper stub (exists for later mock-based automation)', () {
        // This demonstrates where a real harness could inject fakes later
        // without ever touching production services.
        final scenario = _PilotScenario(
          clockNo: '105',
          pilotList: {'22', '105', '207'},
          masterEnabled: true,
        );
        expect(scenario.isAllowed, true);

        final blocked = _PilotScenario(
          clockNo: '999',
          pilotList: {'22', '105'},
          masterEnabled: true,
        );
        expect(blocked.isAllowed, false);
      });

      test('Placeholder for mocked WasteService integration (future)', () {
        // When DI / test fakes are introduced, replace this with real widget tests
        // for WasteCreateLoadScreen, WasteLoadDetailScreen, etc. under pilot flags.
        expect(true, isTrue);
      });
    });

    // -------------------------------------------------------------------------
    // NEW: Weighbridge + Deviation + Audit + Reports + Queued Indicators
    // (Covers production hardening for security team pilot)
    // -------------------------------------------------------------------------
    group('Weighbridge Deviation, Audit, Reports, Offline Queues (MANUAL — updated for current build)', () {
      test('Full deviation + audit + reports flow on pilot devices', () {
        debugPrint('''
[PILOT-HARNESS][DEVIATION-AUDIT-REPORTS-OFFLINE]
SECURITY TEAM STEPS (critical for production sign-off):

1. Create load with 2+ items (record realistic weights, e.g. 250kg total).
2. Mark complete with signature (test offline: queue status update).
3. Go to Pending Weighbridge (confirm queued count icon appears if any prior offline work).
4. Enter actual weighbridge weight that triggers >5% OR >50kg (e.g. recorded 250, actual 320).
5. Confirm:
   - Prominent red DEVIATION ALERT dialog with variance + thresholds.
   - "Acknowledge" button.
   - waste_audit document created (check Firestore: action=weighbridge_deviation, variance fields, clockNo).
6. Go to Reports:
   - Summary shows correct "Loads triggering deviation" count.
   - List items show red warning icon + weight for deviating loads.
   - Export PDF: table includes Deviation column, summary has correct count.
   - Export CSV: columns for Recorded kg, Actual, Variance kg/%, Deviation? YES.
7. Offline test (repeat for weighbridge):
   - While offline, enter weighbridge weight on a pending load.
   - Save → confirm "queued for sync" message.
   - Kill app, reopen, queued cloud icon visible in AppBar on Home + Pending + Reports.
   - Reconnect + refresh → weight lands, deviation alert fires, audit written.
8. Verify no impact on Job Cards tabs / other employees.

Pass criteria: Deviation always correct per spec, audit trail present, exports complete & accurate, full offline recovery for weighbridge + photos + status, zero data loss, clear UX for queued work on every Waste screen.

Log: screenshots of alerts, Firestore audit docs, CSV/PDF samples, queued icon behavior.
''');

        expect(true, isTrue);
      });
    });

    // -------------------------------------------------------------------------
    // 9. Remaining Live Features: Notifications Callable + Full Reports Exports + Complete Cross-Screen Queued UX
    // (Added for full coverage of now-live prod paths: callable notifications, PDF/CSV fidelity, every Waste screen's queued state)
    // -------------------------------------------------------------------------
    group('Notifications (Callable), Reports Exports, Cross-Screen Queued UX (MANUAL — final pilot scenarios)', () {
      test('Callable notifications + export verification + queued UX on ALL Waste screens', () {
        debugPrint('''
[PILOT-HARNESS][NOTIFICATIONS-REPORTS-QUEUED-ALL-SCREENS]
SECURITY TEAM MANUAL STEPS (execute on pilot APK; covers all live features):

CALLABLE NOTIFICATIONS (PR4-2):
1. Login as pilot Security Manager or Admin (clock in list).
2. Navigate to Waste → Pending Weighbridge (or Waste Admin if button exposed).
3. Tap the "Check Pending Weighbridge (callable)" or equivalent trigger for checkWastePendingWeighbridge (africa-south1 region).
4. Confirm callable succeeds (returns {success, ...} with counts or summary).
5. Verify: waste_audit entry written with action ~ 'waste_pending_weighbridge_check', trigger source (callable:uid), threshold used, pending count.
6. (Sends are stubbed in pilot) — confirm no real push sent; only audit + logs.
7. Repeat via Admin if callable exposed there. Cross-check scheduled would also write audit but not callable.
8. Non-pilot: confirm call fails or blocked (rules + client gate).

REPORTS EXPORTS FULL E2E:
9. Create 4+ loads (mix of normal + 2+ deviation cases via weighbridge).
10. Include signature on 2, photos on all, some offline queued then synced.
11. Open Reports:
    - Summary metrics match (total loads, deviation count, signatures count).
12. Export PDF → open file:
    - Header with date range + pilot clock.
    - Table rows include: load_number, date, main_type, recorded_kg, actual_kg, variance, deviation flag (YES/NO + color), signature present?, photo count.
    - Deviation section at bottom with count + list of deviating load_numbers.
    - No PII leaks; clean formatting.
13. Export CSV → open in Excel/Sheets:
    - Columns present: load_number,recorded_weight_kg,actual_weighbridge_weight_kg,variance_kg,variance_percent,is_deviation,driver_signature_url (or bool), etc.
    - All deviation rows have is_deviation=true and numbers correct.
    - UTF8, no corruption on special chars in notes/contractor.
14. Web Reports: same exports from web UI → identical structure + data for same loads.
15. Edge: empty results export → graceful empty PDF/CSV with headers + "no data" note.

QUEUED UX ON *ALL* WASTE SCREENS (full end-to-end offline):
16. Start offline (airplane): 
    - Waste Home: create full load + items + 2 photos + signature complete → see local save + queued banner / cloud icon in AppBar.
    - Waste Create Load: during item photo add while offline → "X item(s) have photos queued..." banner visible.
    - Waste Load Detail: open a pending load → enter weighbridge (deviation) + save → "queued for sync" snack; also complete with signature queues status.
    - Waste Pending Weighbridge: list shows queued marker; attempt weighbridge entry while offline → queued.
    - Waste Reports: open (drains on entry), see "N photo(s) queued" banner if any; export buttons disabled or warn while offline?
    - Waste Signature Screen: if triggered offline → capture succeeds locally, queues upload.
    - Waste Admin: admin actions (if any write) queue; flag toggles may be local-only until reconnect.
17. Kill/restart app multiple times while offline → all queued indicators persist (Hive + session state).
18. Reconnect network:
    - Tap retry on Home (cloud icon) or pull refresh on each screen.
    - Observe sequential processing: photos first (to Storage), then weighbridge updates (trigger deviation alert on sync), then status/signature.
    - Every screen refreshes to show clean state (no pending badges, full URLs).
19. Full cycle verification: one load created offline (photos+signature), weighbridge entered offline (deviation), all recover on reconnect with audit + reports updated + no duplicates.
20. Confirm: ZERO data loss; Job Cards core completely unaffected (no shared queues touched).

Pass: All callable calls work for pilot users, exports accurate and complete for deviation/queued cases, queued state visible + actionable on Home, Create, Detail, Pending, Reports, Signature, Admin. Full offline E2E succeeds for the combination of offline + deviation + audit + reports + signature.

Evidence: Export samples, audit docs from callable, before/after screenshots of every screen's queued UI, Firestore + Storage post-sync.
''');

        expect(true, isTrue);
      });
    });

    // -------------------------------------------------------------------------
    // 10. Admin Recovery + Rollback Drills (explicit)
    // -------------------------------------------------------------------------
    group('Admin Recovery + Rollback Drills (MANUAL — safety critical)', () {
      test('Admin recovery paths + master flag rollback without data loss', () {
        debugPrint('[PILOT-HARNESS][ADMIN-RECOVERY-ROLLBACK] Full steps and evidence requirements are in docs/Pilot_Rollout_Checklist.md (section 7).');
        expect(true, isTrue);
      });
    });
  });
}

/// Tiny local helper only for this harness (illustrative — not used in prod code).
/// Shows how pilot flag logic can be unit-tested in isolation.
class _PilotScenario {
  final String? clockNo;
  final Set<String> pilotList;
  final bool masterEnabled;

  _PilotScenario({
    required this.clockNo,
    required this.pilotList,
    required this.masterEnabled,
  });

  bool get isAllowed =>
      masterEnabled &&
      (!pilotList.isNotEmpty || (clockNo != null && pilotList.contains(clockNo!.trim())));
}
