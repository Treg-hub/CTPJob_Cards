# Pilot Verification Checklist — Waste Recovery Controlled Rollout (PROD-CRITICAL-4)

**Purpose**: Structured verification scaffolding for the security team controlled pilot of Waste Recovery inside CTP Job Cards (mobile) + CTP Pulse (web admin).  
**Scope**: Mobile field capture, Pulse weighbridge/cost review, feature flag controls, offline resilience, signature capture, deviation detection, and usage logging.  
**Target Users**: Security / pilot team (limited clock numbers), admins for config on Pulse.  
**Environments**: Android release APK + https://ctp-job-cards.web.app (mobile) · https://ctp-pulse.web.app (Pulse admin)  
**Risk Posture**: Conservative — master flag + pilot list (PROD-CRITICAL-3 infra already in place). All changes behind role gates + explicit pilot CSV.  
**Date**: 2026-06-23 (updated for mobile/Pulse split)  
**Version**: v2

> **Architecture (22 June 2026)**
> - **Mobile (Job Cards)** — schedule, stock, collection, finish loading only.
> - **CTP Pulse** — weighbridge, cost review, reports, settings, import.
> - Removed from mobile: `waste_pending_weighbridge_screen`, `waste_review_screen`, `waste_reports_screen`, `waste_admin_screen`.

> **Safety Rules for Pilot**
> - Only use designated pilot clock numbers (e.g. admin 22 + 2-3 test users).
> - Master flag starts ON; Pilot Mode ON for restricted access.
> - Always have recovery admin clock in pilot list.
> - Monitor `waste_usage_logs` collection in Firestore during pilot.
> - Keep screenshots / notes for every scenario.
> - Rollback: Toggle master flag OFF via Pulse → Settings → Waste (or legacy mobile prefs if still wired).

---

## 1. Pre-Pilot Setup & Admin Tools

- [ ] **Admin Access Verified**
  - Login as admin (clock 22 or authorized manager) on mobile + Pulse.
  - Pulse: navigate to **Waste → Settings** and confirm waste module toggles visible.
  - Mobile: confirm **Loads** tab visible for pilot users.

- [ ] **Master Flag State**
  - Record initial state of master flag (`wasteTrackEnabled` / Pulse `waste_enabled`).
  - Toggle OFF → confirm Waste entry points show disabled messaging on mobile and Pulse.
  - Toggle back ON.

- [ ] **Pilot Mode Configuration**
  - Enable "Enable Pilot Mode" switch (mobile SharedPreferences path if still active).
  - Enter CSV of pilot clocks: `22,105,207` (include test users + at least one admin recovery clock).
  - Save configuration.
  - Confirm log entry in `waste_usage_logs` with action `admin_update_pilot_config` (if logging still wired).

- [ ] **Pilot User Onboarding**
  - Pilot clocks: see Loads tab and can schedule/collect.
  - Non-pilot clock: hard block with pilot-list message.
  - Admin recovery: admin can adjust pilot list on Pulse settings.

- [ ] **Usage Logging Baseline**
  - Open Firestore → `waste_usage_logs`.
  - Verify entries for load create/complete and admin config actions.
  - Check `platform` field (`mobile` vs `web`).

- [ ] **Seeding / Test Data**
  - Configure contractors, waste types, and rates in **Pulse → Settings → Waste**.
  - Create sample load via mobile schedule or on-the-spot flow.
  - Confirm load appears in Pulse **Loads** and pending queues as expected.

**Pass Criteria**: Admin can control access without locking themselves out. Config on Pulse; field capture on mobile.

---

## 2. Feature Flag Behavior

- [ ] **Master Flag OFF (Safety Valve)**
  - Any user (pilot or not): Waste tab / Pulse waste module show disabled state.
  - No data writes possible (service throws early).
  - Toggle back ON → re-enable on next navigation.

- [ ] **Pilot Mode ON + Master ON**
  - Pilot clocks: full **mobile field** access (schedule, stock, collect, finish loading).
  - Pilot managers/admins: Pulse weighbridge + cost review (role-gated).
  - Non-pilot clocks: blocked at entry with pilot-list message.

