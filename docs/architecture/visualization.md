# CTP Job Cards — Architecture & Role-Based Access

**This is a primary "canvas" for the CTP Architecture Map (scannable tables + flows for board presentations).**

_Last updated: 2026-06-28 (DeviceHealthService — six permission checks synced to employees.permissions; expanded home health banner; admin targeted broadcast via broadcastUpdateNotice clockNos[])._

**Cross-links (load these few targeted files for AI efficiency + full map):**
- Monorepo overview + deploy: `../../../docs/ARCHITECTURE.md`, `../../../README.md`, `../../../docs/COLLECTIONS.md`
- Rich notes index: `../memory-bank/activeContext.md` + systemPatterns.md / decisions.md / techContext.md / learnings.md
- Gating / CF split details: monorepo `firebase/firestore.rules` (Wave B, admins, ink tier, notification_inbox) + `firebase/test/firestore.rules.test.ts`
- Pulse surface: monorepo `web/ctp-pulse/src/features/board/components/JobCardsModule.tsx` + `useJobCardMetrics.ts` (KPIs/read-only) + page.tsx (boardModules)
- Ink: `../../../docs/Ink_Factory_Migration_Plan.md` + collections.dart (ink_*) + rules ink tier (replay/server authoritative)
- Number assignment, copper, geofence, notif services: this file + rules + COLLECTIONS.md
- AGENTS instructions: `AGENTS.md`, `CLAUDE.md` (this repo), monorepo Instructions for AI Agents.md (draft)
- **Phase 8 small focused notes** (admins / inbox / deploy specifics): `../../../Components/admins-collection.md`, `../../../Components/notification-inbox-specifics.md`, `../../../Components/deploy-discipline.md`
- **Phase 8 polish + checklist**: `../../../docs/POLISH-CHECKLIST.md`, `../../../Instructions for AI Agents.md` (load order + cross-link strategy + update discipline)
- **Visual canvases / Excalidraw integration (Phase 8)**: `../../../Canvases/06-data-flows.canvas.md` (full flows incl. notifs/presence/ink), `../../../Canvases/07 - Dependencies.canvas`, new `../../../Canvases/01-auth-gating-flow.excalidraw.md` etc (see Recommended Excalidraw below for the 5). Use for board exports.
- Sync note: dev-docs/architecture/visualization.md is older dupe — keep in sync or delete after merge. **Primary = this file only for edits.** See also monorepo `Components/monorepo-structure.md`.

**Presentation notes**: Tables for quick scan. Update mermaid + matrices on role/module changes. For Excalidraw: extract sections below into visual canvases (see task proposals).

---

## Role System

Roles are **derived** from `Employee.position` and `Employee.department` (see `lib/utils/role.dart`). The **Admin** role is the only exception — it is controlled by the `isAdmin` boolean field on each employee's Firestore document rather than their position string.

| Role | Derived from | Key capabilities |
|---|---|---|
| **Admin** | `Employee.isAdmin == true` (Firestore field) | Full access to all screens + admin controls, module toggles |
| **Security Manager** | dept=`security`, pos=`manager` | Schedule loads, view all loads, reports, pending weighbridge, cancel scheduled |
| **Security Guard** | dept=`security`, pos=`guard` (+ `guard_clock_nos`) | Waste + Security tabs only — no job-card home or My Work; Home hub links to modules; auto-lands on Security tab |
| **Technician** | pos contains `mechanical`/`electrical`/`technician` | Job cards only |
| **Manager** (job cards) | pos contains `manager` | Job card manager dashboard |
| **Operator** | neither manager nor technician | Limited job card actions |
| **Building Maintenance** | pos contains `building maintenance` | Receives Building Maintenance type job cards |
| **Pre Press Specialist** | dept=`Pre Press`, pos contains `specialist` | Receives Pre Press Spec type job cards |
| **Fleet Mechanic** | dept=`Workshop`, pos=`Hyster Mechanic` | Log work, acknowledge/resolve issues (no cost amounts) |
| **Fleet Reporter** | dept ∈ `fleet_settings.reporter_departments` | Report fleet issues, view own issues |
| **Fleet Cost Manager** | `clockNo` ∈ `fleet_settings.cost_manager_clock_nos` | **Pulse only** — optional cost linking, reports, CSV (no mobile Fleet tab) |
| **Fleet Admin** | `Employee.isAdmin == true` | Manage asset register + Fleet settings + all of the above |

