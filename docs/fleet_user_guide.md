# CTP Fleet Maintenance — User Guide

*For Fleet Reporters and Hyster Mechanics on this phone. Cost managers use CTP Pulse.*

---

## What Is Fleet Maintenance?

Fleet Maintenance tracks upkeep of **fleet machines (forks, grab or BT)** — separate from plant job cards. Floor staff report faults and log repairs **on this phone**. **Costs and spend reports are on CTP Pulse only** — there is no Costs or Reports screen in the mobile app.

**Fault reports and fixes are kept separate.** A report can never be edited after it is submitted. The fix is a separate work record written by the mechanic, linked back to the report — so what was reported and what was done are always both visible, side by side.

This guide covers the four roles that operate Fleet Maintenance day-to-day:

| Role | Responsibilities |
|------|-----------------|
| **Fleet Reporter** | Report a problem on a machine (forks, grab or BT); track the issues you raised |
| **Hyster Mechanic** | Acknowledge issues, log the work done, resolve issues |
| **Cost Manager** | Enter spend and reports on **CTP Pulse** (not this phone) |
| **Fleet Admin** | Asset register and Fleet settings on **Pulse** |

> Mechanics and reporters use **this app**. Cost managers and admins use **CTP Pulse** (`/fleet`) for costing, the asset register, and settings. Cancelling false-alarm reports is also Pulse.

---

## Section 1: Accessing Fleet Maintenance

Open **Fleet** from a **Home tile** (not a bottom-nav tab). If you do not see it:

- The module may not be switched on. An admin enables Fleet in **Pulse → Fleet Settings**.
- Your account may not have a Fleet floor role (reporter department or Hyster Mechanic). Contact an admin.

What you see on the phone depends on role:

| View | Who sees it |
|------|-------------|
| **My reports / All open** | Reporters |
| **To Fix / In progress / History** | Hyster Mechanic |
| **Daily check** | Reporters (pre-use) |
| **Costs / Reports / Assets / Settings** | **Not on mobile** — CTP Pulse |

Hyster Mechanics may open straight into Fleet after login. Admins keep the normal Home (they are not auto-pushed into Fleet).

---

## Section 2: For Fleet Reporters — Reporting a Problem

When a machine (forks, grab or BT) develops a fault:

1. On the Fleet home screen, tap **Report a Problem**.
2. **Pick the asset** — choose the machine from the register.
3. **Choose the severity:**
   - **Low** — minor, non-urgent
   - **Medium** — needs attention soon
   - **High** — serious, prioritise
   - **Out of Service** — the machine cannot be used
4. **Confirm the shift** — auto-detected from the current time; change it if needed.
5. **Describe the fault** — be specific about what is wrong.
6. **Attach photos** — up to 3 photos to show the problem.
7. Tap **Submit**.

### What happens after you report

- The issue appears in the **Issues** list, sorted by severity.
- If you reported it as **Out of Service**, the Hyster mechanic and the cost manager(s) get an immediate push notification (or it waits in their Notification Inbox if they are off site). The asset shows an orange **OOS** badge everywhere it appears in the app.
- **High-severity** issues are sent to the mechanic's Notification Inbox without a push.
- You can track your own reported issues from the Issues list. Each issue
  shows a progress timeline (**Reported → Started → Fixed**) and, once
  fixed, **The fix** — the mechanic's own description of the work done.
- Your report cannot be edited by anyone after submission.

---

## Section 3: For Hyster Mechanics — Working an Issue

The mechanic sees open issues under **To Fix**, sorted with Out of Service first.

### Step 1: Acknowledge

Open an issue and tap **Acknowledge** to signal you have seen it and are taking it on. This lets reporters and managers know the issue is being handled.

### Step 2: Resolve the issue

You can close an issue in one of two ways:

**Option A — Log the work (recommended for real repairs)**

1. Tap **Finish the fix**. The original fault report is shown read-only at
   the top of the form — it cannot be changed.
2. Select the **work type**.
3. Describe **what you did to fix it** — your own words, separate from the report.
4. Enter **labour hours** and the current **machine-hour reading**.
5. Add **parts used** — for each part: description and quantity.
6. Attach **photos** of the completed work.
7. If this job also fixes **other reported problems** on the same machine,
   tick them under **Also fixes…** — they close together.