- [ ] **Pilot Mode OFF (Full Access)**
  - All authenticated users with Waste role see mobile field features (subject to role gates).

- [ ] **Photos Required / Signature Required (Pulse Settings)**
  - Toggle **Photos Required** ON → mobile item/stock/truck photos mandatory; Pulse load + stock forms respect toggle.
  - Toggle **Driver Signature Required** ON → signature mandatory on finish/submit.
  - Toggle OFF → photos/signature optional (loaded-truck photos still recommended).

- [ ] **Persistence & Restart**
  - Change flags → kill app / restart → mobile prefs persist.
  - Pulse settings persist in Firestore `waste_settings`.

**Pass Criteria**: Flag system acts as reliable safety valve. Settings toggles affect both platforms.

---

## 3. Offline Photo Scenarios

- [ ] **Queue Photo While Offline (Create Load)**
  - Start new load on mobile.
  - Add item → take photo; go offline.
  - Save item / load.
  - Confirm queued-upload indicator (local path).
  - No crash; load appears in local/recent lists.

- [ ] **Process Queue on Reconnect**
  - Re-enable network; pull-to-refresh or open detail.
  - Photos upload to Storage; URLs stored in Firestore.
  - No duplicate uploads.

- [ ] **Mixed Online/Offline Photos**
  - Some items uploaded live, one queued → all visible after sync.

- [ ] **Signature + Photo Offline Mix**
  - Verify signature/photo queue behaviour; note any limitations.

- [ ] **Resilience: Multiple Queued + App Kill**
  - Queue 3+ photos; force-close app; reopen + reconnect → all processed.

**Pass Criteria**: Photos never lost. Clear pending state. Idempotent sync.

---

## 4. Signature Flow

- [ ] **Capture Signature (Mobile)**
  - Finish collection or draft load → signature screen.
  - Draw signature; empty → validation error.
  - Valid signature → returns PNG, screen pops.

- [ ] **Upload & Persist Signature**
  - Storage path `waste_loads/{loadId}/signature/...`
  - Firestore `driver_signature_url` updated.
  - Load detail shows signature preview.

- [ ] **Settings Gate**
  - With **Signature Required** OFF: can submit without signature.
  - With ON: blocked until signature captured.

- [ ] **Pulse Finish Loading**
  - Draft load finished on Pulse **Loads → Edit** respects signature toggle.

**Pass Criteria**: Signature captured, uploaded, visible. Settings gate works on mobile and Pulse.

---

## 5. Deviation Alerts (Pulse Weighbridge)

- [ ] **Deviation Calculation**
  - recorded 100kg, actual 90kg → deviation (5% rule).
  - recorded 100, actual 160 → deviation (50 kg rule).
  - recorded 100, actual 102 → no deviation.
  - Custom thresholds from Pulse settings respected.

- [ ] **Weighbridge Entry Triggers Alert (Pulse)**
  - Mobile: complete load with recorded item weights.
  - Pulse → **Weighbridge**: enter actual weight differing > threshold.
  - Deviation written to `waste_audit`; visible on load detail and reports.

- [ ] **Quantity-Only Skip**
  - IBC Bins load: mobile submit → `pending_cost_review` directly (no weighbridge).
  - Pulse weighbridge queue does not list quantity-only loads.

- [ ] **Reports View (Pulse)**
  - `/waste/reports` shows deviation counts and export includes Deviation column.

**Pass Criteria**: Deviation reliable. Quantity-only skips weighbridge. Alerts on Pulse only.

---

## 6. Cross Mobile–Pulse Consistency

