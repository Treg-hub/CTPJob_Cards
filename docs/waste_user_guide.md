# Waste Recovery — Full Load Guide

*For Security Managers, Security Guards, and Admins*

This guide walks through **mobile field capture** in WasteTrack — recording stock on site, scheduling or creating a load, and collection (items + loaded-truck photos + driver signature). **Weighbridge, cost review, reports, and settings** are on **CTP Pulse** only (see `waste_pulse_guide.md`).

> **There is no on-site weighbridge.** The truck leaves after loading. The certified weight arrives later on a mailed/email weighbridge document.

---

## Who does what?

| Role | Typical tasks |
|------|----------------|
| **Security Manager** | Browse on-site stock inventory; see **Copper ready to sell**; schedule loads; link stock **on collection day**; begin collections; finish loading |
| **Security Guard** | Schedule loads; **begin collections**; link saved stock **at collection** (From stock); items, photos, signature, submit — **does not browse on-site stock inventory** |
| **Admin** | Same as manager on mobile. **Weighbridge, cost review, reports, and settings** are on **CTP Pulse** only. |

> **Mobile = field capture.** After collection the load stops at **Pending Weighbridge** or **Pending Cost Review** — managers and admins complete those steps on CTP Pulse.

---

## The big picture

There are **two ways** a load starts. After loading, the path depends on the waste type:

- **Weight-based and no-on-site-weight loads** → Pending Weighbridge → weighbridge document → Pending Cost Review → Completed.
- **Quantity-only loads** (e.g. IBC Bins) → skip weighbridge → go straight to Pending Cost Review → Completed.

```
  ┌─────────────────┐     ┌──────────────────┐     ┌─────────────────────┐
  │ 1. Stock (opt.) │ ──► │ 2. Create load   │ ──► │ 3. Items + photos   │
  │  Paper Waste    │     │  Schedule OR     │     │  On-site stock or   │
  │  Stock screen   │     │  New on the spot │     │  fresh capture      │
  └─────────────────┘     └──────────────────┘     └──────────┬──────────┘
                                                              │
                    ┌─────────────────────────────────────────┴────────────────────────┐
                    │                                                                   │
           ┌────────▼────────┐                                            ┌───────────▼──────────┐
           │ SCHEDULED PATH  │                                            │ ON-THE-SPOT PATH     │
           │ Guard: Begin    │                                            │ Manager: New Load    │
           │ Collection      │                                            │ (Draft status)       │
           └────────┬────────┘                                            └───────────┬──────────┘
                    │                                                                   │
                    └────────────────────┬──────────────────────────────────────────────┘
                                         │
              ┌──────────────────────────┴──────────────────────────┐
              │  Weight-based / No-on-site-weight loads              │  Quantity-only loads
              ▼                                                       │  (e.g. IBC Bins)
   ┌─────────────────────┐                                           │
   │ Pending Weighbridge │                                           │
   │ Manager enters      │                                           │
   │ ticket + weight     │                                           │
   └──────────┬──────────┘                                           │
              └──────────────────────────┬──────────────────────────┘
                                         ▼
                            ┌────────────────────────┐
                            │  Pending Cost Review   │
                            │  Admin approves cost   │
                            └────────────┬───────────┘
                                         ▼
                            ┌────────────────────────┐
                            │  Completed             │
                            └────────────────────────┘
```

---

## Waste item types

When adding an item to a load, the form adapts to the waste type. There are three modes:

| Mode | What guard enters | Weighbridge | Example types |
|------|-------------------|-------------|---------------|
| **Weight-based** | Weight (kg) + optional quantity | Required | Paper waste, copper offcuts |
| **Quantity only** | Count only (no weight) | Skipped — goes straight to cost review | IBC Bins |
| **No on-site weight** | Count only (no weight) | Still required — weight confirmed on ticket | Compactor bins, open bins, copper skins |

> The form automatically shows the correct fields for the selected type — you do not need to choose a mode manually.

**Photos:** Controlled by **Photos Required** in CTP Pulse → Settings → Waste. When off (default), item and stock photos are optional; loaded-truck photos are still recommended. When on, each manual item needs at least one photo and stock items need at least one photo.

