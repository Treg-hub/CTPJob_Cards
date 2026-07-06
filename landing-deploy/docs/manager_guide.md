# CTP Job Cards — Manager Guide

---

> **Security department managers:** You also run **Site Security** and **Waste Recovery** on mobile (gate scans, waste scheduling, company car costs) and the **CTP Pulse** security desk for gate-log history and reports. Start with **Site Security — Manager Guide** in Settings → Documentation; return here for job-card dashboard and escalation work in your department.

---

## Your Role in the System

As a manager, you are the quality gate for the job card system in your department. The system works well when the data going into it is accurate and complete. Your job is not just to review what is happening on the floor — it is to ensure that every job card created in your department meets the standard required to build a useful maintenance record over time.

A job card with vague information is almost useless for analysis, reporting, or AI-assisted predictive maintenance in the future. A job card with precise, complete information becomes a permanent record that helps the business make better decisions.

---

## Understanding the Four User Types

| Role | What They Do |
|------|-------------|
| **Operator** | Discovers a fault and creates the job card. Responsible for accurate, complete information at the point of entry. |
| **Technician** | Receives the job card, attends to the fault, and closes it out with a completion note. |
| **Manager** | Oversees all job cards in their department. Responsible for quality, escalation response, and pattern identification. |
| **Admin** | Manages system configuration, employee accounts, and geofence settings. |
| **Security Manager** | Keeps this manager job-card Home **plus** Waste and Security tabs; Pulse desk for security oversight (see Site Security — Manager Guide). |
| **Security Guard** | Does **not** use this guide for day-to-day work — module hub home only (Site Security — Guard Guide). |

> Operators and Technicians are distinct roles. An operator reports — a technician resolves. Ensuring operators understand the importance of complete job card entries is part of your responsibility as a manager.

---

## What the System Gives You

### Real-Time Visibility

Your **Manager Dashboard** gives you a live view of everything in your department. Use the **department** and **date range** filter chips at the top to scope the data to what you need.

#### KPI Cards

Nine KPI cards give you an at-a-glance picture:

| KPI | What It Shows |
|-----|---------------|
| Open Jobs | All currently open (non-closed) jobs |
| High Priority | Open P4 and P5 jobs |
| Monitoring | Jobs in Monitor status — resolved but being watched |
| Closed Today | Jobs closed today |
| Pending Assignment | Open jobs with no technician assigned yet |
| Avg Resolution | Average time from creation to close |
| Overdue >3d | Open jobs older than 3 days |
| Overdue >7d | Open jobs older than 7 days |
| Completion % | Percentage of jobs closed in the selected period |

**Tap any KPI card** (except Avg Resolution and Completion %) to open a filtered list of exactly those jobs and then drill into any individual job card.

#### Analytics Charts

Below the KPIs:
- **Open Jobs by Day** — 30-day area chart showing your open job stock over time (department-filtered; always shows the last 30 days regardless of the date range chip)
- **Trendline** — opened vs. closed jobs over the selected period
- **Priority Breakdown** — bar chart of open jobs by priority (P1 Low → P5 Crit)
- **Team Performance** — table listing each technician with their closed count, average resolution time, and number of currently assigned jobs. Sort order is by closed count. An assigned count above 3 is highlighted in orange as a workload warning.

> **Daily Review** — an additional **Daily Review** screen lets you scope the day's closed and monitored jobs by department or job type and add manager review notes inline. Use this for your morning review pass. The Home tile pulses red when your pending review queue exceeds 5 items. A job card is marked as reviewed the moment you open it, so the pending count decrements as you work through the list — you do not need to take any extra action to mark it.

### Notification History

Every notification sent by the system is logged. You can see:

- Who was notified, when, and at what level
- Who responded (assigned themselves, reported busy, dismissed)
- Which jobs escalated to you because no technician responded in time

### Notification Inbox — Off-Site Delivery

If you are **off-site** (your `isOnSite` status is false) when an escalation or job update arrives, the notification is not pushed to your phone. Instead it is held in your **Notification Inbox** and delivered when you return on-site.

- The **bell icon** in the Home screen app bar shows a live count of unread inbox items.
- When you arrive on site, a banner appears with the count and a shortcut to your inbox.
- Items persist until you mark them read — they do not expire.

This means a job may have escalated to you while you were off shift without you receiving a push alert. Review your inbox at the start of each shift.

### Escalation Notifications

When a P4 or P5 job has not been accepted within the escalation window, **you will receive a notification.** When this happens:

- A fault has been on the system for minutes with no technician response
- You need to act — find a technician, investigate the gap, or attend yourself
- This should be the exception, not the norm

---

## What Is Required From You

### 1. Daily Job Card Review

Review all job cards from your department from the previous day:

- Were all reported faults captured in the system?
- Were jobs responded to promptly and closed within a reasonable time?
- Are there recurring faults on the same machine?

> **Job History is now fully populated.** Closed job cards from April 2026 onwards have correct close dates, so the Job History screen and all dashboard metrics (Avg Resolution Time, Overdue counts, Completion %) reflect real data. Use the **Job History** quick-action tile on the Home screen to search and filter the full closed archive.

### 2. Enforce Job Card Quality — Operators

Operators are responsible for the quality of the job card at the point of creation. Your job is to ensure they meet the standard. Every job card must have:

| Field | What "Good" Looks Like | What to Reject / Send Back |
|-------|------------------------|---------------------------|
| **Department** | Correct department | Blank or wrong department |
| **Area** | Specific area within the plant | Blank or too vague ("production area") |
| **Machine** | Named machine or asset | "The conveyor", "a pump" — no identification |
| **Part** | Specific component affected | Blank, "unknown", or "various" |
| **Description** | Clear fault — what happened, what was observed | "Broken", "not working", "fault" with no detail |
| **Priority** | Accurate reflection of production impact | Blanket P1 to avoid pressure, or P5 to jump the queue |

**Priority must be honest.** A P5 means production is standing and stopped. If operators routinely mark jobs P5 when production is running, the escalation system loses credibility and technicians stop responding urgently. If they routinely mark everything P1 to avoid pressure, genuine issues get buried. Hold them to the correct standard.

---

### 3. Enforce Closure Note Quality — Technicians

When a technician closes a job, there must be a note. A job closed without a note is an incomplete record. The note must cover:

- **What was done** — the actual repair or action taken
- **Parts used** — including numbers or specifications where applicable
- **Root cause** — wear, contamination, operator error, incorrect adjustment, age?
- **Recommendations** — does this fault indicate a need for scheduled maintenance, parts stocking, or further investigation?

If you see closed jobs with no notes or inadequate notes, raise it with the technician directly. This is not a minor issue — it is a gap in the maintenance record.

---

### 4. Understand Job Card Status

Job cards move through four statuses:

| Status | Meaning | What You Should Watch |
|--------|---------|----------------------|
| **Open** | Job is live but no technician has accepted it yet | How long has it been open? Is it about to escalate? |
| **In-Progress** | A technician has self-assigned and is actively working the job | Who is on it? How long since they assigned themselves? |
| **Monitor** | Fault resolved but machine under observation | Who is monitoring and for how long? |
| **Closed** | Job complete and confirmed resolved | Does it have an adequate closure note? |

Jobs should not remain **Open** for more than a few minutes — if they do, escalation should already be firing. Jobs in **In-Progress** for an extended period should be reviewed to confirm the technician is still active on them. **Monitor** jobs older than 3 days should be reviewed to confirm they are still being actively watched.

---

### 5. Monitor Escalation Patterns

Escalation runs across **four configurable stages**, set by Admin under **Settings → Escalation Rules**. Each stage has its own timer, recipient list, and on/off switch. The defaults are:

| Stage | Default Time | Default State | Default Recipients |
|-------|-------------|---------------|-------------------|
| Stage 1 | 5 minutes | Enabled | On-site managers + department foremen |
| Stage 2 | 10 minutes | Enabled | On-site department managers + workshop manager (urgent) |
| Stage 3 | 30 minutes | Disabled | (Admin-configurable — typically senior management) |
| Stage 4 | 60 minutes | Disabled | (Admin-configurable — final escalation tier) |

If jobs in your department regularly hit Stage 2 or beyond, something is wrong:

- Technicians may not have their notifications set up correctly
- There may not be enough on-site technicians for the volume of work
- Technicians may be marking themselves on-site but not actually available
- The escalation timers may be too aggressive for your team's response capacity — speak to Admin if the defaults need adjustment

Review your escalation logs weekly. If the same technician repeatedly has jobs escalate without a response, investigate and address it.

---

### 6. Identify Repeat Failures

If the same machine appears in job cards more than twice in 30 days for similar faults, that is a pattern. You should:

1. Pull up the job card history for that machine
2. Review what was done each time — was the root cause actually resolved?
3. Determine whether an engineering review, scheduled overhaul, or replacement is needed
4. Escalate to the workshop manager or maintenance engineer if warranted

---

### 7. Verify On-Site Status Is Accurate

The system uses geofencing to determine who is on site. If a technician's phone has permissions incorrectly set, their on-site status may be wrong — meaning they may not receive job notifications even though they are physically present.

After new hires or phone upgrades, confirm your team has completed the onboarding setup and that their on-site status in the app reflects reality.

---

## Checklist — Weekly Manager Tasks

- [ ] Review all job cards created in the past 7 days
- [ ] Identify jobs with incomplete fields and follow up with the operator or technician
- [ ] Review closure notes — are they adequate?
- [ ] Review escalation log — are there patterns in who is not responding?
- [ ] Identify any machine with more than 2 similar job cards in the past 30 days
- [ ] Check that Monitor-status jobs older than 3 days are still being actively watched
- [ ] Confirm your team's on-site status is functioning correctly

---

## Checklist — What a Good Job Card Looks Like

Before approving a closed job, verify:

- [ ] Department is correct
- [ ] Area is specific and identifiable
- [ ] Machine is named (not described generically)
- [ ] Part is identified
- [ ] Description explains the fault clearly — what was observed, what stopped working
- [ ] Priority accurately reflects the production impact at the time of the fault
- [ ] Closure note describes what was done, parts used, and root cause
- [ ] Any recommendations for follow-up action are noted

---

## The Bigger Picture: Why Your Role Matters

The quality of this system is entirely dependent on the quality of the data entered into it. The system can only tell you what it has been told.

In the near future, AI tools will be added to identify patterns, predict failures, and guide technicians through fault-finding. Those tools will be trained on the job card history being built right now. If that history is vague, incomplete, or inconsistent, the AI tools will be limited in what they can deliver.

If the history is accurate and specific — the system will be able to tell you which machines are most likely to fail next month, what parts to have on hand, and what interventions have historically worked best.

**Your job today is to build that history by enforcing the standard.**