- [ ] **Feature Parity Matrix (Pilot Users)**
  | Capability | Mobile | Pulse | Notes |
  |------------|--------|-------|-------|
  | Schedule / create load | Full | Full | Pulse for manager corrections |
  | Stock capture | Full | Full | Paper stock on both |
  | Collection + items + photos | Full | Partial | Pulse new/edit load |
  | Signature | Full | Partial | Pulse finish loading |
  | Weighbridge | — | Full | Mobile handoff banner only |
  | Cost review | — | Full | Admin only |
  | Reports + export | — | Full | CSV/PDF on Pulse |
  | Settings / types / rates | — | Full | Pulse only |
  | Pending badges | Handoff banner | Sidebar + Board KPIs | Weighbridge + Review counts |

- [ ] **Data Round-Trip**
  - Create load on mobile → visible on Pulse within seconds.
  - Weighbridge + approve on Pulse → mobile detail shows completed + `cost_by_type`.
  - `selected_waste_types` preserved end-to-end.

- [ ] **Auth / Role / Flag Consistency**
  - Same pilot clock list enforced.
  - Security manager → Pulse weighbridge; admin → cost review.

- [ ] **Photo / Signature URLs**
  - Same Storage paths; display works cross-platform.

**Pass Criteria**: No "works on mobile only" surprises for admin steps. Data unified via Firestore.

---

## 7. General Pilot Execution & Daily Checks

1. Morning: Admin confirms master + pilot config on Pulse. Check `waste_usage_logs`.
2. Pilot users perform 3–5 loads (varied types: weight-based, quantity-only, multi-type).
3. Force offline scenario at least once per device.
4. Capture signature per settings.
5. Trigger 2+ deviation cases via Pulse weighbridge.
6. Admin approves cost on Pulse **Review** — verify `cost_by_type` on load detail.
7. Export reports CSV from Pulse for accounts spot-check.
8. Any blocker → master flag OFF + incident note.

---

## 8. Recovery & Rollback Procedures

- **Instant Disable**: Pulse Settings → Waste Recovery OFF (or mobile master flag).
- **Expand Pilot List**: Edit CSV → Save.
- **Bad Load**: Admin can cancel before completion; soft-delete (`is_deleted`) supported in backend — UI polish pending.
- **Signature / Photo Recovery**: Storage objects remain; admin can re-link via Firestore (emergency).
- **Escalation**: Contact on-call + screenshot + loadNumber + clockNo.

---

## 9. Logging, Monitoring & Audit

- Primary: `waste_usage_logs`, `waste_audit` (deviations)
- Monitor: load create/complete, weighbridge submit, cost approve, photo queue
- Export logs at pilot end for sign-off

---

## 10. Sign-Off Criteria

- [ ] All sections passed with evidence (screenshots + log excerpts).
- [ ] Zero data loss in offline scenarios (10+ photo queues).
- [ ] Signature flow reliable per settings (5+ captures).
- [ ] Deviation alerts correct; quantity-only skips weighbridge.
- [ ] Feature flag prevents unauthorized access; admin never locked out.
- [ ] Mobile ↔ Pulse parity for 20+ loads.
- [ ] Rollback tested at least once.

**Pilot Lead Sign-off**: ________________ Date: ________  
**Security Reviewer**: ________________ Date: ________

---

## Appendix: Quick Reference

| Task | Where |
|------|-------|
| Schedule / collect | Mobile → Loads tab |
| Weighbridge | Pulse → Waste → Weighbridge |
| Cost review | Pulse → Waste → Review |
| Settings / rates | Pulse → Waste → Settings |
| Reports | Pulse → Waste → Reports |
| Field guide | `docs/waste_user_guide.md` |
| Pulse guide | `docs/waste_pulse_guide.md` |

- **Tests**: `cd mobile/CTPJob_Cards && flutter test test/waste_deviation_test.dart`
- **Firestore rules**: `npm run fb:test` from monorepo root
- **Regenerate HTML guides**: `pwsh tools/build-docs.ps1` in CTPJob_Cards

**Related**: `waste_service.dart`, `waste_load_detail_screen.dart`, Pulse `actions.ts`, `costByType.ts`, `wasteTypeRouting.ts`, `COLLECTIONS.md`.

---
*Updated 23 June 2026 for mobile field capture + CTP Pulse admin split.*