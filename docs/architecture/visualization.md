# CTP Job Cards — Architecture & Role-Based Access

**This is a primary "canvas" for the CTP Architecture Map (scannable tables + flows for board presentations).**

_Last updated: 2026-06-18 (added the admin-only **User Feedback** triage board — `feedback_admin_screen.dart`, reached from Admin → Settings → Feedback; see "Admin Screens (Job Cards core)" below). Prior: 2026-06-16 Phase 8 polish — cross-links to small focused notes (admins-collection, notification-inbox-specifics, deploy-discipline), POLISH-CHECKLIST.md, new Canvases Excalidraw specs (auth/gating, geofence-inbox, numbering, ink-replay, module-gating), Instructions/ARCHITECTURE/COLLECTIONS/REAME sync, dupe note reinforced, update discipline ref._

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
- **Visual canvases / Excalidraw integration (Phase 8)**: `../../../Canvases/06-data-flows.canvas.md` (full flows incl. notifs/presence/ink), `../../../Canvases/07-dependencies.canvas.json`, new `../../../Canvases/01-auth-gating-flow.excalidraw.md` etc (see Recommended Excalidraw below for the 5). Use for board exports.
- Sync note: dev-docs/architecture/visualization.md is older dupe — keep in sync or delete after merge. **Primary = this file only for edits.** See also monorepo `Components/monorepo-structure.md`.

**Presentation notes**: Tables for quick scan. Update mermaid + matrices on role/module changes. For Excalidraw: extract sections below into visual canvases (see task proposals).

---

## Role System

Roles are **derived** from `Employee.position` and `Employee.department` (see `lib/utils/role.dart`). The **Admin** role is the only exception — it is controlled by the `isAdmin` boolean field on each employee's Firestore document rather than their position string.

| Role | Derived from | Key capabilities |
|---|---|---|
| **Admin** | `Employee.isAdmin == true` (Firestore field) | Full access to all screens + admin controls, module toggles |
| **Security Manager** | dept=`security`, pos=`manager` | Schedule loads, view all loads, reports, pending weighbridge, cancel scheduled |
| **Security Guard** | dept=`security`, pos=`guard` | View incoming (scheduled) loads, begin collection, view recent loads |
| **Technician** | pos contains `mechanical`/`electrical`/`technician` | Job cards only |
| **Manager** (job cards) | pos contains `manager` | Job card manager dashboard |
| **Operator** | neither manager nor technician | Limited job card actions |
| **Building Maintenance** | pos contains `building maintenance` | Receives Building Maintenance type job cards |
| **Pre Press Specialist** | dept=`Pre Press`, pos contains `specialist` | Receives Pre Press Spec type job cards |
| **Fleet Mechanic** | dept=`Workshop`, pos=`Hyster Mechanic` | Log work, acknowledge/resolve issues (no cost amounts) |
| **Fleet Reporter** | dept ∈ `fleet_settings.reporter_departments` | Report fleet issues, view own issues |
| **Fleet Cost Manager** | `clockNo` ∈ `fleet_settings.cost_manager_clock_nos` | Enter costs, cost reports, CSV export |
| **Fleet Admin** | `Employee.isAdmin == true` | Manage asset register + Fleet settings + all of the above |

> **To grant Admin:** Set `isAdmin: true` on the employee's Firestore document. No code change or app release required.

**Module Gating (2026-06 updates)**:
- Job Cards core: always (mobile branding primary).
- Waste / Fleet: gated by settings flags + role derivation (see permission matrices below + role.dart).
- Copper: hardcoded whitelist (clock 22/5421/20) in role.dart + HomeScreen tab visibility. Part of "copper service".
- Ink Factory: `department == "Ink Factory"` (mobile-only per migration plan; no web). Gated module tile like Fleet.
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
| WasteScheduleLoadScreen (new) | ✅ | ✅ | ❌ | ❌ |
| WasteBeginCollectionScreen (new) | ✅ | ✅ | ✅ | ❌ |
| WasteCreateLoadScreen (legacy) | ✅ | ✅ | ✅ | ❌ |
| WasteLoadDetailScreen — view | ✅ | ✅ | ✅ (read-only) | ❌ |
| WasteLoadDetailScreen — weighbridge | ✅ | ✅ | ❌ | ❌ |
| WastePendingWeighbridgeScreen | ✅ | ✅ | ❌ | ❌ |
| WasteReportsScreen | ✅ | ✅ | ❌ | ❌ |
| WasteAdminScreen | ✅ | ❌ | ❌ | ❌ |
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
│   pending_weighbridge   │  ← Guard submitted; manager sees this in Pending Weighbridge screen
└──────────┬──────────────┘
           │ Manager enters weighbridge weight (WasteLoadDetailScreen)
           ▼
    ┌───────────┐
    │ completed │
    └───────────┘

