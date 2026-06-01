# CTP Job Cards — Architecture & Role-Based Access

_Last updated: 2026-06-01 (reflects 001-scheduled-waste-handoff feature)_

---

## Role System

Roles are **derived** from `Employee.position` and `Employee.department` (see `lib/utils/role.dart`). There is no explicit role field in Firestore.

| Role | Derived from | Key capabilities |
|---|---|---|
| **Admin** | `clockNo == "22"` | Full access to all screens + admin controls |
| **Security Manager** | dept=`security`, pos=`manager` | Schedule loads, view all loads, reports, pending weighbridge, cancel scheduled |
| **Security Guard** | dept=`security`, pos=`guard` | View incoming (scheduled) loads, begin collection, view recent loads |
| **Technician** | pos contains `mechanical`/`electrical`/`technician` | Job cards only |
| **Manager** (job cards) | pos contains `manager` | Job card manager dashboard |
| **Operator** | neither manager nor technician | Limited job card actions |

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
| `waste_config` | Feature flag (`enabled`) + pilot clock list. |

---

## State Management

- Riverpod (`flutter_riverpod ^2.5.3`) for providers
- Screens use `ConsumerStatefulWidget`
- WasteTrack screens call `WasteService` directly (no dedicated provider for loads — uses local state + streams)
- Offline sync via `SyncService` (Hive queue)

## How to regenerate

After significant changes to screens, roles, or navigation, update this file manually or run `/update-architecture` in OpenCode.
