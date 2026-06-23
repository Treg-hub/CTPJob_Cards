# Waste Recovery — Full Load Guide

*For Security Managers, Security Guards, and Admins*

This guide walks through the **complete waste load lifecycle** in WasteTrack — from recording stock on site, through scheduling or creating a load, loading capture (items + loaded-truck photos + driver signature), **off-site weighbridge document** entry, and **admin cost review**.

> **There is no on-site weighbridge.** The truck leaves after loading. The certified weight arrives later on a mailed/email weighbridge document.

---

## Who does what?

| Role | Typical tasks |
|------|----------------|
| **Security Manager** | Record stock; schedule loads; create on-the-spot loads; link stock; capture loaded-truck photos; finish loading |
| **Security Guard** | Same field-capture tasks: schedule, stock, begin collections, items, optional photos/signature, submit |
| **Admin** | Same on mobile. **Weighbridge, cost review, reports, and settings** are on **CTP Pulse** only. |

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

**Photos:** Photos are optional per item. For quantity-only and no-on-site-weight types, the loaded-truck photo captures the visual evidence for the whole load. For weight-based items, photographing the material is strongly recommended.

---

## Step 0 — Record stock on site (optional but recommended)

Use this when waste is **already sitting on site** before the truck arrives (e.g. slab waste, reelends, scrap reels).

1. On the **Loads** tab, tap **+ New / Schedule** → **Paper Waste Stock**.
2. Tap **+** to record a new stock item: choose subtype, take photos, enter estimated weight.
3. The item stays **On Site** until it is linked to a load and the collection is confirmed.

Stock is stored under **Paper Waste** with a **subtype** (e.g. *Slab Waste*, *Reelends*, *Scrap Reels*) — even when the contractor's waste types are listed as separate chips.

---

## Step 1 — Create the load

Tap **+ New / Schedule** on the Loads tab.

### Option A — Schedule Incoming Load (before the truck arrives)

*Managers, admins, and guards (if enabled).*

1. **Contractor** — select who is collecting (e.g. Glenpak).
2. **Waste types** — tap one or more chips. All contractor types are pre-selected; deselect any you do not need. Stock and new items are **filtered to your selection**.
3. **On-site stock (optional)** — tick saved stock items to pre-link. The guard will see these when collection starts.
4. **Expected date** — the day the truck is due. Time is not required.
5. **Notes** — optional instructions for the guard.
6. Tap **Schedule Load**.

The load appears under **Incoming** on the Loads tab with status **Scheduled**.

> **Admins only:** dates can be set to any past date (for corrections or testing). All other users can only schedule today or future dates.

### Option B — New Load on the spot (truck is here now)

*Managers and admins only.*

1. **Contractor** — select the collecting company.
2. **Waste types** — select one or more chips (same multi-select behaviour as scheduling).
3. **On-site stock (optional)** — tick stock to include, or use **Add Waste Item → Add from on-site stock** later.
4. Enter **driver name**, **vehicle registration**, and optional notes.
5. **Waste items** — tap **Add Waste Item**:
   - **Add from on-site stock** — pick already-captured stock items.
   - **Capture new item** — see *Waste item types* above for what the form shows.
6. Tap **Create Load**.

The load is saved as **Draft**. Open it from Recent loads to continue with weighbridge and signature (see Path B below).

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
   - Pre-linked stock appears automatically (marked *Pre-loaded*).
   - Tap **From stock** to add more saved items found at the gate.
   - Tap **Fresh item** to capture new material.
   - **Weight-based items:** enter weight in kg. Photos recommended.
   - **Quantity-only items** (e.g. IBC Bins): enter count only — no weight field.
   - **No-on-site-weight items** (e.g. compactor bins): enter count — weight confirmed at weighbridge.
5. **Loaded truck photos** — photograph the fully loaded truck before it leaves. At least one is required.
6. Tap **Capture Driver Signature** — pass the phone to the driver to sign.
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

Reports and exports: **CTP Pulse → Waste**.

---

## Sharing a load summary (PDF)

On any **completed** load, tap the **↑ share icon** in the app bar to generate a PDF summary containing:
- Load number, date, contractor, driver, vehicle
- Itemised waste items (subtype, weight, rate, value)
- Weighbridge weight and deviation
- Calculated and approved cost

Share or print directly from your phone.

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

A **deviation** is flagged if the difference exceeds **5%** or **50 kg** (whichever applies first). Flagged loads show an amber warning in detail view and in **Reports**. This is for management review — not an automatic rejection.

> For **no-on-site-weight items** (compactor bins, copper skins), the on-site recorded weight is zero by design — only the weighbridge total is meaningful. Deviation will appear as 100% for these items; this is expected and can be ignored. Only the weighbridge weight is used for cost calculations.

---

## Paper Waste Stock banner

On the Loads tab, the green **Paper Waste Stock** banner shows how many items are on site and the total estimated weight. Tap it to open the stock inventory.

---

## Admin — Manage waste types

Go to **Waste → Admin → Manage Waste Types** to configure types and their weight mode.

Each type has two toggles:

| Toggle | Behaviour |
|--------|-----------|
| **Quantity only (no weight)** | Guard enters count only; weighbridge step skipped; priced per unit (e.g. IBC Bins) |
| **No on-site weight** | Guard enters count only; weighbridge still required; weight confirmed on ticket (e.g. compactor bins) |

The two toggles are mutually exclusive — turning one on clears the other. Leave both off for standard weight-based types (paper waste, copper offcuts).

---

## Tips & troubleshooting

**Stock not showing when I select waste types**
- Stock lives under Paper Waste subtypes. Make sure the matching chips are selected (e.g. *Reelends*, *Slab Waste*).
- Only **on-site** stock appears — items already loaded on another truck are excluded.

**Cannot submit collection**
- Need: driver name, vehicle reg, at least one item, at least one **loaded-truck photo**, and a driver signature.
- Weight-based items need a weight entered. Quantity-only and no-on-site-weight items need a count entered.
- Per-item photos are optional — the truck photo is the primary evidence.

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
- [ ] Record stock (optional)
- [ ] Schedule load: contractor, waste types, stock, expected date
- [ ] After guard submits: enter off-site weighbridge document when received *(not needed for IBC Bins)*

### Guard — collection
- [ ] Begin Collection on incoming load
- [ ] Driver details + confirm/add items
  - Weight-based: enter weight (photos optional but recommended)
  - IBC Bins / compactor bins: enter quantity only
- [ ] At least one loaded-truck photo + driver signature
- [ ] Submit Collection

### Manager — truck already here
- [ ] New Load on the spot: contractor, types, items/stock
- [ ] Finish loading: truck photos + signature
- [ ] Enter weighbridge document when it arrives *(not needed for IBC Bins)*

### Admin
- [ ] Review tab: enter/confirm R/kg rates for each item
- [ ] Check calculated total; edit Approved amount if accounts differ
- [ ] Tap Approve → Completed
- [ ] Share PDF from load detail if needed for accounts filing

---

*CTP WasteTrack · Waste Recovery Load Guide · Updated 16 June 2026*