**Signature:** Controlled by **Driver Signature Required** in the same settings panel. Optional by default at launch.

---

## Step 0 — On-site stock (managers & admins)

**Security managers and admins** can browse and record on-site stock. **Guards do not** see the stock inventory screen or banner — they link saved stock **on collection day** via **Begin Collection → From stock** (see Step 3).

### Manual stock (paper, etc.)

Use this when waste is **already sitting on site** before the truck arrives (e.g. slab waste, reelends, scrap reels).

1. On the **Loads** tab, tap **+ New / Schedule** → **On-site Stock** (or tap the green stock banner).
2. Tap **+** to record a new item: choose type, take photos if required, enter estimated weight (or quantity for quantity-only types).
3. The item stays **On Site** until linked to a load on **collection day** and the collection is submitted.

Paper-family stock is stored under **Paper Waste** with a **subtype** (e.g. *Slab Waste*, *Reelends*, *Scrap Reels*).

### IBC Bins (automatic from Ink Factory)

When an ink operator **consumes an IBC** in the Ink Factory app, the system automatically adds **one IBC Bin** to on-site waste stock (identified by **IBC number**). No photo is required on the stock record — guards add photos at collection if **Photos Required** is on.

- Visible to **guards and managers** in the stock inventory (managers) or when linking at collection (guards).
- **Quantity-only** — weighbridge is skipped; cost review uses **count × rate**.
- If an ink manager **voids** the consumption, the linked stock item is removed automatically.

### Copper ready to sell (managers & admins only)

Copper rods and nuggets are tracked in the separate **Copper** module (whitelist staff). The Waste tab shows a **Copper ready to sell** panel for **security managers and admins only** — guards never see this.

| Stage | What you see |
|-------|----------------|
| Below **400 kg** total in the copper sell bucket | Panel shows rods/nuggets kg still in the copper module — not yet waste stock |
| **400 kg or more** | System auto-creates **Copper Waste** on-site stock (Rods and/or Nuggets). Copper module sell bucket resets. Panel shows kg awaiting collection |
| Collection day | Schedule a **Copper Waste** load (no need to pre-link stock). On collection, tap **From stock** and select the auto-created items |

When an admin **approves cost** on Pulse for a Copper Waste load, the commercial sale is recorded in copper transactions automatically.

---

## Step 1 — Create the load

Tap **+ New / Schedule** on the Loads tab.

### Option A — Schedule Incoming Load (before the truck arrives)

*All waste users (guard, manager, admin).*

1. **Contractor** — select who is collecting (e.g. Glenpak).
2. **Waste types** — tap one or more chips. All contractor types are pre-selected; deselect any you do not need. Stock and new items are **filtered to your selection**.
3. **On-site stock (optional)** — managers may pre-link stock when scheduling. For **IBC Bins** and **Copper Waste**, linking usually happens **on collection day** instead (see Step 3).
4. **Expected date** — the day the truck is due. Time is not required.
5. **Notes** — optional instructions for the guard.
6. Tap **Schedule Load**.

The load appears under **Incoming** on the Loads tab with status **Scheduled**.

> **Admins only:** dates can be set to any past date (for corrections or testing). All other users can only schedule today or future dates.

### Option B — New Load on the spot (truck is here now)

*All waste users.*

1. **Contractor** — select the collecting company.
2. **Waste types** — select one or more chips (same multi-select behaviour as scheduling).
3. **On-site stock (optional)** — tick stock to include, or use **Add Waste Item → Add from on-site stock** later.
4. Enter **driver name**, **vehicle registration**, and optional notes.
5. **Waste items** — tap **Add Waste Item**:
   - **Add from on-site stock** — pick already-captured stock items.
   - **Capture new item** — see *Waste item types* above for what the form shows.
6. Tap **Create Load**.

The load is saved as **Draft** with `selected_waste_types` recorded. Open it from Recent loads and **Finish Loading** (see Path B below).

---

## Step 2 — Multi-type loads (e.g. Glenpak)

Some contractors collect **several paper subtypes on one truck** (slab waste + reelends + scrap reels).

