# Waste Recovery — Full Load Guide

*For Security Managers, Security Guards, and Admins*

This guide walks through the **complete waste load lifecycle** in WasteTrack — from recording stock on site, through scheduling or creating a load, loading capture (items + loaded-truck photos + driver signature), **off-site weighbridge document** entry, and **admin cost review**.

> **There is no on-site weighbridge.** The truck leaves after loading. The certified weight arrives later on a mailed/email weighbridge document.

---

## Who does what?

| Role | Typical tasks |
|------|----------------|
| **Security Manager** | Record paper stock; schedule loads; create on-the-spot loads; link stock; capture loaded-truck photos; enter off-site weighbridge documents |
| **Security Guard** | Begin scheduled collections; confirm or add waste items; loaded-truck photos; driver signature; submit collection |
| **Admin** | Everything above, plus **Review** (approve costs), **Settings** (contractors, types, rates). Reports are on **CTP Pulse** only. |

> **Guards can schedule loads** only when an admin has enabled *Guards Can Schedule Loads* in CTP Pulse → Waste Settings.

---

## The big picture

There are **two ways** a load starts, but both follow the same path after loading: **Pending Weighbridge** → weighbridge document → **Pending Cost Review** → admin **Completed**.

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
           ┌────────▼────────┐                                            ┌───────────▼──────────┐
           │ Truck photos +  │                                            │ Finish Loading:      │
           │ driver sign →   │                                            │ truck photos + sign  │
           │ Pending         │                                            │ → Pending Weighbridge│
           │ Weighbridge     │                                            └───────────┬──────────┘
           └────────┬────────┘                                                        │
                    └────────────────────────────┬───────────────────────────────────┘
                                                 │
                                    ┌────────────▼────────────┐
                                    │ Off-site weighbridge    │
                                    │ ticket photo + weight   │
                                    │ → Pending Cost Review   │
                                    └────────────┬────────────┘
                                                 │
                                    ┌────────────▼────────────┐
                                    │ Admin Review tab        │
                                    │ Approve cost → Completed│
                                    └─────────────────────────┘
```

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
4. **Expected date & time** — when the truck is due.
5. **Notes** — optional instructions for the guard.
6. Tap **Schedule Load**.

The load appears under **Incoming** on the Loads tab with status **Scheduled**.

### Option B — New Load on the spot (truck is here now)

*Managers and admins only.*

1. **Contractor** — select the collecting company.
2. **Waste types** — select one or more chips (same multi-select behaviour as scheduling).
3. **On-site stock (optional)** — tick stock to include, or use **Add Waste Item → Add from on-site stock** later.
4. Enter **driver name**, **vehicle registration**, and optional notes.
5. **Waste items** — tap **Add Waste Item**:
   - **Add from on-site stock** — pick already-captured stock items.
   - **Capture new item** — take photos, enter weight (and optional quantity). At least one photo per fresh item is required.
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
   - Tap **Fresh item** to capture new material with photos.
   - Every item on the list must have at least one photo before you can submit.
5. **Loaded truck photos** — photograph the fully loaded truck before it leaves.
6. Tap **Capture Driver Signature** — pass the phone to the driver to sign.
7. Tap **Submit Collection**.

Status changes to **Pending Weighbridge**. The truck does not return — wait for the off-site weighbridge document.

---

## Step 4 — Off-site weighbridge document (Manager / Admin)

When the weighbridge ticket arrives (email/photo/PDF — truck does not return):

### From the Weighbridge tab

1. Open the **Weighbridge** tab (badge shows how many are waiting).
2. Tap a load to open its detail.
3. Scroll to **Off-site Weighbridge Document**.
4. Enter the **ticket/reference number**.
5. Photograph the **weighbridge document**.
6. Enter the **certified weight in kg**.
7. Tap **Submit Weighbridge Document**.

The load moves to **Pending Cost Review** for admin approval.

### From load detail

Same steps — open any **Pending Weighbridge** load from Recent loads.

---

## Step 5 — Admin cost review

1. Open the **Review** tab (admin only; badge shows pending count).
2. The review card shows an **itemized cost table**:
   - Each waste item on the load is shown with its **subtype**, **weight**, an editable **R/kg rate**, and a calculated **value**.
   - The **R/kg** field is pre-filled from the contractor's rate register where a rate exists. Empty fields show a ⚠ warning — enter the rate from the physical document.
   - The **Calculated total** (sum of all line values) updates live as you edit rates.
3. The **Approved amount** field defaults to the calculated total. Edit it to match the accounts document if they differ.
4. Tap **Approve** — the system saves both the calculated total and the approved amount separately for audit.

> Rates entered or corrected during review are saved back to the rate register — the same contractor + subtype pair will be pre-filled automatically on future collections.

Reports and exports are available on **CTP Pulse → Waste → Reports**.

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
4. Load becomes **Pending Weighbridge** — enter the off-site document when it arrives (Step 4).

---

## Load statuses explained

| Status | Meaning | What to do next |
|--------|---------|-----------------|
| **Scheduled** | Manager scheduled the collection; truck not yet processed | Guard taps **Begin Collection** when contractor arrives |
| **Draft** | On-the-spot load created; truck still loading | Manager: **Finish Loading** (truck photos + signature) |
| **Pending Weighbridge** | Loading finished; awaiting off-site document | Manager: photograph ticket + enter certified weight |
| **Pending Cost Review** | Weighbridge document captured | Admin: approve cost in **Review** tab |
| **Completed** | Admin approved cost | Record is locked |
| **Cancelled** | Load was cancelled before collection | No further action |

---

## Deviation alerts

When the weighbridge weight is saved, the app compares:

- **Recorded weight** — sum of item weights on the load
- **Actual weight** — certified weighbridge reading

A **deviation** is flagged if the difference exceeds **5%** or **50 kg** (whichever applies first). Flagged loads show an amber warning in detail view and in **Reports**. This is for management review — not an automatic rejection.

---

## Paper Waste Stock banner

On the Loads tab, the green **Paper Waste Stock** banner shows how many items are on site and the total estimated weight. Tap it to open the stock inventory.

---

## Tips & troubleshooting

**Stock not showing when I select waste types**
- Stock lives under Paper Waste subtypes. Make sure the matching chips are selected (e.g. *Reelends*, *Slab Waste*).
- Only **on-site** stock appears — items already loaded on another truck are excluded.

**Cannot submit collection**
- Need driver name, vehicle reg, at least one item, every item must have a photo, at least one **loaded-truck photo**, and a driver signature.

**Weighbridge tab is empty**
- Only loads in **Pending Weighbridge** appear. Guard must submit collection first.

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
- [ ] Schedule load: contractor, waste types, stock, date
- [ ] After guard submits: enter off-site weighbridge document when received

### Guard — collection
- [ ] Begin Collection on incoming load
- [ ] Driver details + confirm items (stock + fresh photos)
- [ ] Loaded-truck photos + driver signature
- [ ] Submit Collection

### Manager — truck already here
- [ ] New Load on the spot: contractor, types, items/stock
- [ ] Finish loading: truck photos + signature
- [ ] Enter weighbridge document when it arrives

### Admin
- [ ] Review tab: enter/confirm R/kg rates for each item
- [ ] Check calculated total; edit Approved amount if accounts differ
- [ ] Tap Approve → Completed
- [ ] Share PDF from load detail if needed for accounts filing

---

*CTP WasteTrack · Waste Recovery Load Guide*