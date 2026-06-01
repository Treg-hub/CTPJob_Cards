# Pilot Verification Checklist — WasteTrack Controlled Rollout (PROD-CRITICAL-4)

**Purpose**: Structured verification scaffolding for the security team controlled pilot of WasteTrack features inside the live CTP Job Cards app.  
**Scope**: Mobile (Flutter) + Web parity, feature flag controls, offline resilience, signature capture, deviation detection, admin recovery tools, and usage logging.  
**Target Users**: Security / pilot team (limited clock numbers), admins for config.  
**Environments**: Android release APK + https://ctp-job-cards.web.app (WasteTrack section)  
**Risk Posture**: Conservative — master flag + pilot list (PROD-CRITICAL-3 infra already in place). All changes behind role gates + explicit pilot CSV.  
**Date**: 2026-05-31  
**Version**: v1 (scaffolding for actual pilot execution)

> **Safety Rules for Pilot**
> - Only use designated pilot clock numbers (e.g. admin 22 + 2-3 test users).
> - Master flag starts ON; Pilot Mode ON for restricted access.
> - Always have recovery admin clock in pilot list.
> - Monitor `waste_usage_logs` collection in Firestore during pilot.
> - Keep screenshots / notes for every scenario.
> - Rollback: Toggle master flag OFF instantly via Admin screen (no app restart needed for most paths).

---

## 1. Pre-Pilot Setup & Admin Tools

- [ ] **Admin Access Verified**
  - Login as admin (clock 22 or authorized manager) on mobile + web.
  - Navigate to Waste Admin (from Waste Home quick action or dashboard).
  - Confirm "Rollout Safety Flag + Pilot Mode (Production Control)" card is visible with amber styling.

- [ ] **Master Flag State**
  - Record initial state of master flag (default true via SharedPreferences).
  - Toggle OFF → confirm WasteTrack entry points show disabled messaging.
  - Toggle back ON.

- [ ] **Pilot Mode Configuration**
  - Enable "Enable Pilot Mode" switch.
  - Enter CSV of pilot clocks: `22,105,207` (include your test users + at least one admin recovery clock).
  - Tap "Save Pilot Configuration".
  - Confirm log entry created in `waste_usage_logs` with action `admin_update_pilot_config`.
  - Note: Changes take effect on next screen load / action (SharedPreferences + service check).

- [ ] **Pilot User Onboarding**
  - For each pilot clock: confirm they see "WasteTrack is in pilot mode" banner (not full block) on Waste Home.
  - Non-pilot clock (test outside list): confirm hard block with "Your clock number ... is not included in the pilot list." + contact admin message.
  - Admin recovery: non-pilot admin can still enter Admin screen to adjust list (graceful degradation).

- [ ] **Usage Logging Baseline**
  - Open Firestore emulator or console → `waste_usage_logs`.
  - Verify entries appear for admin actions (`admin_update_pilot_config`, `admin_seed_data`, `admin_set_rate`).
  - Check `platform` field (mobile vs web).

- [ ] **Seeding / Test Data (Admin)**
  - Use admin "Seed Demo Data" button (if present) or manual create via Waste Create Load.
  - Confirm contractors, rates, and sample loads appear in lists/reports.
  - Log action `admin_seed_data` recorded.

**Pass Criteria**: Admin can fully control access without locking themselves out. All config changes logged.

---

## 2. Feature Flag Behavior

- [ ] **Master Flag OFF (Safety Valve)**
  - Any user (pilot or not): Waste Home / Create / Detail show clear disabled state.
  - "WasteTrack is currently disabled by feature flag" messaging.
  - No data writes possible (service throws early).
  - Toggle back ON → immediate re-enable on next navigation.

- [ ] **Pilot Mode ON + Master ON**
  - Pilot clocks: full access (home, create load with items+photos, pending weighbridge, reports, admin if role allows).
  - Non-pilot clocks: blocked at entry with specific pilot-list message.
  - Mixed: pilot user creates load → non-pilot cannot see or interact (enforced at service + UI).

- [ ] **Pilot Mode OFF (Full Access)**
  - All authenticated users with Waste role see full features (subject to existing role gates).

- [ ] **Persistence & Restart**
  - Change flags → kill app / restart → flags persist via SharedPreferences.
  - Web equivalent: (note localStorage or equivalent in pilot web UI).

- [ ] **Edge: Empty Pilot List**
  - Pilot mode ON + empty CSV → all users blocked except recovery path via Admin.

- [ ] **Logging on Flag Checks**
  - Every entry attempt by pilot/non-pilot logged (action includes context).

**Pass Criteria**: Flag system acts as reliable safety valve. No way for unauthorized user to bypass via deep link or rapid toggle. Logs are tamper-evident for audit.

---

## 3. Offline Photo Scenarios

- [ ] **Queue Photo While Offline (Create Load)**
  - Start new Waste Load on mobile.
  - Add Waste Item → take 1+ photo (camera or gallery).
  - Go airplane mode / disable WiFi+mobile data.
  - Save item / load.
  - Confirm UI shows "Some photos are queued for upload when back online." indicator (local path starts with `/`).
  - Confirm no crash, load appears in local/recent lists (Hive backed).