8. Tap **Mark as Fixed**. The work record gets a number like **FM-20260604-001**.

> **Editing window:** a work record can be edited for **7 days** after it is created (and only until costs are entered). After that use the comments section for corrections.

**Option B — Quick resolution note**

For an issue that needs no formal work record (e.g. a false alarm or a trivial fix), tap **Resolve** and enter a short note.

> **Out-of-service issues are the exception:** they can only be closed by logging the repair as a work record — a note alone is not accepted.

> **You never see costs.** Work records you create show only a "Costs pending / Costs entered" label — the actual money is entered and seen only by the cost manager.

> **Editing.** A work record can be edited for **7 days** after it is saved, and locks immediately once the cost manager enters costs (or marks it "No cost needed"). After that, corrections go in as comments.

When the last open Out-of-Service issue on a machine is resolved, the orange **OOS** badge is automatically cleared from that asset.

---

## Section 4: For Cost Managers — Recording Costs (CTP Pulse)

Cost managers do **not** enter money in this mobile app. Open **CTP Pulse → Fleet → Costing**.

1. Work the job queue (description, parts, photos).
2. Add cost lines (parts, labour, invoice, other) or mark **No cost needed**.
3. Use **General cost** for spend not tied to one mechanic job.
4. Reports and CSV export are on Pulse **Reports**.

See **Fleet Cost Manager Guide** in Documentation (same phone, if you have a cost-manager clock) or the Pulse Fleet guides.

---

## Section 5: For Admins — Fleet Settings

Everything that configures the module lives in **CTP Pulse → Fleet Settings** (Admin only):

- **Asset register** — add and edit the fleet machines (forks, grab or BT) (name, type, identifier).
- **Reporter departments** — which departments are allowed to report issues.
- **Cost-manager clock numbers** — who can enter and view costs.
- **Asset & work types** — the pick-lists used elsewhere in the module.
- **Enable Fleet** — the master on/off switch for the whole module.

Until Fleet is enabled and reporter departments plus the asset register are configured, the Home **Fleet** tile stays hidden for floor users.

---

## Section 6: Issue Severities & the OOS Badge

| Severity | Meaning | What it triggers |
|----------|---------|------------------|
| **Low** | Minor, non-urgent | Listed in Issues; no alert |
| **Medium** | Needs attention soon | Listed in Issues; no push |
| **High** | Serious | Goes to the mechanic's Notification Inbox |
| **Out of Service** | Machine cannot be used | Immediate push to mechanic + cost managers; orange **OOS** badge on the asset |

The **OOS** badge stays on a machine until every open Out-of-Service issue against it is resolved or cancelled.

---

## Section 7: Notification Inbox

If you are **off site** when a Fleet notification is generated, it is held in your **Notification Inbox** (bell icon in the top bar) instead of being sent as a push alert. When you arrive on site and open the app, a banner tells you how many notifications are waiting. Tap any item to open the related issue.

---

## Section 8: Troubleshooting

**I cannot see the Fleet tile on Home.**
Either the module is not enabled yet (an admin must turn it on in Pulse Fleet Settings) or your account does not have a Fleet floor role. Contact an admin.

**I reported an Out-of-Service issue but no one was notified.**
The mechanic and cost managers receive a push only when they are on site; otherwise the alert waits in their Notification Inbox. Confirm the cost-manager clock numbers and the mechanic are correctly configured in Fleet Settings.

**The asset I need to report on is not in the list.**
The asset register is managed by an admin in Fleet Settings → Asset register. Ask an admin to add the machine.

**I'm the mechanic but I can't see costs.**
This is by design. Mechanics never see cost amounts — only a "Costs pending / Costs entered" label. Cost figures are visible only to cost managers and admins.

**The OOS badge is still showing after I fixed the machine.**
The badge clears only when *every* open Out-of-Service issue on that asset is resolved or cancelled. Check the Issues list for any other open OOS issues on the same machine.

---

*CTP Fleet Maintenance · Forks, Grab & BT Upkeep Guide*
