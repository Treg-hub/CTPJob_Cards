# CTP Fleet Maintenance — Mechanic Guide

*A plain-language guide for Hyster mechanics using the CTP Job Cards app*

---

## What you use this for

Fleet Maintenance tracks problems on **Hyster machines (forks or grab attachments)** — who reported them, what you did to fix them, and when. You do **not** enter costs; a manager handles that later.

Your main tabs:

| Tab | What it is |
|-----|------------|
| **To Fix** | Problems waiting for you (needs fixing / in progress) |
| **History** | Jobs you have already logged |

---

## The three problem statuses

| Status | Meaning |
|--------|---------|
| **Needs fixing** | New report — nobody has started work yet |
| **In progress** | You tapped **Start job** — the clock is running |
| **Fixed** | Work is logged and the problem is closed |

Use the filter chips at the top of **To Fix** to switch between these lists.

---

## Fixing a reported problem (most common)

### Quick job (same visit) — e.g. check brakes, tighten chain

1. Open **Fleet** → **To Fix**
2. Tap the problem
3. Tap **Start job** (moves it to *In progress*)
4. Tap **Finish the fix**
5. Fill in:
   - **Hour-meter reading** (required) — number on the hour meter on the machine
   - **What you did** — short title and description
   - **Labour hours** — optional
   - **Parts** and **photos** — optional
6. Tap **Mark as Fixed**

Done. The problem disappears from **To Fix** and the job appears in **History**.

### Long job (several days) — e.g. replace transmission

1. **Day 1** — Open the problem → tap **Start job** only  
   - The job clock starts now  
   - You do **not** need to fill in the fix form yet  
   - The problem shows as **In progress** in **To Fix**

2. **While you work** — Leave it as *In progress*. Other people can see you are on it.

3. **Last day** — Open the same problem → tap **Finish the fix**  
   - Enter the hour-meter reading when the machine is ready  
   - Describe what was wrong and what you replaced/fixed  
   - Add **total labour hours** for the whole job (e.g. `16`) if you want  
   - Add parts used and photos if helpful  
   - Tap **Mark as Fixed**

**Start time** = when you tapped **Start job**  
**Finish time** = when you tapped **Mark as Fixed**

---

## Logging work that is not a reported problem

Use **Log other work** on the **History** tab for planned jobs with no fault report — e.g. scheduled service, transmission swap you planned yourself.

1. **History** → **Log other work**
2. **When did you start?** — tap to set the start date/time (defaults to now). For multi-day jobs, set the day you began.
3. Pick the Hyster, job type, title, and description
4. Enter hour-meter reading (required)
5. Add labour hours, parts, and photos if needed
6. Tap **Save job**

**Start time** = what you set above  
**Finish time** = when you tap **Save job**

This does not close a problem in **To Fix** — it only adds a record to **History**.

---

## Finding past jobs — History filters

On the **History** tab you can filter by:

- **Hyster** — show jobs for one machine only
- **Job type** — e.g. Repair, Routine, Inspection

Leave both on “All” to see everything.

Tap any job to see details: what you did, hour-meter reading, started/finished dates, and parts.

---

## Closing a problem without a work log

Sometimes a report is wrong (duplicate, not a real fault). On the problem screen, use **Close with a note only** and write a short explanation. No hour-meter or work record is needed.

> **Exception — Out of service problems:** if the machine was reported **out of service**, you must close it by logging the repair (**Finish the fix**). The note-only option is not available for these.

---

## What you never need to worry about

- **Costs / invoices** — managers enter these; you only see “costs pending” on a job
- **Work record numbers** — the system creates these automatically
- **Start/end date pickers** — start = **Start job**, finish = **Mark as Fixed**

---

## Out-of-service machines

When a problem is marked **Out of Service**, the Hyster cannot be used until it is fixed. These appear at the top of the list and may trigger notifications. Fix them the same way: **Start job** → **Finish the fix**.

When the last open out-of-service problem on a machine is fixed, the red warning clears automatically.

---

## Quick reference

| I want to… | Do this |
|------------|---------|
| Begin a repair | **Start job** |
| Complete a repair | **Finish the fix** → **Mark as Fixed** |
| See open problems | **To Fix** tab |
| See finished jobs | **History** tab |
| Filter by Hyster | **History** → Hyster dropdown |
| Log planned work (no fault) | **Log other work** |
| Dismiss a false alarm | **Close with a note only** (not available for out-of-service problems) |

---

## Need access?

If you do not see the **Fleet** tab or your jobs will not save, ask an admin to add your clock number under **Fleet Settings → Mechanic clock numbers**.