From scheduled only:
    scheduled → cancelled  (Manager cancels before guard begins)

Legacy path (preserved):
    [guard creates from scratch] → draft → completed
```

---

## Navigation Flow (WasteTrack)

```
App entry (home_screen.dart)
  └─ [if isWasteUser] → Waste tab → WasteHomeScreen
        ├─ Incoming section (scheduled loads)
        │    └─ "Begin Collection" → WasteBeginCollectionScreen
        │         └─ WasteSignatureScreen (signature capture)
        ├─ Recent loads list (draft, completed, pending_weighbridge)
        │    └─ tap → WasteLoadDetailScreen
        │         ├─ [manager/admin] Weighbridge entry
        │         └─ [manager/admin] Mark complete
        ├─ FAB [guard]:    "New Load" → WasteCreateLoadScreen
        ├─ FAB [manager]:  bottom sheet →
        │    ├─ "Schedule Incoming" → WasteScheduleLoadScreen
        │    └─ "New Load (on the spot)" → WasteCreateLoadScreen
        ├─ AppBar [manager/admin] → WastePendingWeighbridgeScreen
        ├─ AppBar [manager/admin] → WasteReportsScreen
        └─ AppBar [admin]         → WasteAdminScreen
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

## Permission Matrix — Fleet Maintenance

| Screen / Action | Fleet Admin | Cost Manager | Mechanic | Reporter | Others |
|---|---|---|---|---|---|
| FleetHomeScreen — view | ✅ | ✅ | ✅ | ✅ | ❌ |
| FleetReportIssueScreen | ✅ | ✅ | ✅ | ✅ | ❌ |
| FleetIssuesListScreen | ✅ | ✅ | ✅ | ❌ | ❌ |
| FleetIssueDetail — acknowledge / resolve | ✅ | ❌ | ✅ | ❌ | ❌ |
| FleetIssueDetail — cancel | ✅ | ✅ | ✅ | ❌ | ❌ |
| FleetLogWorkScreen | ✅ | ❌ | ✅ | ❌ | ❌ |
| FleetWorkRecordDetail — cost amounts | ✅ | ✅ | ❌ (label only) | ❌ | ❌ |
| FleetAddCostScreen | ✅ | ✅ | ❌ | ❌ | ❌ |
| FleetReportsScreen + CSV export | ✅ | ✅ | ❌ | ❌ | ❌ |
| FleetAssetsScreen (manage register) | ✅ | ❌ | ❌ | ❌ | ❌ |
| FleetSettingsScreen | ✅ | ❌ | ❌ | ❌ | ❌ |

The whole module is also gated behind the `fleet_settings.fleet_enabled` flag — when off, the Fleet tab is hidden for everyone.

---

## Fleet Issue Status Flow

```
Reporter submits issue (FleetReportIssueScreen)
          │
          ▼
    ┌──────────┐
    │   open   │  ── (out_of_service) ──► push to mechanic + cost managers, asset flagged OOS
    └────┬─────┘
         │ Mechanic acknowledges (FleetIssueDetail)
         ▼
   ┌──────────────┐
   │ acknowledged │
   └──────┬───────┘
          │ Mechanic resolves — two paths:
          │   • "Log Work & Resolve" → FleetLogWorkScreen (creates work record, links issue)
          │   • "Resolve with Note"  → quick close with a note
          ▼
    ┌───────────┐
    │ resolved  │  ── clears asset OOS flag if no other open OOS issues
    └───────────┘

Any open/acknowledged issue → cancelled  (mechanic / cost manager / admin)
```