> **To grant Admin:** Set `isAdmin: true` on the employee's Firestore document. No code change or app release required.

**Module Gating (2026-06 updates)**:
- Job Cards core: always (mobile branding primary).
- Waste / Fleet: gated by settings flags + role derivation (see permission matrices below + role.dart).
- Copper: hardcoded whitelist (clock 22/5421/20) in role.dart + HomeScreen tab visibility. Part of "copper service".
- Ink Factory: mobile data entry gated by `department == "Ink Factory"` (tile like Fleet). **Pulse** also has an Ink module (claims `boardModules: 'ink'`, manager/admin): stock/ledger/report KPIs **plus** shipments + landed-cost (`/ink/shipments` → drag-drop PDFs → `parseInkShipmentDoc` → review; GRN saved to shipment before FX rate via `saveShipmentSourceDocs` → rate/duty → push per-colour cost). Inbound list shows CGNA. See `docs/Ink_Receiving_Costing_Plan.md` + `public/docs/ink/manager.md`.
- Geofence / Notifications / Presence (core services): always-on for signed-in (geofence auto in background, presence updates employees.isOnSite/fcm, feeds notification_inbox + escalation). See rules + geofence_editor in Admin.

**Detailed Module Screens & User Flows (Phase 8 map enhancement)**:
For exact screens per module, what each does (purpose, reads/writes, UI), and user flows for users with access (role-specific step-by-step):
- See the separate Architecture Map in `../../../CTP-Factory-System-Map/` (sibling folder, open as own Obsidian vault or add to this one).
  - `Canvases/04 - Module Breakdown.canvas` (visual groups for Mobile/Pulse, nodes with access, key screens summaries, flows per role, links to detailed notes).
  - `Components/Modules/JobCardsCoreModule.md`, `WasteModule.md`, `FleetModule.md`, `InkModule.md`, `PulseModules.md` (full "Detailed Screens Catalog" tables with exact files from code, purposes/what it does, access, reads from, writes to/triggers, notes; "User Flows by Access Level" with numbered steps per role like Mechanic/Reporter/Cost Mgr/Guard/Admin; Mermaid diagrams for flows; Dataview tags like `module: fleet`, `access: mechanic`; cross-refs to collections, CFs, rules, canvases).
  - `Canvases/INDEX.md` for navigation + board tips.
  - `Components/Modules/Module Allocation & Visibility.md` for gating overview.
