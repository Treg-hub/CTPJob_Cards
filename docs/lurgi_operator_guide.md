# Lurgi — Operator guide (mobile)

*For Lurgi department staff and Admins on CTP Job Cards*

This guide covers **floor capture** on the mobile Lurgi hub: morning plant meters, effluent chemicals, recycling machine runs, ink/toloul Daily Readings, and view-only Ink Factory recovery. **Period review, charts, CSV, and soft-void approval** are on **CTP Pulse** (`boardModules: lurgi`).

---

## Who does what?

| Role | Typical tasks |
|------|----------------|
| **Lurgi operator** | Morning section meters, Daily Readings, chemical doses, recycling runs, request void on mistakes |
| **Admin** | Same as operator, plus **date pickers** to change entry dates for support/testing |
| **Pulse Lurgi desk** | Soft-void requested entries, period KPIs, export |

> **Operators capture at the time of save.** You cannot backdate a forgotten yesterday. Admins may override the entry date when needed.

---

## Daily flow

```
  Hub status
       │
       ├─► Walk plant: Gas → Water → Air → Geyser → Tanks  (save each tile)
       ├─► Daily Readings (ink + toloul) — add missing later same day if needed
       ├─► Chemicals / Recycling as events, or mark “none today”
       └─► View Ink Factory recovery (open count period only)
```

---

## 1. Morning meters (Daily log tiles)

1. Open **Lurgi** from Home.
2. Use **one tile per area** (there is no single “Morning Round” mega-form).
3. Enter dial readings. **Last** and **today’s delta** appear under each field when a prior day exists.
4. If the dial is lower because it was **reset**, tick **Meter was reset**.
5. **Save** before leaving the screen. Drafts survive app close until midnight.
6. If the last capture was **not yesterday**, you get a **multi-day gap** warning — acknowledge it and add a short note. That day’s usage includes the whole gap.

### Toloul tanks

- Level in **L** plus **In** (into tank) or **Out** (to pressroom).
- This is a **snapshot** of state at save time, not a full transfer log.

---

## 2. Daily Readings (ink + toloul)

Shared with Ink Factory metering.

- Enter only meters you are reading now. Blank = skipped.
- **Additive sessions:** if some meters are already “Recorded today”, they are locked. Fill the rest and tap **Add missing readings**.
- **Corrections:** manager voids the session on Pulse, then you re-enter. Do not force a second reading for the same meter the same day.

---

## 3. Effluent chemicals

- Multi-entry per day. **Day total = sum of all entries.**
- If no dosing is required: **No dosing today** (so the desk knows it was intentional).
- Wrong kg? **Request void** + reason. Totals still include the row until Pulse voids it. Do not add a second “correcting” entry.

---

## 4. Recycling machine

- One document per cycle: start/finish, steam temp/press, litres recycled, dirty toloul level, cleaned.
- Operators set **times for today** only. Admins may pick full date+time.
- **No recycling today** when the machine is idle on purpose.
- Wrong run → **Request void**.

---

## 5. Ink Factory recovery (view only)

- List of Ink Factory **recovery** posts for the **open ink count period**.
- Lurgi **does not** post toloul stock recovery. Recycling litres ≠ factory tank recovery.

---

## 6. Period history

Open count window: **Chemicals · Recycling · Recovery · Morning**. Load more if the list is long. Closed periods live on Pulse.

---

## Operator tips on screen

Purple tip cards can be dismissed with **Don’t show again**. They are temporary training aids — removing a tip from the app is done in code by deleting that note widget (`noteId`).

---

## What not to do

| Don’t | Do instead |
|-------|------------|
| Skip a weekday and hope KPIs stay clean | Capture every operating day; note multi-day gaps |
| Submit partial Daily Readings then re-type done meters | Use **Add missing** only |
| Double chemical entries to “fix” a typo | **Request void** |
| Post toloul stock from Lurgi | Ink Factory recovery path only |
| Backdate as an operator | Capture at save time; ask admin only if required |

---

## Related

- In-app: Lurgi hub → **Operator guide** tile  
- Pulse: `/lurgi` desk  
- Map: `Components/Modules/cards/Lurgi.md`  