---

## Navigation Flow (Fleet Maintenance)

```
App entry (home_screen.dart)
  └─ [if fleet_enabled && isFleetUser] → Fleet tab → FleetHomeScreen
        ├─ OOS alert banner (assets with has_open_oos_issue)
        ├─ Open Issues [mechanic/cost mgr]   → FleetIssueDetail
        ├─ Recent Work [mechanic]            → FleetWorkRecordDetail
        ├─ My Reported Issues [reporter]     → FleetIssueDetail (read-only)
        ├─ Costs Pending [cost mgr]          → FleetWorkRecordDetail
        └─ Quick Actions (role-based):
             ├─ Report Issue   → FleetReportIssueScreen
             ├─ Log Work       → FleetLogWorkScreen           [mechanic/admin]
             ├─ Open Issues    → FleetIssuesListScreen        [mechanic/admin]
             ├─ Add Cost       → FleetAddCostScreen           [cost mgr/admin]
             ├─ Reports        → FleetReportsScreen           [cost mgr/admin]
             ├─ Manage Assets  → FleetAssetsScreen            [admin]
             └─ Fleet Settings → FleetSettingsScreen          [admin]
```

---

## Fleet Screens

| File | Access | Purpose |
|---|---|---|
| `fleet_home_screen.dart` | all fleet roles | Role-based dashboard + quick actions |
| `fleet_report_issue_screen.dart` | reporter+ | Asset picker, severity, shift, description, photos |
| `fleet_issues_list_screen.dart` | mechanic, cost mgr, admin | Status-filtered issue queue (severity-sorted) |
| `fleet_issue_detail_screen.dart` | role-aware | Acknowledge / resolve / cancel actions |
| `fleet_log_work_screen.dart` | mechanic, admin | Work type, hours, parts rows, photos; calls `createFleetWorkRecord` |
| `fleet_work_record_detail_screen.dart` | role-aware | Mechanic sees no costs; cost mgr/admin see + add cost lines |
| `fleet_work_records_list_screen.dart` | mechanic, cost mgr, admin | Work record list with "Costed" badge |
| `fleet_add_cost_screen.dart` | cost mgr, admin | Cost line entry (category, amount, invoice, supplier) |
| `fleet_reports_screen.dart` | cost mgr, admin | Month/YTD KPIs, spend-per-asset, CSV export |
| `fleet_assets_screen.dart` | admin | Manage forklift/grab register |
| `fleet_settings_screen.dart` | admin | Reporter depts, cost-manager clock nos, asset/work types, feature flag |

---

## Firestore Collections (Fleet Maintenance)

| Collection | Purpose |
|---|---|
| `fleet_assets` | Forklift/grab register. `has_open_oos_issue` denormalised for picker badges. |
| `fleet_issues` | Reported problems (the mechanic's queue). |
| `fleet_work_records` | Maintenance log. `fleet_work_parts` sub-collection holds part rows. |
| `fleet_cost_lines` | Manager-entered costs (never shown to mechanic). |
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
- **Geofence + Presence**: geo_fence_logs + employees.isOnSite/fcmTokenUpdatedAt. Background in Job Cards (not web). Drives notification targeting.
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

**Integration note (Phase 8)**: These 5 are now first-class Canvases artifacts (alongside 05-Cloud Functions.canvas, 06-data-flows.canvas.md/json, 07-dependencies.canvas.json). Update the Excalidraw .md specs + this list + 06-data-flows.canvas.md on any related change (per update discipline in Instructions + POLISH-CHECKLIST.md). Export subsets for board slides.

Update these tables/mermaid + this section on changes. See monorepo docs/ARCHITECTURE.md + README.md + COLLECTIONS.md for full cross-app map + deploy. Reference prior subagent findings: gating details (viz §1 + role.dart), CF split (rules/test Wave B), collection gaps (shared-ts vs here + dart + rules). See also Components/monorepo-structure.md + deploy-discipline.md .
