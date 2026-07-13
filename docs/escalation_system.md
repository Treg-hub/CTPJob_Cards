# How job-card escalation works

This guide explains **why you get alerts**, what happens if nobody takes a job, and how managers get pulled in. It is written for everyone who uses Job Cards — operators, technicians, and managers.

Nothing here is secret: knowing the rules builds trust that the system is fair and that open jobs do not sit unnoticed.

---

## The big picture

1. Someone creates a job card for a fault.
2. The right **on-site** technicians for that trade (mechanical / electrical / both) are notified straight away.
3. If nobody **assigns themselves** (or stops escalation another way) in time, the system **escalates** — it notifies a wider circle so the job is not forgotten.
4. Escalation stops as soon as someone owns the job (or marks Busy in a way that parks the chase).

There are **four stages**. Stages 1 and 2 are usually on; stages 3 and 4 are reserved for wider management and are often left off.

| Stage | Typical timing | Who it reaches (default idea) |
|-------|----------------|--------------------------------|
| Stage 1 | ~5 minutes after create | On-site managers and foremen / shift leaders for that work |
| Stage 2 | ~10 minutes after create | Department and workshop managers |
| Stage 3 | Often off | Wider / off-site managers (when enabled) |
| Stage 4 | Often off | Final escalation (when enabled) |

Exact minutes and who is on each stage are set by **Admin → Escalation** (or the Factory Admin hub). Timings can change without waiting for a new app version.

---

## What you will notice as a technician

- **Instant alert** when a matching open job is created and you are marked **on site**.
- From the alert you can usually **Assign self** (you take the job — escalation stops), **I'm Busy**, or dismiss (logged; escalation may continue depending on settings).
- If a job is still open later, you may see **escalation** alerts — that means the system is widening the circle so someone responds.
- **Maintenance-type** jobs may be excluded from escalation (they still exist as job cards; they just are not chased the same way).

## What you will notice as an operator (creator)

- You get notified when someone accepts and when the job closes.
- If nobody has taken the job after Stage 1, you may get a **follow-up**: the job is still open and people have been notified — you can chase locally if needed.
- You do **not** need to be on site to get that creator follow-up.

## What you will notice as a manager

- Escalation exists so open faults do not sit on one quiet phone.
- Stage 1/2 bring foremen and managers in when the floor has not responded.
- You can review open jobs on Pulse (**Job Cards**) and on mobile lists that your role allows.
- Changing who gets which stage is an **Admin** configuration task — ask Factory Admin if timings feel wrong (too noisy or too slow).

---

## What stops escalation

Escalation for a job stops when, for example:

- Someone **assigns** themselves (or is assigned) to the job
- A response such as **Busy** is recorded in a way that parks further chase for that job
- The job is no longer in an escalatable open state

Once stopped, later stages should not keep pinging people about that same open chase.

---

## Fairness and on-site

Alerts for new work are aimed at people who are **on site** for the right trade. That is intentional: it reduces noise for people who are off shift or off plant, and it matches who can actually walk to the machine.

If you are physically on site but the app shows you **off site**, fix geofence / location permissions first (see **Troubleshooting**). Wrong on-site status is the most common reason someone “never got the job.”

---

## Permissions that matter for alerts

For P3+ and especially loud P4/P5 alarms to work reliably:

- Notifications allowed
- Battery unrestricted for CTP Job Cards
- Do Not Disturb exception where needed for priority alarms
- Background location / always-on location for geofence on-site

Home shows a health banner when something is missing — tap **Fix** and complete the list.

---

## Admin note (managers / admins)

Configure stages under **Admin → Escalation** (or Factory Admin → Escalation):

- Turn stages on/off
- Set minutes between create and each stage
- Choose recipient groups (managers, foremen, etc.)

Only people with Admin access should change this. If a stage is turned **on** after being off, only **new** jobs created after that change are meant to use the newly enabled stage — so old open jobs do not suddenly flood phones.

---

## Related guides

- **Employee Guide** — day-to-day job-card flow  
- **Manager Guide** — oversight and quality  
- **Troubleshooting** — notifications not arriving, geofence, updates  
- **App Features** — full feature overview  

*(Developers maintaining Cloud Functions / config schema: see `dev-docs/escalation_system_engineering.md` in the repo — not shipped in the app.)*
