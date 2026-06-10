# CTP Fleet Maintenance — User Guide

*For Fleet Reporters, Hyster Mechanics, and Cost Managers*

---

## What Is Fleet Maintenance?

Fleet Maintenance is the module in the CTP Job Cards app used to track the upkeep of the **Hyster machines (forks or grab attachments)** — separate from normal production job cards. It records faults reported on each machine, the work the mechanic does to fix them, and the costs the manager records against each asset.

This guide covers the four roles that operate Fleet Maintenance day-to-day:

| Role | Responsibilities |
|------|-----------------|
| **Fleet Reporter** | Report a problem on a Hyster (forks or grab); track the issues you raised |
| **Hyster Mechanic** | Acknowledge issues, log the work done, resolve issues |
| **Cost Manager** | Record costs per asset, view spend reports, export CSV |
| **Fleet Admin** | Manage the asset register and all Fleet settings |

> **Admin** users have full access to every Fleet screen plus the Fleet Settings configuration panel.

---

## Section 1: Accessing Fleet Maintenance

Fleet Maintenance is reached from the **Fleet** tab in the app. If you do not see the Fleet tab:

- The module may not be switched on yet. An admin enables it in **Fleet Settings → Enable Fleet**.
- Your account may not have a Fleet role. Fleet roles are based on your department, position, or clock number — contact an admin to be added.

The Fleet home screen is organised into role-based tabs. You will only see the tabs your role allows:

| Tab | Who sees it |
|-----|-------------|
| **Issues** | Everyone with Fleet access |
| **Work** | Mechanic + Admin |
| **Costs** | Cost Manager + Admin |
| **Reports** | Cost Manager + Admin |
| **Assets** | Admin |
| **Settings** | Admin |

The **Issues** tab shows a live count badge of currently open issues.

---

## Section 2: For Fleet Reporters — Reporting a Problem

When a Hyster (forks or grab) develops a fault:

1. On the Fleet home screen, tap **Report a Problem**.
2. **Pick the asset** — choose the Hyster (forks or grab) from the register.
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
- You can track your own reported issues from the Issues list.

---

## Section 3: For Hyster Mechanics — Working an Issue

The mechanic sees all open issues in the **Issues** tab, sorted by severity (Out of Service first).

### Step 1: Acknowledge

Open an issue and tap **Acknowledge** to signal you have seen it and are taking it on. This lets reporters and managers know the issue is being handled.

### Step 2: Resolve the issue

You can close an issue in one of two ways:

**Option A — Log the work (recommended for real repairs)**

1. Tap **Log Work**.
2. Select the **work type**.
3. Enter **labour hours**.
4. Enter the current **machine-hour reading** from the machine's hour meter.
5. Add **parts used** — for each part: description, quantity, and (optionally) a part number.
6. Attach **photos** of the completed work.
7. Tap **Save**. The work record gets a short number like **FM-0001**.

> **Editing window:** a work record can be edited for **14 days** after it is created (and only until costs are entered). After that it is locked for record-keeping.

**Option B — Quick resolution note**

For an issue that needs no formal work record (e.g. a false alarm or a trivial fix), tap **Resolve** and enter a short note.

> **Out-of-service issues are the exception:** they can only be closed by logging the repair as a work record — a note alone is not accepted.

> **You never see costs.** Work records you create show only a "Costs pending / Costs entered" label — the actual money is entered and seen only by the cost manager.

When the last open Out-of-Service issue on a machine is resolved, the orange **OOS** badge is automatically cleared from that asset.

---

## Section 4: For Cost Managers — Recording Costs

The **Costs** tab is where the overseeing manager records what was spent on each machine.

### Adding a cost line

1. Open the **Costs** tab and tap **Add Cost**.
2. **Pick the asset.**
3. Choose the **cost type** — parts, labour, invoice, or other.
4. Enter the **amount**.
5. Add an **invoice reference** and **supplier** if applicable.
6. Tap **Save**.

### Viewing reports

The **Reports** tab shows:

- **Month-to-date** and **year-to-date** spend per machine.
- A breakdown of cost by category per asset.
- **Export CSV** — download the full cost data for the selected period for your own records or accounting.

---

## Section 5: For Admins — Fleet Settings

Everything that configures the module lives in **Fleet Settings** (Admin only):

- **Asset register** — add and edit the Hyster machines (forks or grab attachments) (name, type, identifier).
- **Reporter departments** — which departments are allowed to report issues.
- **Cost-manager clock numbers** — who can enter and view costs.
- **Asset & work types** — the pick-lists used elsewhere in the module.
- **Enable Fleet** — the master on/off switch for the whole module.

Until Fleet is enabled and at least the reporter departments and asset register are configured, the Fleet tab stays hidden for everyone except admins.

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

**I cannot see the Fleet tab.**
Either the module is not enabled yet (an admin must turn it on in Fleet Settings) or your account does not have a Fleet role. Contact an admin.

**I reported an Out-of-Service issue but no one was notified.**
The mechanic and cost managers receive a push only when they are on site; otherwise the alert waits in their Notification Inbox. Confirm the cost-manager clock numbers and the mechanic are correctly configured in Fleet Settings.

**The asset I need to report on is not in the list.**
The asset register is managed by an admin in Fleet Settings → Asset register. Ask an admin to add the machine.

**I'm the mechanic but I can't see costs.**
This is by design. Mechanics never see cost amounts — only a "Costs pending / Costs entered" label. Cost figures are visible only to cost managers and admins.

**The OOS badge is still showing after I fixed the machine.**
The badge clears only when *every* open Out-of-Service issue on that asset is resolved or cancelled. Check the Issues list for any other open OOS issues on the same machine.

---

*CTP Fleet Maintenance · Hyster — Forks & Grab Upkeep Guide*
