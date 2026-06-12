# CTP Fleet Maintenance — Mechanic Guide

*A plain-language guide for Hyster mechanics using the CTP Job Cards app*

---

## What you use this for

Fleet Maintenance tracks problems on **fleet machines (forks, grab or BT)** — who reported them, what you did to fix them, and when. You do **not** enter costs; a manager handles that later.

**The report and the fix are separate.** The reporter's fault report can never be changed — when you fix a problem, the report is shown read-only at the top of the form and you describe **your own work** underneath it.

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
5. The original fault report is shown at the top — you cannot change it. Fill in:
   - **Hour-meter reading** (required) — number on the hour meter on the machine
   - **What you did to fix it** — describe **your** work, not the fault
   - **Labour hours** — optional
   - **Parts** and **photos** — optional
   - **Also fixes…** — if other reported problems on the same machine were
     fixed by this job, tick them and they close too
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
3. Pick the machine, job type, title, and description
   - If the machine has open reported problems that this job fixes, tick
     them under **Does this job fix any reported problems?** — they close
     when you save
4. Enter hour-meter reading (required)
5. Add labour hours, parts, and photos if needed
6. Tap **Save job**

**Start time** = what you set above  
**Finish time** = when you tap **Save job**

This does not close a problem in **To Fix** — it only adds a record to **History**.

---

## Finding past jobs — History filters

On the **History** tab you can filter by:

- **Machine** — show jobs for one machine only
- **Job type** — e.g. Repair, Routine, Inspection

Leave both on “All” to see everything.

Tap any job to see details: what you did, hour-meter reading, started/finished dates, and parts.

---

## Fixing a mistake in a saved job

You can **edit a job for 7 days** after saving it (tap the job in **History** → **Edit this job**). After 7 days — or as soon as a manager enters costs against it — the job is **locked** and shows a lock note instead of the edit button.

To correct a locked job, **add a comment** on the job explaining the correction. Comments are always open.

---

## Closing a problem without a work log

Sometimes a report is wrong (duplicate, not a real fault). On the problem screen, use **Close with a note only** and write a short explanation. No hour-meter or work record is needed.

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
| Filter by machine | **History** → Machine dropdown |
| Log planned work (no fault) | **Log other work** |
| Close several reports with one job | Tick them under **Also fixes…** |
| Fix a typo in a saved job | Edit within 7 days, comment after that |
| Dismiss a false alarm | **Close with a note only** |

---

## Need access?

If you do not see the **Fleet** tab or your jobs will not save, ask an admin to add your clock number under **Fleet Settings → Mechanic clock numbers**.