- Select **all relevant chips** when creating or scheduling the load.
- On-site stock list shows only items matching your selected types.
- **Add Waste Item** only offers subtypes you have selected.
- The load saves as **Paper Waste** in the system so stock linking works correctly.

---

## Step 3 — Guard collects a scheduled load

When the contractor arrives:

1. On the **Loads** tab, find the load under **Incoming**.
2. Tap **Begin Collection**.
3. Enter **driver name** and **vehicle registration**.
4. **Waste items:**
   - Pre-linked stock appears automatically (marked *Pre-loaded*) if the manager linked any at schedule time.
   - Tap **From stock** to link saved on-site items (IBC bins, copper, paper, etc.). **Guards use this** even though they do not browse the stock inventory list.
   - Tap **Fresh item** to capture new material.
   - **Weight-based items:** enter weight in kg. Photos recommended.
   - **Quantity-only items** (e.g. IBC Bins): enter count only — no weight field.
   - **No-on-site-weight items** (e.g. compactor bins): enter count — weight confirmed at weighbridge.
5. **Loaded truck photos** — photograph the fully loaded truck before it leaves (recommended; required when Photos Required is on).
6. **Driver signature** — capture when required by settings, or optional when off.
7. Tap **Submit Collection**.

**After submission:**
- Weight-based or no-on-site-weight loads → **Pending Weighbridge**.
- Quantity-only loads (IBC Bins) → **Pending Cost Review** (weighbridge skipped).

---

## Step 4 — Off-site weighbridge document (CTP Pulse — Manager / Admin)

*Only applies to weight-based and no-on-site-weight loads. Quantity-only loads skip this step.*

When the weighbridge ticket arrives (email/photo/PDF — truck does not return), use **CTP Pulse → Waste → Weighbridge**:

1. Open the pending load from the weighbridge queue (sidebar badge shows count).
2. Enter the **ticket/reference number** and **certified weight in kg**.
3. Upload or waive the weighbridge document photo.
4. Submit — deviation is audited automatically if thresholds are exceeded.

The load moves to **Pending Cost Review**.

---

## Step 5 — Admin cost review (CTP Pulse only)

Use **CTP Pulse → Waste → Review** (admin only):

1. Each load shows **one cost line per waste type** (not per item).
2. Edit **R/kg** per type; calculated total updates live.
3. Confirm **Approved amount** and tap **Approve** — load becomes **Completed** with `cost_by_type` saved.
4. **Copper Waste loads:** approving also records the sale in the copper module (audit transaction linked to the load).

Reports and exports: **CTP Pulse → Waste**.

---

## After mobile — use CTP Pulse

See **`waste_pulse_guide.md`** for weighbridge, cost review, reports, and settings on Pulse.

---

## Path B — On-the-spot load (Draft) finish loading

When a manager creates a **New Load on the spot**:

1. Open the **Draft** load from Recent loads.
2. Add or edit items / stock if needed.
3. Tap **Finish Loading** — add **loaded-truck photos** and capture **driver signature**.
4. Load becomes **Pending Weighbridge** (or **Pending Cost Review** for quantity-only loads) — enter the off-site document when it arrives (Step 4).

---

## Load statuses explained

| Status | Meaning | What to do next |
|--------|---------|-----------------|
| **Scheduled** | Manager scheduled the collection; truck not yet processed | Guard taps **Begin Collection** when contractor arrives |
| **Draft** | On-the-spot load created; truck still loading | Manager: **Finish Loading** (truck photos + signature) |
| **Pending Weighbridge** | Loading finished; awaiting off-site document | Manager on **CTP Pulse → Weighbridge** |
| **Pending Cost Review** | Weighbridge captured (or quantity-only load) | Admin on **CTP Pulse → Review** |
| **Completed** | Admin approved cost | Record is locked |
| **Cancelled** | Load was cancelled before collection | No further action |

---

## Deviation alerts

When the weighbridge weight is saved, the app compares:

- **Recorded weight** — sum of item weights entered on-site
- **Actual weight** — certified weighbridge reading

A **deviation** is flagged if the difference exceeds **5%** or **50 kg** (whichever applies first). Flagged loads show on Pulse weighbridge/review and in **Reports**. This is for management review — not an automatic rejection.

