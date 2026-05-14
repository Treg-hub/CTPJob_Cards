# CTP Job Cards — Employee Guide

---

## Section 1: Onboarding & App Permissions

### Who Uses This App

There are four types of users in the CTP Job Cards system:

| Role | Primary Responsibility |
|------|----------------------|
| **Operator** | Reports faults and creates job cards when a machine or process has an issue |
| **Technician** | Receives job card notifications, attends to faults, and closes jobs when resolved |
| **Manager** | Oversees job cards in their department, monitors escalations, and ensures quality |
| **Admin** | Manages the system, employee accounts, and geofence configuration |

> **Note:** Operators and Technicians are separate roles. An operator is the person who discovers and reports the fault — a technician is the person who goes to fix it.

---

### Logging In

You log in using your **company email address** and **password** through the Firebase authentication system. Your email account is linked to your clock number behind the scenes, which determines what role you have, what department you belong to, and what you see in the app.

If you have forgotten your password, use the "Forgot Password" option on the login screen and a reset link will be sent to your email.

---

### Why You Need This App

**For Operators:** This app is how you formally report a fault or breakdown. Instead of verbally reporting to a supervisor or writing on a paper log, you create a job card directly. This means the fault is instantly in the system, visible to the right technicians, and tracked to resolution — nothing gets lost.

**For Technicians:** This app is how you receive and manage your work. When a fault is reported, you are notified immediately on your phone. You can accept the job, indicate you are unavailable, and record what you did to fix it — all from the app.

---

### First-Time Setup: Permissions Explained

When you open the app for the first time, it will ask for a number of permissions. Each one has a specific reason. **Do not skip or deny these — without them, the app cannot do its job and you will miss urgent alerts.**

---

#### 1. Location — "Allow All the Time"

**What the app asks:** *Allow CTP Job Cards to access your location all the time.*

**Why it needs this:**
The app uses your location to determine whether you are on site or off site. This matters for two reasons:

- **On-site status** — Your profile in the system is updated to show you are on site. Technicians who are on site receive job card notifications. If you are off site, the system knows not to send you alerts for jobs you cannot attend to.
- **Geofence detection** — The moment you enter or leave the company boundary (approximately 800 m radius), the system logs it automatically. You will receive a notification confirming "Arrived On-Site" or "Left Site Area."

**Location is not used for surveillance.** It is used solely to determine whether you are within the company boundary and should be receiving job alerts.

> Select **"Allow All the Time"** — if you choose "Only While Using the App" the geofence will not work when the app is in the background.

---

#### 2. Notifications — "Allow"

**What the app asks:** *Allow CTP Job Cards to send you notifications.*

**Why it needs this:**
Every job card assigned to you, every escalation, every urgent fault — all of it reaches you through notifications. Without this permission, you will receive nothing. You will be invisible to the system and jobs will escalate as if no one is responding.

> Always select **"Allow."**

---

#### 3. Battery Optimisation — "Don't Optimise" / "Unrestricted"

**What the app asks:** *Allow CTP Job Cards to run in the background without restrictions.*

**Why it needs this:**
Android phones, particularly newer models, aggressively shut down background apps to save battery. If the app is "optimised," your phone may kill it after a few minutes of not being used, meaning you will miss notifications entirely — especially overnight or during quiet periods.

Exempting the app from battery optimisation ensures it stays alive to receive messages even when your phone has been idle.

> Navigate to **Settings → Apps → CTP Job Cards → Battery → Unrestricted** (wording varies by phone brand).

---

#### 4. Display Over Other Apps / System Alert Window

**What the app asks:** *Allow CTP Job Cards to appear over other apps.*

**Why it needs this:**
Priority 5 (P5) faults are the most urgent jobs on site — production is standing and needs an immediate response. When a P5 job card arrives, the app needs to display a full-screen alert that interrupts whatever you are doing: even if your phone is locked, even if another app is open.

This permission allows that full-screen alarm to appear so you cannot miss a critical fault.