- In this viz, use the permission matrices below for high-level access; drill to the map for per-screen details and "what links with what / reads from / does" (edges in canvas, relationships sections in notes, Graph view for links, backlinks for dependencies).
- To visualize: Canvas 04 for overview (groups, nodes for screens/flows, clickable links, labeled edges for "user with access -> screen X -> reads Y collection -> writes via CF Z"). Notes for tables + Mermaid flows (render in Obsidian, text for maintainability/git/AI edits, export images). Graph view (filter by path "Modules/", local graph on a note to see reads/writes links). Embed Mermaid in canvas text nodes or use Excalidraw specs (the 5 Phase 8 ones for cross-flows; extend for per-module journeys).
- Maintainable: Text-based (md, canvas JSON, Mermaid code, frontmatter for Dataview queries e.g. "TABLE title FROM \"Components/Modules\" WHERE module = \"fleet\""). Update when code adds screen (add row to table in note, node text in canvas, Mermaid if flow changes, sources/citations; touch related canvases + small notes + POLISH-CHECKLIST + run fb:test if rules/CF; re-export visuals). See POLISH-CHECKLIST.md and Instructions for AI Agents.md (load order #1-8, richer notes strategy, strict 10-step update discipline, cross-links everywhere). 

**Permission Matrices (high-level access per module; see map notes for per-screen details and flows)**:
- Pulse (external): boardModules claim (not in this mobile viz; see monorepo Pulse canvases).

**Legacy note**: Old web views fully removed; this mobile + Pulse are current.

> Fleet **Reporter** and **Cost Manager** are config-driven (read from `fleet_settings/config`), unlike all other roles which derive purely from the `Employee` record. Their `role.dart` helpers take a `FleetSettings` argument.

---

## Permission Matrix — WasteTrack

| Screen / Action | Admin | Sec Manager | Sec Guard | Others |
|---|---|---|---|---|
| WasteHomeScreen — view | ✅ | ✅ | ✅ | ❌ |
| WasteHomeScreen — Incoming section | ✅ | ✅ | ✅ | ❌ |
| WasteScheduleLoadScreen | ✅ | ✅ | ✅ | ❌ |
| WasteBeginCollectionScreen (new) | ✅ | ✅ | ✅ | ❌ |
| WasteCreateLoadScreen (legacy) | ✅ | ✅ | ✅ | ❌ |
| WasteLoadDetailScreen — view | ✅ | ✅ | ✅ (read-only) | ❌ |
| WasteLoadDetailScreen — finish loading | ✅ | ✅ | ✅ | ❌ |
| Weighbridge / Cost review / Reports / Settings | ❌ | ❌ | ❌ | ✅ managers + admins (`canAccessWastePulse`; guards blocked) |
| Cancel scheduled load | ✅ | ✅ | ❌ | ❌ |
| Edit scheduled load date/notes | ✅ | ✅ | ❌ | ❌ |

---

## Waste Load Status Flow

```
Manager creates scheduled load
          │
          ▼
    ┌──────────────┐
    │  scheduled   │  ← WasteScheduleLoadScreen
    └──────┬───────┘
           │ Guard begins + submits (WasteBeginCollectionScreen)
           │ [Firestore transaction — prevents double-collection]
           ▼
┌─────────────────────────┐
│   pending_weighbridge   │  ← Hand off to CTP Pulse Weighbridge (manager/admin)
└──────────┬──────────────┘
           │ Off-site ticket + deviation audit on Pulse
           ▼
┌─────────────────────────┐
│  pending_cost_review    │  ← Admin cost approval per waste type on Pulse
└──────────┬──────────────┘
           ▼
    ┌───────────┐
    │ completed │
    └───────────┘

Quantity-only types (e.g. IBC Bins): skip pending_weighbridge → pending_cost_review directly.

From scheduled only:
    scheduled → cancelled  (Manager/admin on mobile or Pulse)

On-the-spot create:
    draft → pending_weighbridge | pending_cost_review (finish loading on mobile)
```

---

## Navigation Flow (WasteTrack)

```
App entry (home_screen.dart)
  └─ [if isWasteUser] → Waste tab (single Loads view) → WasteHomeScreen
        ├─ Incoming section (scheduled loads)
        │    └─ "Begin Collection" → WasteBeginCollectionScreen
        ├─ Stock → WasteStockInventoryScreen
        ├─ Recent loads (draft, scheduled, pending_*, completed)
        │    └─ tap → WasteLoadDetailScreen (finish loading; Pulse handoff banner)
        ├─ FAB: Schedule / New load / Stock (all waste users)
        │    ├─ WasteScheduleLoadScreen (selected_waste_types + stock links)
        │    └─ WasteCreateLoadScreen (on-the-spot)
        └─ Weighbridge, cost review, reports, admin → CTP Pulse desk hubs (managers + admins only)
```

---

## New Screens (001-scheduled-waste-handoff)

### WasteScheduleLoadScreen
- **File**: `lib/screens/waste_schedule_load_screen.dart`
- **Access**: Security Manager + Admin
- **Purpose**: Manager pre-creates a load with contractor, waste type, expected date, optional notes
- **Output**: `waste_loads` doc with `status: scheduled`

### WasteBeginCollectionScreen
- **File**: `lib/screens/waste_begin_collection_screen.dart`
- **Access**: All waste users (guard, manager, admin)
- **Purpose**: Guard fills driver name, reg, waste items (with photos), signature when truck arrives
- **Output**: Transitions load `scheduled → pending_weighbridge`, writes items, uploads photos + signature

---

## Firestore Collections (WasteTrack)

| Collection | Purpose |
|---|---|
| `waste_loads` | One doc per load. Status drives the lifecycle. |
| `waste_items` | Items per load (`load_id` field). Min 1 per completed load. |
| `waste_photos` | Photo upload queue references (offline). |
| `waste_types` | Master list of waste types + subtypes. |
| `waste_contractors` | Contractor list. |
| `waste_rates` | Cost per kg by contractor + subtype. |
| `waste_config` | Feature flag (`enabled`). Module enable/disable controlled via Settings → Modules (admin only). |

---

## Permission Matrix — Site Security (Mobile + Pulse split)

| Screen / Action | Admin | Security Manager | Security Guard | CTP Pulse desk |
|---|---|---|---|---|
| Home — job-card Quick Actions / My Work | ❌ | ✅ | ❌ | ❌ |
| Home — guard module hub (Waste + Security cards) | ❌ | ❌ | ✅ | ❌ |
| Security tab / home | ✅ | ✅ | ✅ | ❌ guards never |
| Scan in / out, on-foot, company car | ✅ | ✅ | ✅ | ❌ (capture is mobile) |
| On-site list (mobile) | ✅ | ✅ | ✅ | ✅ managers review on Pulse Operations |
| Add company car cost | ✅ | ✅ | ❌ | ✅ managers (Costing hub) |
| Deny list, module settings | ✅ (Pulse) | ❌ | ❌ | ✅ admin Setup hub |
| Gate log / reports / exports | ❌ mobile | ❌ mobile | ❌ | ✅ managers + admins |

Mobile gates: `canUseSecurityModule` + `security_enabled`. Pulse gates: `boardModules 'security'` + `canAccessSecurityPulse` (managers + admins only). Costs validate against `security_vehicles` where `vehicle_type: company_car`.

---

## Permission Matrix — Fleet Maintenance (Mobile)

| Screen / Action | Fleet Admin | Cost Manager | Mechanic | Reporter | Others |
|---|---|---|---|---|---|
| Fleet tab — view | ✅ (if also mobile role) | ❌ Pulse only | ✅ | ✅ | ❌ |
| Reporter shell / Report wizard | ✅ | ❌ | ❌ | ✅ | ❌ |
| Mechanic shell — Mark as Fixed / Log work | ✅ | ❌ | ✅ | ❌ | ❌ |
| Work record detail — any cost UI | ❌ | ❌ | ❌ | ❌ | ❌ |
| Costing / Reports / Settings | ❌ (Pulse) | ❌ (Pulse) | ❌ | ❌ | ❌ |

Cost managers use **CTP Pulse** (`boardModules: fleet`) for optional cost linking, reports, and settings. The whole mobile module is gated behind `fleet_settings.fleet_enabled` + `isFleetMobileUser` (reporter OR mechanic).

---

## Fleet Issue Status Flow

```
Reporter submits issue (FleetReportWizardScreen — 3 steps)
          │
          ▼
    ┌──────────┐
    │   open   │  ── (out_of_service) ──► push to mechanic + cost managers, asset flagged OOS; pinned in To Fix
    └────┬─────┘
         │ Mechanic Save progress (FleetMarkFixedScreen) OR opens from In progress
         ▼
   ┌──────────────┐
   │ acknowledged │
   └──────┬───────┘
          │ Mechanic Mark as Fixed → createFleetWorkRecord CF
          ▼
    ┌───────────┐
    │ resolved  │  ── clears asset OOS flag if no other open OOS issues
    └───────────┘

Any open/acknowledged issue → cancelled  (mechanic / cost manager / admin)
```

---

## Navigation Flow (Fleet Maintenance — Mobile)

```
App entry (home_screen.dart)
  └─ [if fleet_enabled && isFleetMobileUser] → Fleet tab
        ├─ Reporter → FleetReporterHomeScreen (grid, wizard, daily check)
        └─ Mechanic → FleetMechanicHomeScreen (To Fix / In progress / Log work / History)
              └─ Mark as Fixed / Log work tab → createFleetWorkRecord CF
  Home tiles (reporters only): Report Problem → wizard step 1; Daily Safety Check → FleetDailyCheckEntryScreen
```

Desk costing: see Pulse `/fleet` (Costs, Reports, Assets) — `Canvases/08-fleet-floor-to-desk-flow.excalidraw.md`.

---

## Fleet Screens (Mobile)

| File | Access | Purpose |
|---|---|---|
| `fleet_home_screen.dart` | reporter OR mechanic | Routes to persona shell only |
| `fleet_reporter_home_screen.dart` | reporter | Always-on machine grid; My reports / All open (no FAB) |
| `fleet_daily_check_entry_screen.dart` | reporter | Home tile entry — check-only machine picker |
| `fleet_report_wizard_screen.dart` | reporter | 3-step report wizard (max 10 photos) |
| `fleet_mechanic_home_screen.dart` | mechanic | To Fix (pinned OOS) / In progress / Log work / History |
| `fleet_mark_fixed_screen.dart` | mechanic | Save progress or Mark as Fixed → CF |
| `fleet_work_capture_form.dart` | mechanic | Shared work form widget |
| `fleet_work_record_detail_screen.dart` | mechanic | Work detail — zero cost UI |
| `fleet_work_records_list_screen.dart` | mechanic | History list — no cost badges |

Removed from mobile (2026-06-25): `fleet_add_cost_screen`, `fleet_reports_screen`, `fleet_settings_screen`, `fleet_assets_screen`, `fleet_cost_widgets`.

---

## Firestore Collections (Fleet Maintenance)

| Collection | Purpose |
|---|---|
| `fleet_assets` | Forklift/grab register. `has_open_oos_issue` denormalised for picker badges. |
| `fleet_issues` | Reported problems (the mechanic's queue). |
| `fleet_work_records` | Maintenance log. `fleet_work_parts` sub-collection holds part rows. |
| `fleet_cost_lines` | Pulse-only optional costs (never shown on mobile). `has_linked_costs` on work records when linked. |
| `fleet_types` | Configurable asset types + work types. |
| `fleet_settings` | `config` doc: reporter depts, cost-manager clock nos, feature flag. |
| `fleet_counters` | Global `FM-NNNN` sequence at `fleet_counters/global`, never resets (Admin SDK only). |
| `fleet_audit` | Immutable audit trail. |

Cloud Functions (`createFleetWorkRecord`, `onFleetIssueCreated`, `onFleetIssueUpdated`) live in the **monorepo** `firebase/functions/src/index.ts`, not this repo. See `docs/COLLECTIONS.md` for full field schemas.

---

## Admin Screens (Job Cards core)

Admin-only screens reached from the Home **Admin** tile / Admin Settings. All gated on `Employee.isAdmin`.

| File | Access | Purpose |
|---|---|---|
| `admin_screen.dart` | admin | 6-tab control panel: Employees, Structures, Settings, Job Cards, On Site, Comms |
| `geofence_editor_screen.dart` | admin | Map editor for the site geofence boundary (`config/geofence`) |
| `copper_dashboard_screen.dart` | admin (clock 22) | Copper inventory dashboard (whitelist-gated) |
| `feedback_admin_screen.dart` | admin | **User Feedback triage board** — reviews `feedback` submissions; sets status `New → Planned → Implemented → Declined` + private notes. Reached from Settings → Feedback. |
| `scan_tester_screen.dart` | admin | **Scan Tester** — PDF417 capture to `pulse_scan_samples`. Driver licence RSA decrypt. Review in Pulse Settings. |
| `security_home_screen.dart` | `isSecurityUser` | Site Security hub — gate selector + action cards. Add company car cost tile: `isSecurityCostManager` only. |
| `security_vehicle_scan_in_screen.dart` | `isSecurityUser` | Vehicle scan in — disc + driver licence + occupants. |
| `security_vehicle_scan_out_screen.dart` | `isSecurityUser` | Vehicle scan out — disc on departing vehicle. |
| `security_company_car_screen.dart` | `isSecurityUser` | Company car exit/return — reg must match `vehicle_type: company_car` in register. |
| `security_on_foot_visitor_screen.dart` | `isSecurityUser` | On-foot visitor entry. |
| `security_on_site_screen.dart` | `isSecurityUser` | Live on-site vehicle list (operational; managers also use Pulse). |
| `security_add_cost_screen.dart` | `isSecurityCostManager` | Company car picker + cost line — not visitor/contractor regs. |

**User Feedback board (`feedback` collection)**: employees submit via the Home-screen "Give Feedback" FAB (`feedback`/`userName`/`clockNo`/`timestamp`). The admin board writes triage fields onto each doc — `status`, `statusUpdatedAt`, `statusUpdatedByClockNo`, `adminNotes`, `adminNotesUpdatedAt`, `adminNotesByClockNo` — and never touches the submitter's fields. Status filtering is client-side, so no composite index is needed. The rule stays `match /feedback/{docId} { allow read, write: if isSignedIn(); }` — admin-only access is enforced in the UI, not in rules.

---

## State Management

- Riverpod (`flutter_riverpod ^2.5.3`) for providers
- Screens use `ConsumerStatefulWidget`
- WasteTrack screens call `WasteService` directly (no dedicated provider for loads — uses local state + streams)
- Offline sync via `SyncService` (Hive queue)

## How to regenerate

After significant changes to screens, roles, or navigation, update this file manually or run `/update-architecture` in OpenCode.

---

## Core Services Notes (Copper / Geofence / Notifications / Number Assignment) — Map Polish Addition (2026-06-16)

- **Copper**: Transactions + inventory (copper_* collections). Whitelist-gated in mobile (role.dart). Password protected ops. See collections.dart + rules (signed-in) + copper_service.dart.
- **Geofence + Presence**: geo_fence_logs + employees.isOnSite/fcmTokenUpdatedAt. Background in Job Cards (not web). Drives notification targeting. **Device health (2026-06-28)**: `DeviceHealthService` monitors six Android permissions; `employees.permissions` merged via `updateEmployeePresence`; home `GeofenceHealthBanner` surfaces gaps on resume.
- **Notifications / Inbox**: notifications + notification_configs + notification_inbox/{clockNo}/items/* . CF for escalation + writes. Client clears own. Subcol pattern (see COLLECTIONS.md + rules).
- **Number Assignment (counters)**: jobCards / overtime / waste / fleet / ink counters. Client read, CF/AdminSDK write only (Wave B). Global sequential never-reset for waste/fleet/ink.
- **Pulse Job Cards view**: External read-only KPIs (see cross-links above). Not full CRUD. "Job Cards & Machine Health" branding in Pulse.

**Recommended Excalidraw/embedded additions** (for Phase 8 canvases 01-04+ — **INTEGRATED**):
See dedicated specs in monorepo `Canvases/` (created/updated per Phase 8 polish review output; use these for import into Excalidraw or canvas tools; include mermaid + layout notes + CTP palette + links back to this viz + rules/COLLECTIONS):
1. Auth + Gating flow: `../../../Canvases/01-auth-gating-flow.excalidraw.md` (mobile client derivation/hardcoded + Pulse claims + admins/{uid} registry + CF setCustomClaims). Cross-ref: this §Role System + role.dart + firebase/functions (setCustomClaims) + rules ADMIN REGISTRY + Components/admins-collection.md .
2. Geofence->Presence->Notification Inbox flow: `../../../Canvases/02-geofence-presence-inbox.excalidraw.md` (employees + logs + inbox subcol + CF). Cross-ref: this §Core Services Notes + Components/notification-inbox-specifics.md + COLLECTIONS.md (notification_inbox entry) + rules + CFs (job-cards-core, fleet-notifs, notification-parking).
3. Number Assignment across modules: `../../../Canvases/03-number-assignment.excalidraw.md` (counters + CFs for job/waste/fleet/ink/overtime + pulse). Cross-ref: rules Wave B (counters/* write:false), COLLECTIONS (counters entries), publish.md CF inventory.
4. Ink replay / WAC authoritative: `../../../Canvases/04-ink-replay.excalidraw.md` (transactions -> server onInkTransactionWritten replay -> stock_items cache; append-only). Cross-ref: `../../../docs/Ink_Factory_Migration_Plan.md`, mobile ink_ledger.dart + firebase CF, rules INK FACTORY TIER.
5. Module enablement + boardModules: `../../../Canvases/05-module-gating.excalidraw.md` (Job Cards mobile tiles vs Pulse sections + claim mirror in pulse_user_settings). Cross-ref: this §Module Gating + Pulse JobCardsModule + setBoardModules CF + pulse_user_settings in COLLECTIONS.

**Integration note (Phase 8)**: These 5 are now first-class Canvases artifacts (alongside 05-Cloud Functions.canvas, 06-data-flows.canvas.md/json, 07 - Dependencies.canvas). Update the Excalidraw .md specs + this list + 06-data-flows.canvas.md on any related change (per update discipline in Instructions + POLISH-CHECKLIST.md). Export subsets for board slides.

Update these tables/mermaid + this section on changes. See monorepo docs/ARCHITECTURE.md + README.md + COLLECTIONS.md for full cross-app map + deploy. Reference prior subagent findings: gating details (viz §1 + role.dart), CF split (rules/test Wave B), collection gaps (shared-ts vs here + dart + rules). See also Components/monorepo-structure.md + deploy-discipline.md .
