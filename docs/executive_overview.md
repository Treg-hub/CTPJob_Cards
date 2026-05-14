# CTP Job Cards — Executive Overview

---

## What the System Is

The CTP Job Cards platform is a real-time digital maintenance management system built for the plant. It replaces paper-based, radio, and verbal fault-reporting processes with a structured, tracked, and auditable system accessible from every employee's mobile phone.

The platform is built on Google Firebase — enterprise-grade cloud infrastructure — and is designed to be always available, offline-capable, and scalable without requiring any on-site IT infrastructure.

---

## The Problem It Solves

In a traditional plant environment, fault reporting and maintenance response suffer from well-known problems:

- **No formal record** — faults reported verbally or on paper are frequently lost, incomplete, or undiscoverable after the event
- **No accountability** — there is no reliable way to know when a fault was reported, when it was attended to, or how long it took to resolve
- **No real-time visibility** — managers are often the last to know about active faults or unresolved jobs
- **No pattern recognition** — without structured records, it is impossible to identify which machines fail most often, at what cost, or why
- **Slow response** — critical faults rely on physically finding a technician or making a radio call, which introduces dangerous delays

The CTP Job Cards system addresses all of these by digitising the entire process — from fault report to job closure — with automated notifications, escalation, and a permanent audit trail.

---

## The Four User Types

| Role | Primary Function |
|------|----------------|
| **Operator** | Discovers a fault and creates a job card. The first link in the chain — quality of entry determines quality of the record. |
| **Technician** | Receives the job notification, attends to the fault, records what was done, and closes the job. |
| **Manager** | Oversees all jobs in their department, enforces data quality, monitors escalations, and identifies recurring failure patterns. |
| **Admin** | Manages system configuration, employee accounts, geofence settings, and access control. |

---

## How the System Works — High Level

### 1. Fault Reported

An **operator** identifies a fault and creates a job card on their phone. They record the machine, area, component, fault description, and priority (1 to 5, where 1 has no production impact and 5 means production is standing).

The job card is live the moment it is submitted.

### 2. Relevant Technicians Notified Instantly

The system automatically identifies which **technicians** are on site (via real-time geofencing) and what their trade is (mechanical, electrical, or both). The appropriate on-site technicians receive push notifications on their phones immediately — no dispatcher, no radio call.

Notification urgency scales with priority:
- **Priority 1–3:** Standard notification banner
- **Priority 4:** Persistent banner with action buttons that stays visible until responded to
- **Priority 5:** Full-screen alarm that overrides the lock screen and Do Not Disturb — cannot be passively ignored

### 3. Technician Accepts or Responds

The technician receives the alert and can assign themselves to the job, report themselves as busy, or dismiss it — directly from the notification. Every response is logged with a timestamp.

### 4. Automatic Escalation

If no technician responds within **2 minutes**, foremen and operational managers are automatically notified. If still unresolved after **7 minutes**, department managers and the workshop manager receive an urgent alert. No critical fault can be silently ignored.

### 5. Job Tracked to Closure

The technician works the job and updates its status (Open → Monitor → Closed). When complete, they record what was done. The operator who raised the job is notified of the closure. The full record is stored permanently.

### 6. Management Oversight

Managers have a dedicated dashboard with live visibility of all department jobs, technician on-site status, escalation history, and notification logs. They are responsible for policing job card quality — ensuring all entries are complete and accurate.

---

## Job Card Status Flow

```
Created  →  Open  →  Monitor  →  Closed
                 ↘              ↗
                   (direct close)
```

| Status | Meaning |
|--------|---------|
| **Open** | Job is active — pending or being worked |
| **Monitor** | Fault resolved, machine under observation |
| **Closed** | Job complete and confirmed resolved |

---

## What the System Captures

Every job card creates a permanent, searchable record:

| Data Point | Business Value |
|------------|---------------|
| Machine, area, part | Asset identification for tracking |
| Fault description | What happened and why |
| Priority at time of report | Urgency and production impact |
| Who created it, when | Operator accountability and fault timestamp |
| Who responded, when | Technician accountability and response time |
| What was done | Repair record and parts used |
| Time from report to closure | Mean time to repair (MTTR) |
| Full notification history | Who was notified, when, and what they did |

---

## Geofencing and On-Site Tracking

The system uses geofencing technology to automatically determine whether each employee is within the site boundary:

1. **Smart notification routing** — only on-site technicians receive job alerts, preventing off-hours disturbance for faults they cannot attend
2. **Site attendance records** — every entry and exit is logged with GPS coordinates and timestamp

Geofence events are triggered in real time using native Android location services, with a 30-minute background check for devices that may have missed an event.

---

## Security and Access Control

The system uses **Firebase Authentication** — users log in with their company email and password, linked to their clock number. Three access levels exist:

| Role | Access Scope |
|------|-------------|
| Operator / Technician | Own jobs, relevant department notifications |
| Manager | Full department visibility, escalation logs, notification history |
| Admin | Full system — employee management, geofence configuration, all data |

All data is encrypted at rest and in transit. No employee can access data outside their authorised scope.

---

## Infrastructure and Cost Model

| Component | Provider | Notes |
|-----------|----------|-------|
| Database | Google Firebase Firestore | Real-time, offline-capable, serverless |
| Push Notifications | Firebase Cloud Messaging | Enterprise-grade, free tier supports high volumes |
| Cloud Functions | Google Cloud Functions | Serverless — no server to maintain |
| Authentication | Firebase Auth | Email + password, linked to clock numbers |
| Mobile App | Android (primary) | iOS and web capable |

There is no server to maintain, no on-site hardware to manage, and no single point of failure. The system scales automatically.

---

## Current Capabilities

| Capability | Status |
|------------|--------|
| Real-time job card creation and tracking | Live |
| Push notifications scaled by priority (P1–P5) | Live |
| Full-screen critical alarms (P5) | Live |
| Automatic escalation (2-min, 7-min, 30-min) | Live |
| Real-time geofencing and on-site status | Live |
| Background location check (30-min fallback) | Live |
| Permanent audit trail for every action | Live |
| Notification history log | Live |
| Manager dashboard | Live |
| Offline support with automatic sync | Live |
| Role-based access control | Live |
| Notification action buttons (Assign / Busy / Dismiss) | Live |
| Copper inventory tracking | Live |

---

## The Road Ahead: AI and Predictive Maintenance

The current platform is a foundation. Its long-term value lies in what the structured, standardised data it collects makes possible.

---

### Phase 1 — Predictive Maintenance Analytics

Every job card completed today becomes a data point in a growing maintenance history. Machine learning models applied to this history will identify:

- **Failure patterns** — which machines fail most often, at what intervals, and under what conditions
- **Early warning signals** — combinations of faults that historically precede major failures
- **Predictive alerts** — "Machine X is due for a bearing failure based on 18 months of history — schedule inspection in the next 2 weeks"
- **Cost visibility** — which assets cost the most in repair time and parts, informing replacement or overhaul decisions

This shifts the maintenance function from **reactive** (fixing what breaks) to **predictive** (preventing it from breaking), directly reducing unplanned downtime and its associated production cost.

---

### Phase 2 — AI Assistant for Technicians and Operators

A conversational AI assistant will be integrated into the app with access to:

- All operator and maintenance manuals for plant equipment
- Historical fault and repair records from job cards
- Wiring diagrams, parts lists, and technical schematics

A technician on the floor will be able to ask:

> *"What are the most common causes of overload faults on this conveyor?"*
> *"What was done the last three times this machine had a similar fault?"*
> *"What is the correct torque for the coupling on this gearbox?"*

The assistant responds instantly with answers drawn from official documentation and real maintenance history — reducing diagnostic time and reducing dependency on senior staff for routine knowledge retrieval.

---

### Business Case for AI Integration

| Benefit | Mechanism |
|---------|-----------|
| Reduced unplanned downtime | Predictive alerts trigger maintenance before failure |
| Faster fault resolution | AI-assisted diagnosis reduces time to identify root cause |
| Knowledge retention | Institutional knowledge captured in the system — not lost when experienced staff leave |
| Lower parts inventory cost | Predictive maintenance enables targeted stocking |
| Reduced repeat failures | Root cause captured and addressed, not just symptoms |
| Operator and technician upskilling | Access to manuals and history in seconds, on the phone |

---

### What Makes This Possible

The accuracy of AI-driven insights depends entirely on the quality of the data feeding them. Every job card completed with accurate machine identification, clear fault descriptions, and detailed closure notes becomes a data point that improves predictive accuracy.

This is why **data quality enforcement at the manager level is not an administrative task — it is a direct investment in the long-term intelligence of the maintenance operation.**

The structure being built today determines what the system can deliver in two years.

---

## Summary

The CTP Job Cards system provides the business with:

1. **Speed** — critical faults reach the right technician in seconds, with automatic escalation to management if not responded to
2. **Accountability** — every fault is recorded, every response is timestamped, every action is logged
3. **Visibility** — management sees everything in real time without needing to chase information
4. **Compliance** — a complete, permanent audit trail for every maintenance event
5. **Intelligence** — a growing data asset that will power predictive maintenance and AI-assisted operations

The return on investment is measured in reduced unplanned downtime, lower mean-time-to-repair, and the progressive shift from emergency maintenance to planned, predictive maintenance — all of which translate directly to production output and cost efficiency.
