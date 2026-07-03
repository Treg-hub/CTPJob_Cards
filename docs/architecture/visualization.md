# CTP Job Cards — Architecture & Role-Based Access

**This is a primary "canvas" for the CTP Architecture Map (scannable tables + flows for board presentations).**

_Last updated: 2026-07-03 (Feedback loop closed — home FAB now opens **My Feedback** (`my_feedback_screen.dart`, all roles incl. Guard-Shell): submit + follow own items with worker-friendly statuses (Received/Planned/Done/Declined) and a public two-way thread (`feedback_thread_screen.dart`, `feedback/{id}/feedback_comments` subcol — submitter + admins only, rules-enforced via clockNum claim); admin board gains "Reply to submitter"; CFs `onFeedbackStatusChanged`/`onFeedbackCommentCreated` (this repo's jobcards codebase) notify the other side, push or inbox-park with `feedbackId` deep link; feedback update/delete now admin-claim-only in rules). 2026-07-02 (Waste offline resilience — persistent `waste_media_queue/` media, single-owner Hive queue, media_lost audit surfacing, timestamp restoration + photo_count recompute on replay, IBC pool ops online-only guard, 14-day home window). 2026-07-02 (Client off-site presence gating — Ink/Waste/Security hidden off-site; Fleet reporters on-site only, mechanics full access; My Work retained; Create blocked unless isAdmin; see `lib/utils/presence_gating.dart`). 2026-06-28 (iPhone web inbox_only delivery — clientPlatform/clientDevice on employees; CF prefersInboxDelivery parks all job alerts; Android push unchanged)._

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
- **Stores (proposed)**: See `../../../docs/Stores_Module_Design.md` (official future-planning design spec — not for current implementation). Digitize manual employee **requisitions** for consumables in the central mobile hub. Volume ~20 req/day (2-5 items). QR/scan proof of collection at crib (replaces paper signature/duplicate). Special items via clerk notification + QR pickup. Direct issues rare (urgent breakdown). High-value (copper nuggets) needs manager release flag. Small items: transaction-level QR (no per-bolt scanning). Returns for wrong size supported. Pastel CSV import via simple daily export. Weekly per-shift/dept reports with costing planned. Gating via `stores_settings` clock lists. Rugged tablet recommended for dirty/greasy crib. Embedded in central Job Cards + Pulse. (Planning spec only.)
- Geofence / Notifications / Presence (core services): always-on for signed-in (geofence auto in background, presence updates employees.isOnSite/fcm, feeds notification_inbox + escalation). See rules + geofence_editor in Admin.

**Off-Site Client Gating (2026-07-02)** — `lib/utils/presence_gating.dart` + route guards on module roots. **Server write enforcement still deferred** (see memory-bank/decisions.md). Only `Employee.isAdmin` bypasses off-site restrictions (managers are not exempt).

| Surface | On-site | Off-site (floor) | Off-site (`isAdmin`) |
|---|---|---|---|
| Ink / Waste / Security (tabs + home tiles) | Visible | Hidden | Full access |
| Fleet tab | Reporter + mechanic | Mechanic only; reporter hidden | Full fleet |
| My Work + job detail updates | Yes | Yes | Yes |
| Create Job Card | Yes | Blocked (disabled tile + route guard) | Allowed |
| View Jobs / History / Manager Dashboard | Unchanged | Unchanged | Unchanged |

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
| On-site stock pick (Schedule / Begin Collection / Create-from-scratch) | ✅ | ✅ | ✅ | ❌ |
| Begin Collection: "Show all contractor types" override (bypasses scheduled type restriction) | ✅ | ❌ | ❌ | ❌ |

**Converged 2026-06-30**: `paper_document_ref` is required to submit on both Begin Collection and Create-from-scratch (was optional on the latter). On-site stock pick is "any waste user" everywhere (was admin/Security-Manager-only on Create-from-scratch). Loaded-truck-photo + driver-signature requirements are settings-driven (`waste_settings.photos_required`/`signature_required`) on both the scheduled and on-the-spot paths — Finish Loading no longer hardcodes signature=mandatory/photos=optional. Begin Collection's item/stock pickers are restricted to the manager's `selected_waste_types` from scheduling (admin override available, recorded to `waste_audit`).

---

## Waste Load Status Flow

```
Manager creates scheduled load (W-NNNN assigned immediately via createWasteLoad CF,
client_ref-protected — no longer deferred to the guard's submitCollection)
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
- **Purpose**: Manager pre-creates a load with contractor, waste type(s), expected date, optional notes, optional paper-doc pre-fill, optional on-site stock pre-link
- **Output**: `waste_loads` doc with `status: scheduled`. As of 2026-06-30, `createScheduledLoad()` calls the `createWasteLoad` CF immediately (online) — getting a real `W-NNNN` up front instead of an empty `load_number` — with a `client_ref`-protected retry-once-on-timeout helper and an `OFFLINE-*` placeholder fallback that reconciles via the same sync-queue path Create-from-scratch already used.

### WasteBeginCollectionScreen
- **File**: `lib/screens/waste_begin_collection_screen.dart`
- **Access**: All waste users (guard, manager, admin)
- **Purpose**: Guard fills driver name, vehicle reg, optional trailer reg, **required** paper document reference, waste items (photos required only if `waste_settings.photos_required`), signature (required only if `waste_settings.signature_required`) when truck arrives. Item/stock pickers are restricted to the manager's `selected_waste_types` from scheduling (full contractor list if unset); an admin-only "Show all contractor types" toggle overrides this, recording the override to `waste_audit` (`action: type_restriction_override`).
- **Output**: Transitions load `scheduled → pending_weighbridge`, writes items, uploads photos + signature

---

## Firestore Collections (WasteTrack)

| Collection | Purpose |
|---|---|
| `waste_loads` | One doc per load. Status drives the lifecycle. Includes optional `trailer_reg` (alongside `driver_name`/`vehicle_reg`, captured at Create-from-scratch or Begin Collection), `selected_waste_types` (manager's schedule-time restriction, enforced at Begin Collection), and a transient `client_ref` written by `createWasteLoad` for retry-dedup. |
| `waste_items` | Items per load (`load_id` field). Min 1 per completed load. |
| `waste_photos` | Photo upload queue references (offline). As of 2026-07-02: queued files are copied to the persistent `waste_media_queue/` app-docs dir (single-owner central Hive queue — session queues removed); Storage names derive from the queue item id (retry-idempotent); permanently lost files write a `waste_audit` `media_lost` entry surfaced in WasteQueuedScreen; replay restores ISO-string dates on `waste_loads`/`waste_items` to Timestamps and recomputes `photo_count`. Home lists (active/scheduled/recent) window to the last 14 days + future-scheduled (`WasteService.homeListWindow`). |
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
| `feedback_admin_screen.dart` | admin | **User Feedback triage board** — reviews `feedback` submissions; sets status `New → Planned → Implemented → Declined` + PRIVATE notes; "Reply to submitter / Thread (N)" opens the public two-way thread (`feedback_thread_screen.dart`). Reached from Settings → Feedback. |
| `scan_tester_screen.dart` | admin | **Scan Tester** — PDF417 capture to `pulse_scan_samples`. Driver licence RSA decrypt. Review in Pulse Settings. |
| `security_home_screen.dart` | `isSecurityUser` | Site Security hub — gate selector + action cards. Add company car cost tile: `isSecurityCostManager` only. |
| `security_vehicle_scan_in_screen.dart` | `isSecurityUser` | Vehicle scan in — disc + driver licence + occupants. |
| `security_vehicle_scan_out_screen.dart` | `isSecurityUser` | Vehicle scan out — disc on departing vehicle. |
| `security_company_car_screen.dart` | `isSecurityUser` | Company car exit/return — reg must match `vehicle_type: company_car` in register. |
| `security_on_foot_visitor_screen.dart` | `isSecurityUser` | On-foot visitor entry. |
| `security_on_site_screen.dart` | `isSecurityUser` | Live on-site vehicle list (operational; managers also use Pulse). |
| `security_add_cost_screen.dart` | `isSecurityCostManager` | Company car picker + cost line — not visitor/contractor regs. |

**User Feedback loop (`feedback` collection + `feedback_comments` subcol, closed 2026-07-03)**: the Home-screen FAB opens **My Feedback** (`my_feedback_screen.dart`, all roles) — submit (`feedback`/`userName`/`clockNo`/`timestamp`, persona-attributed to the real employee) and follow own items with worker wording (Received/Planned/Done/Declined) + reply counts. Tapping an item (or a parked `feedback_status`/`feedback_comment` inbox notification, deep-linked by `feedbackId`) opens the shared **thread** (`feedback_thread_screen.dart`): original message + status + public comments; only the original submitter and admins can post — enforced in **rules** (parent `clockNo == clockNum` claim, self-attributed `byClockNo`, non-admins can't set `byIsAdmin`), not just UI. The admin board writes triage fields — `status`, `statusUpdatedAt`, `statusUpdatedByClockNo`, `adminNotes*` (PRIVATE, never in the thread) — now gated `update, delete: if isAdmin()` in rules; `lastCommentAt`/`commentCount` are CF-maintained. CFs `onFeedbackStatusChanged` + `onFeedbackCommentCreated` (this repo's `functions/index.js`) notify the submitter on status/replies and all admins on submitter replies (push on-site, inbox park off-site). Status filtering and My-Feedback sorting are client-side, so no composite index is needed. Shared model: `lib/models/feedback_item.dart`.

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
- **Geofence + Presence**: geo_fence_logs + employees.isOnSite/fcmTokenUpdatedAt. Background in Job Cards (not web). Drives notification targeting. **Device health (2026-06-28)**: `DeviceHealthService` monitors six Android permissions; `employees.permissions` merged via `updateEmployeePresence`; home `GeofenceHealthBanner` surfaces gaps on resume. **Routing**: `permissionsCompleted` gates onboarding once — revoked location/perms send user to **Home** + banner, not full onboarding. **Fix flow**: `fixMissing()` / `openSettingsFor()` request dialogs then open battery/DND/overlay/app Settings as needed (onboarding rows, banner Fix, Settings tiles). **iPhone web (2026-06-28)**: Safari/iPad web reports `clientDevice` + `notificationDelivery: inbox_only` via `ClientPlatformService`; CF `prefersInboxDelivery()` parks job/escalation/broadcast alerts to `notification_inbox` (Settings → Notification Inbox on web). Android APK reports `push` — unchanged FCM behaviour.
- **Notifications / Inbox**: notifications + notification_configs + notification_inbox/{clockNo}/items/* . CF for escalation + writes. Client clears own. Subcol pattern (see COLLECTIONS.md + rules).
- **Number Assignment (counters)**: jobCards / overtime / waste / fleet / ink counters. Client read, CF/AdminSDK write only (Wave B). Global sequential never-reset for waste/fleet/ink.
- **Pulse Job Cards view**: External read-only KPIs (see cross-links above). Not full CRUD. "Job Cards & Machine Health" branding in Pulse.
- **Startup / Update surfaces (2026-07-03)**: Three layers, all Job Cards mobile only. (1) **Version kill-switch** — `main.dart` reads `settings/app.minSupportedBuild` before `runApp`; older builds get the blocking `UpdateRequiredScreen` (fails open on fetch error). (2) **Update prompt** — `UpdateService` (Firebase Remote Config: `latest_version`/`latest_build`/`download_url`/`force_update`/`release_notes`) checks on HomeScreen mount with a 4 h cooldown; `force_update: true` makes the dialog non-dismissible. (3) **What's-changed sheet (NEW)** — `WhatsNewService` + `whats_new_sheet.dart`: on the first HomeScreen mount of a *new build* (SharedPreferences `lastSeenWhatsNewBuild` < current build) a one-time bottom sheet shows the newest entry of the bundled `docs/CHANGELOG.md` (same asset as Settings → Documentation → Changelog) with a "Full changelog" link into `DocViewerScreen`. Fresh installs are stamped during permissions onboarding so first-time users never see it; the sheet defers itself when a notification deep link has pushed a screen over Home. **Release discipline**: prepend a user-facing entry to `docs/CHANGELOG.md` before every APK build — the top entry is exactly what users see after updating.
- **Startup resilience (2026-07-03)**: hardening of the cold-start / auto-login path (root-cause fix for "logged in but nothing appears"). (1) **Resilient streams** — `services/resilient_stream.dart` `resilientSnapshots()` wraps the Home Firestore listeners (active jobs, my work, employee, inbox-unread badge) so a `permission-denied` (Firestore kills such listeners permanently) no longer blanks Home until restart: it refreshes claims (deduped, via `AuthClaimsService.onRefreshCompleted`) then retries with backoff per the pure `utils/stream_retry_policy.dart`, and re-arms parked streams on connectivity/claims/resume/auth via `RetryTriggers`. Errors are never forwarded downstream (consumers keep last data / stay in `waiting`). (2) **Cached-vs-empty** — `JobCardListSnapshot` carries `metadata.isFromCache`; pure `utils/list_load_state.dart` `decideListLoadState()` shows skeletons + "Waiting for connection…" instead of a false empty state on a cold cache. (3) **Session-expired banner** — `widgets/session_health_banner.dart` (top of the Home body Column) surfaces a dead/revoked Firebase Auth session (prefs say logged-in, `authStateChanges` null, or `getIdToken(true)` → `user-disabled`/`-not-found`/`-token-expired`) and a server-confirmed employee-doc deletion; "Sign in" keeps prefs + Hive `sync_queue` (offline work replays post-auth). (4) **Capped startup** — `main.dart` kill-switch/uid-restore/employee fetch are timeout-bounded (4s/2s+5s/6s, fail open); duplicate `initializeSettings()` read removed; `getEmployeeChecked` distinguishes a server-confirmed missing doc from an offline cache miss (only the former clears the session); startup breadcrumbs (`startup_employee_source`, `claims_refresh_last`). (5) **Registration parity** — `registration_screen.dart` mints claims + saves FCM token after linking (was login-only) and self-heals `email-already-in-use` by signing in and resuming the link. (6) **Module-settings retry** — Fleet/Waste/Security settings re-load on reconnect + resume when the first attempt failed. All post-first-frame — zero added startup time. Streams hoisted to Home state fields (one active-jobs listener shared by counts + recent list; no re-subscription per rebuild). See `stream_retry_policy_test.dart` + `list_load_state_test.dart`.
- **Navigation & wide-screen layout (2026-07-03)**: `main.dart` sets one `PageTransitionsTheme` (Cupertino slide) for all routes on both themes — lighter to paint than the Android zoom default (removes back-nav stutter) and adds edge-swipe-back. Home Quick Actions grid constrained to a 1200px centred column with a 1.25 tile aspect ratio on desktop (`_maxContentWidth`/`_gridChildAspectRatio` in `home_screen.dart`) so wide screens no longer balloon tiles and hide Recent Job Cards; phones/tablets unchanged.

**Recommended Excalidraw/embedded additions** (for Phase 8 canvases 01-04+ — **INTEGRATED**):
See dedicated specs in monorepo `Canvases/` (created/updated per Phase 8 polish review output; use these for import into Excalidraw or canvas tools; include mermaid + layout notes + CTP palette + links back to this viz + rules/COLLECTIONS):
1. Auth + Gating flow: `../../../Canvases/01-auth-gating-flow.excalidraw.md` (mobile client derivation/hardcoded + Pulse claims + admins/{uid} registry + CF setCustomClaims). Cross-ref: this §Role System + role.dart + firebase/functions (setCustomClaims) + rules ADMIN REGISTRY + Components/admins-collection.md .
2. Geofence->Presence->Notification Inbox flow: `../../../Canvases/02-geofence-presence-inbox.excalidraw.md` (employees + logs + inbox subcol + CF). Cross-ref: this §Core Services Notes + Components/notification-inbox-specifics.md + COLLECTIONS.md (notification_inbox entry) + rules + CFs (job-cards-core, fleet-notifs, notification-parking).
3. Number Assignment across modules: `../../../Canvases/03-number-assignment.excalidraw.md` (counters + CFs for job/waste/fleet/ink/overtime + pulse). Cross-ref: rules Wave B (counters/* write:false), COLLECTIONS (counters entries), publish.md CF inventory.
4. Ink replay / WAC authoritative: `../../../Canvases/04-ink-replay.excalidraw.md` (transactions -> server onInkTransactionWritten replay -> stock_items cache; append-only). Cross-ref: `../../../docs/Ink_Factory_Migration_Plan.md`, mobile ink_ledger.dart + firebase CF, rules INK FACTORY TIER.
5. Module enablement + boardModules: `../../../Canvases/05-module-gating.excalidraw.md` (Job Cards mobile tiles vs Pulse sections + claim mirror in pulse_user_settings). Cross-ref: this §Module Gating + Pulse JobCardsModule + setBoardModules CF + pulse_user_settings in COLLECTIONS.

**Integration note (Phase 8)**: These 5 are now first-class Canvases artifacts (alongside 05-Cloud Functions.canvas, 06-data-flows.canvas.md/json, 07 - Dependencies.canvas). Update the Excalidraw .md specs + this list + 06-data-flows.canvas.md on any related change (per update discipline in Instructions + POLISH-CHECKLIST.md). Export subsets for board slides.

Update these tables/mermaid + this section on changes. See monorepo docs/ARCHITECTURE.md + README.md + COLLECTIONS.md for full cross-app map + deploy. Reference prior subagent findings: gating details (viz §1 + role.dart), CF split (rules/test Wave B), collection gaps (shared-ts vs here + dart + rules). See also Components/monorepo-structure.md + deploy-discipline.md .
