# CTP Fleet Maintenance — Mechanic Guide

*A plain-language guide for Hyster mechanics using the CTP Job Cards app*

---

## What you use this for

Fleet Maintenance tracks problems on **fleet machines (forks, grab or BT)** — who reported them, what you did to fix them, and when. You do **not** enter costs; a manager handles that later.

**The report and the fix are separate.** The reporter's fault report can never be changed — when you fix a problem, the report is shown read-only at the top of the form and you describe **your own work** underneath it.

Your main tabs:

| Tab | What it is |
|-----|------------|
| **To Fix** | Open problems waiting for you (not yet started) |
| **In progress** | Problems you have already opened — tap to **finish the repair** |
| **History** | All work records you have logged |

**Service due** machines appear at the top with a **Log service** button — use this for scheduled maintenance.

---

## The problem statuses

| Status | Meaning |
|--------|---------|
| **Needs fixing** | New report — not yet opened by a mechanic. Shows in **To Fix**. |
| **In progress** | You opened the problem — it is logged as seen. Shows in **In progress**. |
| **Fixed** | Work is logged and the problem is closed. |

---

## Fixing a reported problem (most common)

### Quick job (same visit)

1. Open **Fleet** → **To Fix**
2. Tap the problem — the **Mark as Fixed** form opens and the problem is automatically logged as *In progress*
3. The original fault report is shown at the top — read-only. Fill in the two required fields:
   - **What you did to fix it**
   - **Hour-meter reading**
4. Tap **Mark as Fixed**

Optional extras (labour hours, parts, photos, work date, closing other faults on the same machine) are under **More details** if you need them.

Done. The problem disappears from **To Fix** / **In progress** and the job appears in **History**.

---

### Long job (several days) — e.g. replace transmission

1. **Day 1** — Tap the problem in **To Fix**  
   - The fix form opens and the problem is automatically logged as *In progress*  
   - Close the form without saving — you are not done yet  
   - The problem moves to the **In progress** tab

2. **While you work** — The problem stays in **In progress**. Other people can see it is being worked on.

3. **Last day** — Open the **In progress** tab → tap the same problem → fill in the fix form:
   - Set **Work carried out** to the day you started (tap the date to change it)
   - Enter the hour-meter reading, description, parts, and photos
   - Tap **Mark as Fixed**

**Work date** = when the work was carried out (editable)  
**Saved at** = when you tapped **Mark as Fixed**

---

## Logging work that is not a reported problem

Use **Log other work** for planned jobs with no fault report — e.g. scheduled service, overhaul you planned yourself.

1. **History** → **Log other work**
2. Tap the **Work carried out** date to set when the job was done (defaults to now). For multi-day jobs, set the day you started.
3. Pick the machine, job type, title, and description
   - If the machine has open reported problems that this job fixes, tick them under **Does this job fix any reported problems?** — they close when you save
4. Enter hour-meter reading (required)
5. Add labour hours, parts, and photos if needed
6. Tap **Save job**

---

## Finding past jobs — History filters

On the **History** tab you can filter by:

- **Machine** — show jobs for one machine only
- **Job type** — e.g. Repair, Routine, Inspection

Leave both on "All" to see everything.

Tap any job to see details: what you did, hour-meter reading, work date, and parts.

---

## Fixing a mistake in a saved job

You can **edit a job for 7 days** after saving it (tap the job in **History** → **Edit this job**). After 7 days — or as soon as a manager enters costs against it — the job is **locked** and shows a lock note instead of the edit button.

To correct a locked job, **add a comment** on the job explaining the correction. Comments are always open.

---

## Out-of-service machines

When a problem is marked **Out of Service**, the machine cannot be used until it is fixed. These appear at the top of the list and may trigger notifications. Fix them the same way: tap the problem → fill in the fix form → **Mark as Fixed**.

When the last open out-of-service problem on a machine is fixed, the red warning clears automatically.

---

## What you never need to worry about

- **Costs / invoices** — managers enter these; you only see "costs pending" on a job
- **Work record numbers** — the system creates these automatically
- **"Close with a note only"** — if a report is a false alarm, ask an admin or manager to cancel it. Admins handle cancellations and Fleet settings in **Pulse** (the web admin app), not in this mobile app.

---

## Quick reference

| I want to… | Do this |
|------------|---------|
| Start on a problem | Tap it in **To Fix** — it is logged as started automatically |
| Complete a repair | Open **In progress** → tap the problem → fill in fix form → **Mark as Fixed** |
| See open problems | **To Fix** tab |
| See in-progress jobs | **In progress** tab |
| See finished jobs | **History** tab |
| Log planned work (no fault) | **History** → **Log other work** |
| Close several reports with one job | Tick them under **Also fixes…** |
| Fix a typo in a saved job | Edit within 7 days, add a comment after that |

---

## Need access?

If you do not see the **Fleet** tab or your jobs will not save, ask an admin to check your account is set up as a Hyster mechanic.
