# CTP Fleet Maintenance — Cost Manager Guide

*A plain-language guide for recording spend and reviewing fleet costs*

---

## What you use this for

Mechanics log **what they did** on fleet machines (forks, grab or BT). You record **what it cost** — parts, invoices, labour, and other spend. Mechanics never see amounts; only you and admins do.

Your main tabs:

| Tab | What it is |
|-----|------------|
| **Costs** | Queue of mechanic jobs — enter spend against each job |
| **Reports** | Totals, spend per machine, and export for accounts |

---

## The two ways to add a cost

### 1. Cost against a mechanic job (most common)

Use when the spend relates to work the mechanic logged (repair, service, parts for that job).

1. Open **Fleet** → **Costs** tab
2. Find the job in the list (last 50 jobs, newest first)
3. **Orange “Needs costing”** = no costs yet → **tap the job**
4. Fill in what was purchased, amount (R), category, invoice details
5. Tap **Save cost**

The job turns **green “Costed”**. You can tap it again later to **add more cost lines** to the same job.

**Entering a cost locks the job for the mechanic** — they can no longer edit what they wrote, so your costs always match the work as you reviewed it. (Mechanics can still add comments.)

**Filters on Costs tab** (opens on **Needs costing** — your work queue):

| Filter | Shows |
|--------|--------|
| **All jobs** | Every job in the list (orange = still needs costing) |
| **Needs costing** | Only jobs with no costs entered yet |
| **Costed** | Only jobs that already have at least one cost line |
| **No cost** | Jobs you marked as needing no spend |

You can also filter by **Machine** or **Job type**.

### Jobs with no spend — "No cost needed"

Some jobs cost nothing (an adjustment, an inspection). Open the job and tap
**No cost needed** — it leaves the costing queue (grey **No cost** badge)
without a zero-value entry. This also locks the job for the mechanic.

### 2. General cost (not tied to a job)

Use for spend on a machine that is **not** linked to one mechanic job — e.g. annual contract, delivery fee, stock not tied to a specific repair.

1. On the **Costs** tab, tap **General cost** (bottom-right)
2. Pick the machine, category, description, and amount
3. Leave **Link to mechanic's job** empty (or link one if you change your mind)
4. Tap **Save cost**

---

## Cost categories

| Category | Typical use |
|----------|-------------|
| **Parts** | Parts or materials bought for a machine |
| **Labour** | External labour or contractor invoice |
| **Invoice** | Full supplier invoice (may cover several items) |
| **Other** | Delivery, consumables, anything else |

---

## Add Cost form — field guide

| Field | Required? | Notes |
|-------|-----------|--------|
| Which machine? | Yes | The machine this spend applies to |
| Link to mechanic's job | No | Pre-filled when you tap a job from the Costs list |
| What type of cost? | Yes | Parts / Labour / Invoice / Other |
| What was purchased / paid for? | Yes | Short description for reports |
| Amount (Rands) | Yes | VAT-inclusive amount you want recorded |
| Invoice number | No | Helps matching to supplier paperwork |
| Supplier | No | Who you paid |
| Invoice / payment date | Yes | Date on the invoice or when paid |

---

## Reports tab

Use **Reports** to review spend and export data.

1. Open **Fleet** → **Reports**
2. Choose **This month** (use arrows to change month) or **Year to date**
3. See:
   - **Total spend** for the period
   - **Number of cost lines**
   - **Spend per machine** (bar chart)
   - Full list of every cost line
4. Tap **Export CSV** to share a spreadsheet (e.g. email to accounts)

The CSV includes date, machine, job number (if linked), category, description, amount, invoice, supplier, and who entered it.

---

## How jobs and costs stay in sync

```
Mechanic logs job → appears on Costs tab (Needs costing)
        ↓
You enter cost(s) linked to that job → job marked Costed
        ↓
Costs appear in Reports for the invoice/payment month
```

- A job can have **multiple cost lines** (e.g. parts invoice + labour invoice).
- A job with **no spend**: tap **No cost needed** on the job so it leaves the queue.
- Deleting the **last** cost line on a job puts it back in the **Needs costing** queue.
- **General costs** without a job link still appear in Reports under the machine name.

---

## Quick reference

| I want to… | Do this |
|------------|---------|
| Enter costs for a repair | **Costs** → tap orange job → **Save cost** |
| Enter spend not tied to one job | **General cost** FAB |
| Job had no spend | Open job → **No cost needed** |
| See what's still uncosted | **Costs** → **Needs costing** filter |
| Review monthly spend | **Reports** → This month |
| Export for accounts | **Reports** → **Export CSV** |
| Add another invoice to same job | **Costs** → tap green job → **Add Cost** on detail |

---

## Need access?

If you do not see **Costs** or **Reports**, ask an admin to add your **clock number** under **Fleet Settings → Cost manager clock numbers**.