> Grant this permission. Without it, P5 alerts will fall back to a standard banner notification, which can be easily missed.

---

#### 5. Do Not Disturb Access

**What the app asks:** *Allow CTP Job Cards to override Do Not Disturb.*

**Why it needs this:**
If your phone is set to Do Not Disturb mode — common during night shifts or breaks — standard notifications are silenced. This permission allows P5 critical alerts to bypass Do Not Disturb so the alarm still sounds and the screen still lights up.

> Grant this permission for P5 fault coverage.

---

#### 6. Schedule Exact Alarms

**What the app asks:** *Allow CTP Job Cards to set exact alarms.*

**Why it needs this:**
The full-screen alarm for P5 faults uses the phone's alarm system — the same system that wakes you up in the morning — to guarantee the alert fires at the exact right moment, even if the phone is in deep sleep. Without this, the alarm may fire late or not at all.

> Grant this permission when prompted. On some phones it is found under **Settings → Apps → Special App Access → Alarms & Reminders.**

---

## Section 2: Flow of Job Cards

### What is a Job Card?

A job card is a formal digital record of a fault, breakdown, or maintenance task. It captures:

- **Department** — which department the job belongs to
- **Area** — the specific area within the plant
- **Machine** — the specific machine or asset
- **Part** — the component or part affected
- **Description** — a clear description of the fault or work required
- **Priority** — how urgent the job is (1–5)
- **Type** — Mechanical, Electrical, or Mech/Elec

---

### Priority Levels

| Priority | Impact on Production |
|----------|---------------------|
| **1** | No effect on production — routine or planned work |
| **2** | Minor impact — can continue but should be attended to soon |
| **3** | Moderate impact — attend within the shift |
| **4** | Significant impact — attend as soon as possible |
| **5** | Production is standing — immediate response required |

> Priority must reflect actual impact. A P5 means production has stopped. Use it only when that is true.

---

### Job Card Status

A job card moves through three statuses during its life:

| Status | Meaning |
|--------|---------|
| **Open** | Job has been created and is awaiting or in progress with a technician |
| **Monitor** | Fault has been resolved but the machine is being watched for recurrence |
| **Closed** | Job is complete — fault resolved and confirmed |

---

### For Operators: Creating a Job Card

When you discover a fault or breakdown, create a job card immediately. Do not wait.

**Steps:**
1. Open the CTP Job Cards app
2. Tap **Create Job Card**
3. Fill in all fields — department, area, machine, part, description, and priority
4. Submit

The job card is live the moment you submit it. The relevant technicians are notified on their phones immediately.

**Your responsibility as an operator is to fill in the form completely and accurately.** Vague or incomplete job cards slow down the technician and create useless records in the system. Be specific:

| Instead of... | Write... |
|---------------|---------|
| "Machine broken" | "Conveyor 3 drive motor tripping on overload — production line stopped" |
| "Pump issue" | "Cooling water pump P-02 not priming — no flow to chiller circuit" |
| "Fault on line" | "PLC fault code E-14 on Line 2 pressing machine — cycle will not complete" |

Once you have submitted the job card, you can track its status in the app. You will receive a notification when a technician accepts the job and again when it is closed.

---

### For Technicians: Receiving and Working a Job

#### Receiving a Notification

When a job card is created that matches your trade and you are on site, you will receive a push notification on your phone. The notification shows:
- Job number and priority
- Machine and area
- Description of the fault

You have three options directly from the notification:

| Action | What it does |
|--------|-------------|
| **Assign Self** | You take ownership of the job. The operator is notified you are attending. Escalation stops. |
| **I'm Busy** | You acknowledge the job but cannot take it right now. The operator is notified. Escalation stops. The system continues looking for another technician. |
| **Dismiss** | You dismiss the alert. The system logs this and escalation continues. |

> **Always respond to notifications.** If you do not respond, the system escalates the job to your foreman, then your manager. Repeated non-responses will be visible in the notification log.

---

#### Working the Job

Once you have accepted a job, navigate to **My Assigned Jobs** in the app to see the full details.

