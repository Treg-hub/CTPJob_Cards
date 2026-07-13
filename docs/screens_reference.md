# Screens guide — what each area of the app does

A plain-language map of the main screens. Written so everyone can see **what exists**, **who it is for**, and **why** — without engineering file names or backend internals.

Guards who only use Site Security see a simpler Home; their Security and Waste guides cover that layout.

---

## Getting in

| Screen | Who | What it does |
|--------|-----|--------------|
| **Login** | Everyone | Email + password. After a successful sign-in you go to onboarding (first time) or Home. |
| **Create account** | New users | Links your login to your existing employee clock number (HR must already have your row). |
| **Permissions / first-run tour** | First launch | Explains your role, job flow, priorities, escalation, then asks for notifications, overlay, battery, location, etc. |

Forgot password uses the normal email reset flow.

---

## Home and navigation

| Area | Who | What it does |
|------|-----|--------------|
| **Home (standard)** | Most staff | On-site / off-site status, Quick Actions (create job, My Work, view jobs, modules you are allowed to use), optional Recent Job Cards for managers. |
| **Home (Security guard hub)** | Site Security guards (not security managers) | Module cards for **Site Security** and **Waste** when enabled — not the full job-card tile set. |
| **Bottom tabs** | Role-dependent | My Work, modules (Fleet / Ink / Waste / Security / Copper) when your role and factory settings allow them. |
| **Notification inbox (bell)** | Everyone | Held or parked messages (e.g. while off site) you can open later. |
| **Settings** | Everyone | Preferences, permissions, theme, check for update, documentation, sign out. Admins also reach Factory Admin tools from here. |

**Off-site note:** Creating a new job card normally requires you to be **on site**. Other actions (reading lists, inbox, some modules) may still work off site depending on rules.

---

## Job cards (core)

| Screen | Who | What it does |
|--------|-----|--------------|
| **Create Job Card** | Operators, technicians, managers (when on site) | Capture department, area, machine, fault, priority, type (mechanical / electrical / both). Tips can be dismissed and restored in Preferences. |
| **My Work** | People with job-card work | Jobs assigned to you or that you created; start / complete / monitor / comments / photos. |
| **View Jobs** | Broader visibility roles | Browse by status (open, in progress, monitoring, closed) with filters. |
| **Job History** | Search roles | Find closed jobs (server search — not every old card is kept on the phone). |
| **Job detail** | Anyone who can open that job | Full story: status, people, comments, photos, completion notes. |
| **Daily Review** | Managers | Day’s work overview for quality and follow-up. |

Priority **P1–P5** affects how loud and urgent notifications are (P5 can take over the screen when configured).

---

## Escalation and alerts

Escalation is explained in full in **How escalation works**. In short: if nobody takes an open job, wider groups are notified on a timer so faults are not ignored.

---

## Modules (when enabled for you)

| Module | Typical users | What mobile is for |
|--------|---------------|--------------------|
| **Site Security** | Guards, security managers | Gate scans (vehicles, visitors, company cars), on-site lists, force sign-out when needed. Managers also use Pulse for reports/costs. |
| **Waste Recovery** | Security / waste roles | Schedule, stock, collect, finish loading on the phone. Weighbridge and costing live on **CTP Pulse**. |
| **Fleet** | Reporters, mechanics, cost managers | Report machine issues, fix / log work, urgency. Cost detail may be role-limited. |
| **Ink Factory** | Ink floor + related roles | Daily meter readings, receive stock / IBC, production, tips. Manager costing and month-end are on **CTP Pulse**. |
| **Copper** | Admins and Pre Press managers | Copper inventory tab when your role allows — no shared password; access is by role. |
| **My Timesheet** | Enrolled workers | Monthly hours from jobs + extra lines; PDF for Accounts when enabled for you. |
| **Feedback** | Everyone | Send feedback (optional photos); thread replies with the CTP team. Admins triage submissions. |

If a module tile is missing, you either do not have that role or the factory has the module switched off — ask a manager or Admin.

---

## Admin and Factory Admin (admins only)

Admins can open tools for employees, site/geofence, escalation timing, module gates, app update channels, on-site who’s who, and feedback triage. Those screens are intentionally **not** listed in detail here for every employee — if you need a change, ask Factory Admin.

---

## Documentation inside the app

**Settings → Documentation** lists the guides your role can see (this screen guide, escalation, employee/manager guides, module guides, changelog, troubleshooting).

---

## Related

- **Employee Guide** — step-by-step daily use  
- **How escalation works** — why alerts widen over time  
- **Troubleshooting** — empty Home, notifications, updates, geofence  

*(Developers needing Dart paths and collection maps: `dev-docs/screens_reference_engineering.md` in the repo — not shipped as the in-app guide.)*
