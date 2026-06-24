# Waste Recovery — CTP Pulse Guide (Managers & Admins)

*For Security Managers and Admins using **CTP Pulse** after mobile field capture.*

Mobile (Job Cards app) handles **schedule, stock, collection, and finish loading**. Pulse handles **queues, weighbridge, cost approval, reports, and settings**.

---

## Who does what (after 22 June 2026)

| Role | Mobile (Job Cards) | CTP Pulse |
|------|-------------------|-----------|
| **Security Guard** | Schedule, begin collection, link stock at collection, submit | View loads only (if `waste` board claim); **no on-site stock inventory page** |
| **Security Manager** | Browse on-site stock + copper ready panel; link stock at collection | Weighbridge, schedule/edit loads, overview queues, stock page |
| **Admin** | Same field capture | Weighbridge + **cost review** + settings + reports |

---

## Finding your queues

### Board overview (`/waste`)

- **Pending Weighbridge** and **Pending Cost Review** KPI cards link directly to the queue pages.
- The action strip below the KPIs repeats the same counts with one-click navigation.

### Sidebar badges

- **Weighbridge** — count of loads in `pending_weighbridge` (manager+).
- **Review** — count of loads in `pending_cost_review` (admin only).

---

## Weighbridge (Manager / Admin)

**Path:** CTP Pulse → Waste → **Weighbridge**

Applies to weight-based and no-on-site-weight loads. Quantity-only types (e.g. IBC Bins) skip this step on mobile and arrive straight in cost review.

1. Open a pending load from the queue.
2. Enter **ticket/reference number** and **certified weight (kg)**.
3. Upload the weighbridge document photo, or waive the ticket (manager audit).
4. Submit.

**On submit:**
- Load moves to **Pending Cost Review**.
- Deviation is calculated (default **5%** or **50 kg**, whichever triggers first).
- Deviations are written to `waste_audit` for admin visibility.

Suggested cost lines are pre-calculated using live `waste_types` and contractor rates.

---

## Cost review (Admin only)

**Path:** CTP Pulse → Waste → **Review**

Cost is approved **per waste type on the load**, not per item.

1. Each pending load shows a table: waste type, weight (kg), editable **R/kg**, line value.
2. **Calculated total** sums the lines; **Approved total** defaults to the calculated value (edit to match accounts if needed).
3. Tap **Approve** — load becomes **Completed** with `cost_by_type` saved.
4. Rates entered during review are upserted to `waste_rates` keyed by **waste_type**.
5. **Copper Waste loads:** approval also writes `record_sale_from_waste` in `copper_transactions` (linked to load id; audit only).

Open **Details** to see the full load including `cost_by_type` breakdown after completion.

---

## Settings (Admin)

**Path:** CTP Pulse → **Settings** → Waste section

| Setting | Purpose |
|---------|---------|
| **Waste Recovery Enabled** | Master toggle for mobile tab + Pulse module |
| **Photos Required** | When on, item/stock/truck photos mandatory at collection (mobile + Pulse load forms) |
| **Driver Signature Required** | When on, signature mandatory when finishing collection |
| **Waste Types** | Master type list; link types to contractors |
| **Contractors** | Approved collectors + linked waste types |
| **Rates** | R/kg per contractor + **waste type** (not per item subtype) |
| **Deviation Thresholds** | % and kg for weighbridge flags |
| **Permissions** | Manager and guard clock numbers |

---

## Reports & audit

- **Reports:** `/waste/reports` — date range, status/deviation filters, CSV (loads + cost lines), PDF with `cost_by_type` summary. Board charts drill down via `?month=YYYY-MM&type=…` query params.
- **Audit log:** `/waste/audit` — weighbridge deviations, soft deletes, historic imports (admin).

## Historic import (Admin)

**Path:** CTP Pulse → Waste → **Import**

Upload the legacy Excel register (sheets named *Waste* / *Waste Reels*). Preview rows before import; duplicates (same sheet + Doc Num) are auto-skipped. Imported loads are `completed` with `source: historic_import` and `cost_by_type` when rate/value columns are present.

## Soft delete (Admin)

**Path:** CTP Pulse → Waste → **Loads → Edit** → Admin — Soft Delete

Hides the load from all queues and lists. Full snapshot archived to `waste_deleted_loads`; linked stock returns to on-site. Logged in `waste_audit` as `soft_delete`.

---

## Finish loading on Pulse (draft loads)

Managers can finish draft loads on **Loads → Edit** as well as on mobile:

- Optional truck photos and driver signature (respects settings toggles).
- **Quantity-only** waste types automatically skip weighbridge (`skip_weighbridge`) and go to cost review.

---

## Quick manager day

1. Check **Board** or sidebar badges for pending counts.
2. When tickets arrive → **Weighbridge** queue.
3. Hand off to admin for **Review** (or approve yourself if admin).
4. Use **Reports** for month-end accounts.

---

*CTP Waste Recovery · Pulse Guide · Updated 22 June 2026*