- [ ] **Process Queue on Reconnect**
  - Re-enable network.
  - Pull-to-refresh on Waste Home or open detail.
  - Observe console / logs: `[WasteService] Queued offline photo...` then processing attempt.
  - Verify photos eventually appear in Firebase Storage under `waste/{loadId or itemId}/photos/...` and URLs stored in doc.
  - Confirm Firestore doc updated (no duplicate uploads).

- [ ] **Mixed Online/Offline Photos**
  - Some items uploaded live, one item queued.
  - After reconnect: all photos visible in load detail (horizontal scroll / grid).
  - No data loss on sync.

- [ ] **Signature + Photo Offline Mix**
  - Complete load with signature while offline (if flow allows queuing) or note limitation.
  - Verify queued photos still processed independently.

- [ ] **Web Offline Note**
  - Web is primarily online; note any browser offline behavior as "future" in checklist (mobile primary for offline).

- [ ] **Resilience: Multiple Queued + App Kill**
  - Queue 3+ photos across items.
  - Force-close app.
  - Reopen + reconnect → all processed successfully.

**Pass Criteria**: Photos never lost. User always sees clear pending state. Sync is idempotent. No impact on core Job Cards offline paths.

---

## 4. Signature Flow

- [ ] **Capture Signature (Mobile)**
  - Complete a draft load → enter weighbridge (if required) or mark complete flow.
  - Tap signature capture (opens `WasteSignatureScreen`).
  - Draw signature with finger/stylus (black ink on white, 3px stroke).
  - Confirm "Clear" and "Save Signature" buttons.
  - Empty signature → snackbar "Please provide a signature".
  - Valid signature → returns Uint8List PNG bytes, screen pops.

- [ ] **Upload & Persist Signature**
  - On save: service calls `uploadSignature` → stores in Storage `waste_loads/{loadId}/signature/signature_{ts}.png`.
  - Firestore `waste_loads` doc updated with `driver_signature_url`.
  - Load detail shows signature (image preview) + "Load marked complete with signature!" green snackbar.

- [ ] **Signature in Reports / History**
  - Reports screen / PDF export includes driver signature reference (or note if demo-only).
  - Completed load in list shows signature indicator.

- [ ] **Error Handling**
  - Simulate Storage upload failure (e.g. bad auth) → graceful error, load still marked but signature noted as pending?
  - Retry path documented or admin recovery.

- [ ] **Web Parity**
  - If web supports signature capture (canvas), verify same upload path + display.
  - If web read-only for pilot: confirm signature visible from mobile-created loads.

- [ ] **Security**
  - Signature bytes never stored locally long-term (ephemeral in flow).
  - Only authorized roles can trigger completion+signature.

**Pass Criteria**: Signature is captured cleanly, uploaded reliably, visible in detail/reports, tied to specific load. Tamper resistant (Storage + URL in doc).

---

## 5. Deviation Alerts

- [ ] **Deviation Calculation (Pure Logic — `calculateDeviation`)**
  - Use harness or manual: recorded 100kg, actual 90kg → >5% → isDeviation true, variance ~ -10kg / -11%.
  - recorded 100, actual 160 → >50kg abs → true.
  - recorded 100, actual 102 → within both thresholds → false.
  - Custom thresholds respected (e.g. 10% / 20kg).
  - actual <=0 → no deviation (special case).

- [ ] **Weighbridge Entry Triggers Alert (Mobile)**
  - Create load with recorded items totaling X kg.
  - Complete load.
  - Later (pending weighbridge screen or detail): enter actual weighbridge weight that differs >5% OR >50kg.
  - Confirm deviation banner / dialog appears automatically ("Auto-show deviation after successful save").
  - Notes field or UI flags deviation (demo uses notes containing 'deviation' + count in reports).

- [ ] **Reports View**
  - Reports screen shows "Deviation Alerts (demo filter): N in current view".
  - PDF export includes deviation section.
  - Filter / search loads by deviation status.

- [ ] **Threshold Config (Admin)**
  - Admin screen mentions "Default deviation thresholds + notification config" (Phase 6+).
  - For pilot: verify current hard-coded 5% / 50kg used everywhere (deviation.dart + reports).

- [ ] **Cross Load Consistency**
  - Deviation visible in load detail, reports, and (future) notifications.
  - No false positives on small variances.

**Pass Criteria**: Deviation detection reliable and consistent. Alerts surface at weighbridge entry and in reporting. Pure function is deterministic and tested.

---

## 6. Cross Mobile-Web Consistency

- [ ] **Feature Parity Matrix (Pilot Users)**
  | Capability              | Mobile | Web   | Notes |
  |-------------------------|--------|-------|-------|
  | Waste Home / Lists      | Full   | Full  |       |
  | Create Load + Items + Photos | Full | Partial (photos upload) | |
  | Signature Capture       | Full   | TBD   | Mobile primary |
  | Weighbridge / Pending   | Full   | View  |       |
  | Deviation Display       | Full   | Full (demo) | |
  | Reports + PDF           | Full   | Full  |       |
  | Admin / Pilot Config    | Full   | Read or limited | Admin mobile preferred |
  | Usage Logs (platform field) | mobile | web   | Verify in Firestore |

