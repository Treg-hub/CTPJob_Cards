# CTP Job Cards — Architecture & Role-Based Access

_Last updated: 2026-06-05 (Firestore-based admin, Building/Spec job types)_

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

## State Management

- Riverpod (`flutter_riverpod ^2.5.3`) for providers
- Screens use `ConsumerStatefulWidget`
- WasteTrack screens call `WasteService` directly (no dedicated provider for loads — uses local state + streams)
- Offline sync via `SyncService` (Hive queue)

## How to regenerate

After significant changes to screens, roles, or navigation, update this file manually or run `/update-architecture` in OpenCode.
