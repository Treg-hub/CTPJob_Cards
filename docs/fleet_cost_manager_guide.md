# CTP Fleet Maintenance — Cost Manager Guide

*Recording spend on **CTP Pulse** — not in this mobile app*

---

## What you use this for

Mechanics log **what they did** on fleet machines (forks, grab or BT) on the phone. You record **what it cost** on **CTP Pulse** — parts, invoices, labour, and other spend. Mechanics never see amounts; only you and admins do.

There is **no Costs or Reports screen** on the phone. Open **CTP Pulse → Fleet → Costing** (and **Reports** for exports).

| Pulse page | What it is |
|------------|------------|
| **Costing** | Queue of mechanic jobs — enter spend against each job |
| **Reports** | Totals, spend per machine, and export for accounts |
| **Operations** | Open issues (read-only for cost managers) |

You need the **fleet** board module on Pulse plus your clock on the cost-manager list.

---

## The two ways to add a cost

### 1. Cost against a mechanic job (most common)

Use when the spend relates to work the mechanic logged.

1. Open **CTP Pulse → Fleet → Costing**
2. Find the job (newest first). Open jobs are read-only for work text; cost lines are editable.
3. Jobs still needing money are your work queue — open the job
4. Fill in what was purchased, amount (R), category, invoice details
5. Save the cost line

You can add **more cost lines** later on the same job.

**Entering a cost (or marking no cost) locks the job for the mechanic** — they can no longer edit what they wrote. They can still add comments.

Costs are **optional** — there is no “uncosted” attention badge. Work the queue when invoices arrive.

### Jobs with no spend — "No cost needed"

Some jobs cost nothing (an adjustment, an inspection). Open the job and mark **No cost needed**. This also locks the job for the mechanic.

### 2. General cost (not tied to a job)

Use for spend on a machine that is **not** linked to one mechanic job — e.g. annual contract, delivery fee.

1. On Costing, open **General cost** (or `/fleet/costs/new`)
2. Pick the machine, category, description, and amount
3. Leave the mechanic-job link empty unless you want to attach one
4. Save

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
| Link to mechanic's job | No | Pre-filled when you open a job from Costing |
| What type of cost? | Yes | Parts / Labour / Invoice / Other |
| What was purchased / paid for? | Yes | Short description for reports |
| Amount (Rands) | Yes | VAT-inclusive amount you want recorded |
| Invoice number | No | Helps matching to supplier paperwork |
| Supplier | No | Who you paid |
| Invoice / payment date | Yes | Date on the invoice or when paid |

---

## Reports

Use **Pulse → Fleet → Reports** to review spend and export CSV (date, machine, job number if linked, category, description, amount, invoice, supplier, who entered).

---

## How jobs and costs stay in sync

```
Mechanic logs job on the phone → appears on Pulse Costing
        ↓
You enter cost(s) linked to that job → job marked costed
        ↓
Costs appear in Reports for the invoice/payment month
```

- A job can have **multiple cost lines**.
- **General costs** without a job link still appear in Reports under the machine.

---

## Quick reference

| I want to… | Do this |
|------------|---------|
| Enter costs for a repair | Pulse **Costing** → open job → save cost line |
| Enter spend not tied to one job | **General cost** |
| Job had no spend | Open job → **No cost needed** |
| Review monthly spend | Pulse **Reports** |
| Export for accounts | **Reports** → **Export CSV** |

---

## Need access?

If you cannot open Fleet on Pulse, ask an admin to grant **board module: fleet** and add your **clock number** under **Fleet Settings → Cost manager clock numbers**.
