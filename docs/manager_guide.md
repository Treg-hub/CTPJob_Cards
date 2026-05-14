# CTP Job Cards — Manager Guide

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

> Operators and Technicians are distinct roles. An operator reports — a technician resolves. Ensuring operators understand the importance of complete job card entries is part of your responsibility as a manager.

---

## What the System Gives You

### Real-Time Visibility

Your **Manager Dashboard** gives you a live view of:

- All open, monitoring, and recently closed job cards in your department
- Which technicians are currently on site and which are off site
- Jobs that have escalated and why
- Jobs that have been open for too long without progress

### Notification History

Every notification sent by the system is logged. You can see:

- Who was notified, when, and at what level
- Who responded (assigned themselves, reported busy, dismissed)
- Which jobs escalated to you because no technician responded in time

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

Job cards move through three statuses:

| Status | Meaning | What You Should Watch |
|--------|---------|----------------------|
| **Open** | Job is live — technician assigned or pending | How long has it been open? Who is on it? |
| **Monitor** | Fault resolved but machine under observation | Who is monitoring and for how long? |
| **Closed** | Job complete and confirmed resolved | Does it have an adequate closure note? |

Jobs should not remain Open indefinitely without progress. Monitor jobs older than 3 days should be reviewed to confirm they are still being actively watched.

---

### 5. Monitor Escalation Patterns

If jobs in your department regularly escalate past 2 or 7 minutes, something is wrong:

- Technicians may not have their notifications set up correctly
- There may not be enough on-site technicians for the volume of work
- Technicians may be marking themselves on-site but not actually available

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