- [ ] **Data Round-Trip**
  - Create load + items + photos on mobile → visible on web within seconds (Firestore real-time).
  - Enter weighbridge + signature on mobile → web reflects URLs and flags.
  - Create partial on web → mobile sees it.

- [ ] **Auth / Role / Flag Consistency**
  - Same pilot clock list (SharedPreferences on mobile; web should respect same Firestore-driven or config).
  - Pilot block messaging similar on both platforms.
  - Role derivation (department/position → waste access) identical.

- [ ] **Photo / Signature URLs**
  - Same Storage paths used.
  - Display works cross-platform (CORS handled for web images).

- [ ] **Logging**
  - Every action (create, complete, admin config, signature) writes to `waste_usage_logs` with correct `platform`.
  - Pilot team can query by platform during review.

**Pass Criteria**: No "works on mobile only" surprises for pilot users. Data and controls feel unified. Logs prove cross-platform activity.

---

## 7. General Pilot Execution & Daily Checks

1. Morning: Admin confirms master + pilot config correct. Check recent `waste_usage_logs`.
2. Pilot users perform 3-5 real or simulated loads (varied contractors, photo counts, weights).
3. Force offline scenarios at least once per device.
4. Capture 1+ signature per day.
5. Trigger 2+ deviation cases (high and low actual weights).
6. Review reports / PDF exports on both platforms.
7. End of day: Admin reviews logs for anomalies, toggles if needed.
8. Any blocker → immediate master flag OFF + incident note.

**Test Users Matrix** (fill during pilot):
- Pilot clocks: 22 (admin), ___, ___
- Non-pilot test: ___
- Devices: Android v___, browser ___

---

## 8. Recovery & Rollback Procedures

- **Instant Disable**: Admin opens Waste Admin → toggle master flag OFF. All users (including in-flight) see disabled state on next action.
- **Expand Pilot List**: Edit CSV → Save. No restart.
- **Data Recovery**: If bad load created, use admin "soft delete" or future hard delete flow (is_deleted flag).
- **Signature / Photo Recovery**: Storage objects remain; admin can re-link via Firestore edit (emergency).
- **Log Tampering**: Logs append-only; monitor for unexpected deletes (rules should prevent).
- **App Crash / Update During Pilot**: Update check still works (Remote Config). Pilot unaffected.
- **Escalation**: Contact on-call + screenshot + loadNumber + clockNo.

---

## 9. Logging, Monitoring & Audit

- Primary collection: `waste_usage_logs`
- Key actions to monitor: `admin_update_pilot_config`, load create/complete, `signature_upload`, photo queue/process, deviation events (future), any errors.
- Fields: action, clockNo, loadId, timestamp, platform, metadata.
- During pilot: security team runs ad-hoc queries or watches collection.
- Export logs at pilot end for sign-off report.

---

## 10. Sign-Off Criteria (for Pilot Completion / Promotion)

- [ ] All sections above passed with evidence (screenshots + log excerpts).
- [ ] Zero data loss in offline scenarios across 10+ photo queues.
- [ ] Signature flow 100% reliable (5+ captures).
- [ ] Deviation alerts trigger correctly on all threshold cases; no false positives in normal ops.
- [ ] Feature flag prevents unauthorized access 100% of attempts; admin never locked out.
- [ ] Mobile ↔ Web data parity verified for 20+ loads.
- [ ] Usage logs complete and queryable for entire pilot period.
- [ ] No crashes or unhandled errors in pilot user sessions.
- [ ] Rollback tested successfully at least once.
- [ ] Security team + product owner sign-off on this checklist.

**Pilot Lead Sign-off**: ________________ Date: ________  
**Security Reviewer**: ________________ Date: ________  
**Next Phase Recommendation**: ________________ (e.g. expand pilot / full rollout / adjustments)

---

## Appendix: Quick Command / Navigation Reference

- **Mobile Admin Entry**: Waste Home → "Open Waste Admin (pilot list / full controls)"
- **Run Existing Tests** (safe): `cd mobile/CTPJob_Cards && flutter test test/waste_deviation_test.dart test/waste_widget_smoke_test.dart`
- **Pilot Harness**: `flutter test test/pilot_verification_harness.dart` (see harness file for manual scenario runners + pure logic verification)
- **Firestore Rules Test** (backend): From repo root `npm run fb:test`
- **Web**: https://ctp-job-cards.web.app → login → Waste sections (role gated)

**Document Control**: This is living scaffolding. Update with pilot findings. Do not delete — archive dated copies after each pilot phase.

**Related**: See `waste_admin_screen.dart`, `waste_service.dart` (PROD-CRITICAL-3 rollout infra), `deviation.dart`, `waste_signature_screen.dart`, `waste_create_load_screen.dart` (offline notes), and `COLLECTIONS.md` for `waste_` prefix rules.

---
*Generated as part of PROD-CRITICAL-4 verification scaffolding. Safe location only (docs/ under mobile). No core files edited.*
