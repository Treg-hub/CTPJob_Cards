# Failure subtype on complete form — implementation plan

**Status:** Implemented on mobile Complete / Monitor (detail + My Work).  
**Related:** Breakdown family SSoT = job card `type` (Mechanical / Electrical / …).  
**Field:** `failureSubtype` (string, optional free-text).

---

## Product rules

| Rule | Detail |
|------|--------|
| When | On **Complete** and **Monitor** (after the fix is known). Not required on create. |
| Required? | **Optional** — blank is OK (same philosophy as comments/notes). |
| UI | Free-text field + **suggestions**: curated seeds for **current `type`** + past values used on cards of that type (part-list pattern). |
| Scope by type | Seeds differ for Mechanical vs Electrical vs Maintenance vs Building so the list stays short and relevant. |
| SSoT | **`type` remains the breakdown family.** Subtype only refines (e.g. type=Mechanical, subtype="Pneumatic / air"). |

---

## Seed lists (from Pressroom job cards, 2026-07)

Source: live export patterns (part / description / corrective keywords) grouped by `type`.

### Mechanical
Pneumatic / air · Mechanical wear / drive · Hydraulic / oil · Safety / access · Process / quality · Setup / adjust · Bearings / rollers · Folder / nips · Other

### Electrical
Sensors / switches / limits · Power / supply / batteries · Drives / motors / DC bus · Controls / PLC / reset · Wiring / connections · Setup / calibrate · Other

### Mech/Elec
Cylinder load / arms · Sensors & mechanics · Interlock / safety · Setup / calibrate · Other

### Maintenance
Planned service · Inspection · Lubrication / greasing · Preventive check · Other

### Building
Floor / structure · Doors / latches · Access / safety · Other

### Pre/Post Press Spec
Process / quality · Mechanical · Electrical · Setup / adjust · Other

Code: `lib/constants/failure_subtypes.dart` → `FailureSubtypes.suggestionsFor(JobType)`.

---

## Implementation steps (mobile) — done

1. **Model** — `failureSubtype` on `JobCard` (fromFirestore / copyWith).
2. **Actions** — `completeJob(..., failureSubtype:)` field-scoped write.
3. **UI** — Complete + Monitor (detail + My Work): `FailureSubtypeField` chips + free text.
4. **Past values** — `FirestoreService.fetchFailureSubtypeHistory(type)` (limit 120, client filter).
5. **Display** — Detail hero shows `Subtype: …` when set.
6. **Seeds** — `lib/constants/failure_subtypes.dart` by `JobType`.
7. **Pulse / export / skill** — monorepo already reads/writes `failureSubtype`.

### Not in v1
- Force subtype required  
- Global subtype enum in rules  
- Changing subtype seeds without app release (later: Firestore config doc if needed)

---

## Status change audit (done 2026-07-26)

Manager **Change Status** dialog now:

- Requires a **reason** for every status change  
- **Closed** or **Monitor**: reason is also written to **correctiveAction** (+ log)  
- All changes: **notes** + **notesLog** + **assignmentHistory** narrative  
- Stamps **`lastUpdatedBy` / `lastUpdatedByName`** so `onJobCardWritten` → `job_card_audit` has an actor  
- Includes **In Progress** in the picker (was missing)

---

## Testing checklist

- [ ] Complete with subtype suggestion selected → field on doc  
- [ ] Complete with free-typed subtype → field + appears in next job’s suggestions  
- [ ] Complete with blank subtype → still succeeds  
- [ ] Electrical job only shows electrical-leaning seeds  
- [ ] Manager status → Closed without reason blocked  
- [ ] Manager status → Closed with reason appears in CA + audit actor  
- [ ] Manager status → Open with reason appears in notes + audit  