> For **no-on-site-weight items** (compactor bins, copper skins), the on-site recorded weight is zero by design — only the weighbridge total is meaningful. Deviation will appear as 100% for these items; this is expected and can be ignored. Only the weighbridge weight is used for cost calculations.

---

## On-site stock banner (managers & admins)

On the Loads tab, managers and admins see a green **on-site stock** banner (estimated weight and/or bin count). Tap it to open the stock inventory.

Guards **do not** see this banner — they link stock only during **Begin Collection → From stock**.

---

## Waste type modes (admin)

Configure types in **CTP Pulse → Settings → Waste → Waste Types** (Firestore `waste_types` documents).

| Flag | Behaviour |
|------|-----------|
| **Quantity only** (`isQuantityOnly`) | Count only on mobile; skips weighbridge → cost review |
| **No on-site weight** (`noSiteWeight`) | Count on mobile; weighbridge still required on Pulse |

Leave both off for standard weight-based types.

---

## Tips & troubleshooting

**Stock not showing when I select waste types**
- Paper stock lives under Paper Waste subtypes — select matching chips (e.g. *Reelends*, *Slab Waste*).
- **IBC Bins** loads: link stock with waste type **IBC Bins**; bins appear after ink operators consume IBCs.
- **Copper Waste** loads: manager-only stock appears after copper sell total reaches **400 kg**; use **From stock** on collection day.
- Only **on-site** stock appears — items already loaded on another truck are excluded.

**Guard cannot find On-site Stock menu**
- By design. Guards link stock at collection via **From stock**, not the inventory screen.

**IBC consumed in ink but no bin in waste**
- Consumption must complete online. Stock doc id is `stock_ibc_{number}` — retry consume if a prior attempt failed partway.

**Cannot submit collection**
- Need: driver name, vehicle reg, at least one item.
- When **Photos Required** is on: each manual item needs a photo; loaded-truck photo required.
- When **Signature Required** is on: driver signature required.
- Weight-based items need weight; quantity-only / no-site-weight items need count.

**Where is weighbridge / cost review on mobile?**
- Removed from the app (2026-06-22). Use **CTP Pulse**. Pending loads show a handoff banner on mobile load detail.

**Load went straight to Cost Review — no weighbridge step**
- This is correct for quantity-only types (IBC Bins). The cost is calculated by count × rate, not by weight.

**Offline**
- Photos, signatures, and load data queue locally. Tap the orange **cloud sync** banner to retry when back online.
- Loads scheduled while offline appear in the Incoming list once synced; load numbers are assigned at that point.
- Stock items linked to an offline collection sync automatically — they will not remain permanently *Loaded* if the parent load was not yet written.

**I cannot see the Waste tab**
- Your account needs a WasteTrack role. Contact an admin.

---

## Quick checklist

### Manager — scheduled load
- [ ] Check on-site stock banner / copper panel (optional)
- [ ] Schedule load: contractor, waste types, expected date (pre-link stock optional)
- [ ] On collection day: guard or manager links stock via **From stock** if not pre-linked
- [ ] After guard submits: enter off-site weighbridge document when received *(not needed for IBC Bins)*

### Guard — collection
- [ ] Begin Collection on incoming load
- [ ] **From stock** — link IBC bins or other saved items (no inventory browse)
- [ ] Driver details + confirm/add items
  - Weight-based: enter weight (photos optional but recommended)
  - IBC Bins / compactor bins: enter quantity only
- [ ] At least one loaded-truck photo + driver signature when required
- [ ] Submit Collection

### Manager — truck already here
- [ ] New Load on the spot: contractor, types, items/stock
- [ ] Finish loading: truck photos + signature
- [ ] Enter weighbridge document when it arrives *(not needed for IBC Bins)*

### Admin (CTP Pulse)
- [ ] Review queue: confirm R/kg **per waste type**
- [ ] Check calculated total; edit Approved amount if accounts differ
- [ ] Approve → Completed (`cost_by_type` saved)
- [ ] Reports export if needed for accounts

---

*CTP Waste Recovery · Mobile Field Guide · Updated 24 June 2026 · Pulse steps: waste_pulse_guide.md*