Update the job status as you progress:
- When you begin working: the job remains **Open**
- When you have resolved the fault but want to monitor: change to **Monitor**
- When the job is fully complete: change to **Closed**

---

#### Closing a Job

When you close a job, you must add a note. This is not optional — it is the maintenance record that managers, engineers, and future technicians will rely on.

Your closure note should include:
- What was done
- Any parts used (include part numbers or specifications where possible)
- Root cause if known
- Any follow-up work recommended

**A closed job with no note is a wasted record.**

When you close the job, the operator who created it is automatically notified.

---

### What Happens If Nobody Responds?

The system has automatic escalation. If a job sits open without a technician accepting it:

| Time After Creation | What Happens |
|--------------------|-------------|
| **2 minutes** | Foremen and on-site managers for the relevant department are notified |
| **7 minutes** | Department managers and the workshop manager are notified with an urgent alert |
| **30 minutes** | Further escalation as configured |

Escalation stops the moment any technician assigns themselves or responds "I'm Busy."

---

## Section 3: Notifications — Types and What They Mean

### Notification Levels

There are three levels of notification, determined by the priority of the job card:

---

#### Level 1 — Normal Banner (Priority 1, 2, 3)

**Appearance:** Standard Android notification banner at the top of the screen.

**Sound:** Default notification tone.

**Behaviour:** Appears and disappears like any other notification. Tap it to open the job.

**Used for:** Jobs that need attention but are not stopping production.

---

#### Level 2 — Persistent Banner (Priority 4)

**Appearance:** A notification that stays in your notification panel until you act on it. It cannot be accidentally swiped away.

**Sound:** Escalation alert tone with stronger vibration.

**Behaviour:** Remains visible in your notification shade. Action buttons appear directly on the notification: **Assign Self**, **Busy**, **Dismiss**.

**Used for:** Jobs with significant production impact needing prompt attention.

---

#### Level 3 — Full-Screen Alarm (Priority 5)

**Appearance:** A full-screen alert that takes over your entire phone screen, even from the lock screen.

**Sound:** Loud, repeating escalation alarm that continues until dismissed. Bypasses Do Not Disturb.

**Behaviour:** Cannot be ignored without deliberate action. Shows full job details and three buttons. Tapping any button logs your response and dismisses the alarm.

**Used for:** Production is standing. Immediate response required.

> If your phone does not have exact alarm permission granted, a P5 job will fall back to a persistent banner. This is why granting alarm permission during onboarding is critical.

---

### On-Site Arrival and Departure Notifications

When you cross the company boundary, you automatically receive:

- **"Arrived On-Site"** — your status is updated and you start receiving job notifications
- **"Left Site Area"** — your status is updated and job notifications pause until you return

No action is required — this is fully automatic.

---

## The Future: AI-Assisted Maintenance

### Predictive Maintenance

By analysing the history of job cards — which machines fail most often, at what intervals, and with what parts — the system will identify patterns and generate predictive alerts:

- "Machine X has had 4 bearing failures in 6 months. Inspection recommended within 3 weeks."
- "Fault frequency on Line 3 increases in summer. Pre-emptive service advised."

This shifts the team from always reacting to breakdowns to planning interventions during scheduled downtime.

---

### AI Chatbot — Operator Manuals and Fault Finding

A conversational AI assistant will be integrated into the app with access to:

- Operator and maintenance manuals for all plant equipment
- Historical fault and repair records from job cards
- Wiring diagrams, schematics, and parts lists

A technician on the floor will be able to ask:

> *"The conveyor on Line 2 is tripping on overload. What are the common causes?"*
> *"What is the torque spec for the main shaft bearing on the FX400 gearbox?"*
> *"What was done the last time this fault appeared on Machine 7?"*

The assistant responds with answers drawn from official documentation and real maintenance history — reducing time spent searching through manuals and helping with fault-finding guidance.

**Your job card entries today become the data that makes these AI tools accurate. Complete descriptions and clear closure notes are an investment in the system's future intelligence.**
