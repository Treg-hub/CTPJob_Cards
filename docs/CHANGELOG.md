# CTP Job Cards — Documentation Changelog

Append-only log of user-visible changes. Add a new entry at the top each release; do not edit historical entries except to fix factual errors.

The role guides, the onboarding flow, and the reference docs all draw from this log. Whatever you write here is what staff will read next time they open the docs portal.

---

## 2026-07-18 — 2.3.0+178 — Copper ready for Waste collection

### What you will notice

- When copper is moved to **To Sell** (plate bars or sort to sell), it also appears as **Waste stock** (Rods and Nuggets) for collection.
- Security can open **Waste**, use **From stock**, and link those copper items to a Copper Waste load.
- Completing the waste load still records the commercial sale; there is no sale button on the Copper tab.
- Copper screen text explains staged stock and how it is collected; leftover tiny amounts can still be cleared by admins with a reason.
- The old “wait for 400 kg before stock appears” step is gone — stock updates as you stage metal for sell.

---

## 2026-07-17 — 2.3.0+177 — Copper process and clearer tabs

### What you will notice

- On **Copper**, commercial sales are recorded when a Copper Waste load is completed — not from a sale button on Copper.
- Sorting uses separate **Reuse** and **Sell** amounts; small leftovers in **To Reuse** clear more reliably (use **All** if needed).
- A collection status area shows progress toward the collection threshold and can open **Waste** when stock is ready.
- Admins can **Adjust** a copper bucket or **Zero dust** (tiny leftovers) with a short reason.
- **Dept Requests** and **Fleet** tab labels are easier to read and better aligned.

---

## 2026-07-17 — 2.3.0+176 — Home stability after updates and return to site

### What you will notice

- After an app update, Home and job lists should load without needing to force-close and reopen the app.
- When you return to the factory with the app still open, modules and Recent Jobs refresh more reliably.
- Admins and multi-module users stay on **Home** instead of being taken to **Fleet** unexpectedly; Hyster Mechanics still open Fleet as usual.

---

## 2026-07-16 — 2.3.0+175 — Dept Requests for managers

### What you will notice

- Managers get a new Home tile **Dept Requests** to leave a short note for another department (or your own) with department and area, optional photos, and a reply thread.
- Opening a request for your department marks it seen; mark **Done** when it is handled. Open items older than two days show a gentle reminder.
- Admins can open **All Dept Req** on Home to see every request.
- Guidance tips on Dept Requests can be hidden and turned back on under **Settings → Preferences**.

---

## 2026-07-16 — 2.3.0+174 — Employee position and department pickers

### What you will notice

- On **Factory Admin → Employees**, when you add or edit someone, **Position** and **Department** open a full list of values already in use (tap the arrow). You can still type a new value if needed.
- Registration lock and the other admin hire tools from the previous pilot build are still included.

---

## 2026-07-16 — 2.3.0+173 — Admin hire tools and job status polish

### What you will notice

- Job cards that use status labels like **In Progress** or **Monitoring** open and display more reliably.
- **Factory Admin → Employees:** lock or unlock registration for a clock number so new hires can register when ready.
- **Factory Admin → Employees:** pick **Position** and **Department** from values already in use, or type a new one.
- If your account is missing a clock number after sign-in, you get a clear message so notification inbox issues are not silent.

---

## 2026-07-15 — 2.3.0+172 — Fix received IBC shipments on Receive Ink

### What you will notice

- On **Receive Ink (IBC)**, shipments already received in the current count period now show under **Received this period** (this was missing on some devices).
- Outstanding shipments still appear at the top as before.

---

## 2026-07-15 — 2.3.0+171 — Ink receive lists + IBC wash confirm

### What you will notice

- On **Receive Local**, orders already fully received in the current count period appear under **Received this period** (greyed — for reference only).
- On **Receive Ink (IBC)**, shipments already received in the current count period appear the same way under **Received this period**.
- Outstanding orders and shipments still appear at the top so you can receive them as usual.
- On **Consume IBC**, if you leave **Toloul used to wash** blank, the app asks you to confirm no wash was used. You can go back and enter litres, or confirm no wash (flagged for manager review on Pulse).

---

## 2026-07-15 — 2.3.0+170 — My Timesheet PDF polish and notes

### What you will notice

- My Timesheet PDF looks cleaner (header, job table, total hours) and special characters no longer show as blank boxes.
- You can add optional Notes on the timesheet hub; they appear at the bottom of the PDF, with space to write more by hand if needed.

---

## 2026-07-15 — 2.3.0+169 — My Timesheet weekly + job work date

### What you will notice

- My Timesheet is now week by week (Monday to Sunday). Use the arrows to move between weeks.
- Each job line has a work date for the timesheet. It starts as the job card create date and you can change it without changing the job card itself.
- You enter hours and an optional billing summary on each job line. There is no separate additional-work screen.
- PDF and CSV share are in the top bar on My Timesheet.
- Editing an older week asks you to confirm first.

---

## 2026-07-14 — 2.3.0+168 — Post Press Specialist job type

### What you will notice

- Post Press Specialist is available as a job type when creating and viewing job cards.
- Post Press Specialist roles show the matching badge and home behaviour for that role.
- On-site Post Press Specialist auto-assign works the same way Pre Press Specialist does for matching jobs.

---

## 2026-07-14 - 2.3.0+167 - Confirm consumption works for all IBC barcodes

### What you will notice

- Scanning or looking up an IBC and confirming consumption no longer fails with a permission error.
- Both the older 8-digit barcodes and the newer longer barcode formats work the same way on Consume.
- Wash litres and the damaged toggle still work as before after you confirm.

---

## 2026-07-14 - 2.3.0+166 - Consume IBC confirm works with both barcode formats

### What you will notice

- **Confirm consumption** no longer fails with a permission error when the IBC was scanned or looked up by barcode.
- Both the older last-8 barcode style and the newer full SSCC-style codes resolve to the same IBC, so either format works on Consume.
- Marking an IBC damaged or sending it for wash still works the same way after you confirm.

---

## 2026-07-12 — Pilot 2.3.0+165 (Ink Factory — feedback photos)

### What you will notice

- When you **Give Feedback**, you can attach up to **3 photos** (camera or gallery) — useful for screenshots or a picture of the problem.
- In a feedback **thread**, you and the CTP team can attach photos on replies the same way.
- Tap a photo thumbnail to view it full screen.

### For admins

- Triage board shows photo thumbnails on submissions; reply from the thread with photos if needed.
- **Deploy required**: Storage rules from `/firebase` (`feedback/{id}/photos/**`) before the APK that uses this feature (if not already live).

---

## 2026-07-12 — Pilot 2.3.0+164 (Ink Factory — security hardening)

### What you will notice

- Same security work as factory **163**: clearer **Create account** link messages, module role flags (Security / Fleet / Ink / Waste) with existing allow-list fallback, quiet app build reporting for managers, safer assign-to employee lists when the server supports them.

---

## 2026-07-12 — Factory + Pilot 2.3.0+163 (security hardening)

### What you will notice

- **Create account** gives clearer messages when something blocks linking (wrong company email, clock locked for registration, or already linked).
- **Security / Fleet / Ink / Waste** access can follow server role flags as well as the existing allow-lists — behaviour stays the same for staff already on the lists.
- Opening the app reports **which build you are on** (quietly) so managers can see who still needs the update.
- Assign-to pickers prefer a safer employee list from the server when available (no sensitive account fields in the list).

### For admins

- Factory + pilot binaries: **2.3.0 / 163**
  - Factory / landing Download: `https://ctp-job-cards-landing.web.app/releases/latest.apk`
  - Pilot channel URL (if still used): `https://ctp-job-cards-landing.web.app/releases/pilot.apk` (same build when promoting pilot)
- Publish **Default + Shared** to **2.3.0 / 163**, Shared download URL = factory `latest.apk`, Force **off** unless you need a hard push.
- **On Site** shows each person’s app version/build (or “Unknown” until they open this APK once).
- Registration: optional **company email match** and **registration_locked** on employee rows (server-side); existing linked accounts are not broken.
- Deploy Cloud Functions with this release so presence version reporting and tighter `linkEmployeeAccount` rules are live.

---

## 2026-07-11 — Factory 2.3.0+162 (soft-delete + My Work + Copper)

### What you will notice

- **Job cards stay in the system** — closed jobs are archived; any admin cleanup is **soft-delete** only (hidden from floor lists, kept for audit). Staff create/complete jobs as usual.
- **My Work** no longer stuck on “Waiting for connection…” after login/security refresh; **Retry** if needed.
- **Copper** tab (admins + Pre Press managers only) opens directly — **no password**, no clock prompt.
- Soft-deleted jobs (if any) no longer appear in active lists or open-job KPIs.

### For admins

- Factory download: **2.3.0 / 162** → `https://ctp-job-cards-landing.web.app/releases/latest.apk`.
- Publish Default + Shared channels to **2.3.0 / 162** with that Shared download URL.
- Soft-delete API is ready for admin tools; floor apps do not hard-delete job cards.

---

## 2026-07-11 — Pilot 2.3.0+161 (Copper tab + My Work)

### What you will notice

- **Copper** bottom tab (admins + Pre Press managers only) opens copper straight away — **no clock-number prompt**.
- **My Work** no longer stuck on “Waiting for connection…” after security rules refresh; **Retry** button if needed.
- Copper: no shared password; access by role only.

### For admins

- Factory **latest.apk** stays lower (e.g. 159) until promoted.

---

## 2026-07-11 — Copper tab: open directly (no clock entry)

### What you will notice

- **Copper** bottom tab (admins + Pre Press managers only) opens the copper screen straight away — **no clock-number prompt**.
- Others never see the tab; server rules still block copper data.

---

## 2026-07-11 — Pilot 2.3.0+160 (My Work connection fix)

### What you will notice

- **My Work** no longer stays stuck on “Waiting for connection…” when one of its job lists was still on a cold cache after login (seen after security rules refresh, especially Ink Factory operators).
- **Retry** button on that screen, and app resume reloads My Work cleanly.

### For admins

- Factory **latest.apk** unchanged until promoted.

---

## 2026-07-11 — Copper access by role (no password)

### What you will notice

- **Copper** opens for **admins** and **Pre Press managers** only — **no shared password**.
- Hard-coded clock list (22 / 5421 / 20) removed; access follows your department and position.

### For admins

- Ensure Pre Press managers have department **Pre Press** and a position containing **Manager**.
- Residual `copperPassword` on server can be cleared with `clear_copper_password.mjs` after rules deploy.

---

## 2026-07-11 — Factory 2.3.0+159 (copper password + security)

### What you will notice

- **Copper module password** now reads from the secure server settings (`app_secrets`). Required after the factory security migration so Copper unlock keeps working for clocks 22 / 5421 / 20.
- Job Cards create/edit and other floor modules unchanged for this purpose.

### For admins

- Factory download: **2.3.0 / 159** → `…/releases/latest.apk`. Publish Default + Shared to this build.
- Copper users should update to this build (or newer). Older APKs may fail Copper password after secrets moved off `settings/app`.

---

## 2026-07-10 — Pilot 2.3.0+158 (minify + safe area + cleanup)

### What you will notice

- **Smaller install** — release APK uses R8 minify (~**47 MB** vs ~**52.5 MB** without minify on the same code).
- **Bottom safe area** fixed on My Timesheet, Fleet lists, Ink meters/production/IBC register, waste stock, feedback.
- **Receive Local** + ink process tips (from +157) included.
- Unused Ink **manager** screens removed from the app (use **CTP Pulse** for costing/month-end/setup).

### For admins

- Pilot: **2.3.0 / 158**, Channel APK URL = `…/releases/pilot.apk`. Keep Shared/Default on factory `latest.apk`.
- Smoke release-only paths before factory: FCM, geofence, Ink scan, Security disc if used.
- Mapping: `build/app/outputs/mapping/release/mapping.txt` after release builds.

---

## 2026-07-10 — Pilot 2.3.0+157 (Receive Local + tips)

### What you will notice

- **Receive Local** (was “Receive Stock”): lists **outstanding local purchase orders** after a manager marks them sent on CTP Pulse. Tap an order, enter **quantity received** per open line, confirm. Partial deliveries stay listed until fully received.
- **Receive without order** is still available for ad-hoc stock (secondary button).
- Cyan **process tips** on Ink hub, Receive Local, Receive Ink (IBC), meters, consume IBC, and production. Tap **×** to hide; restore in **Settings → Preferences → Ink Factory Tips**.
- **Receive Ink (IBC)** still list-first for import shipments.

### For managers (Pulse)

- RFO PDF is for **board explanation** only — no need to upload a signed RFO back into Pulse.
- Workflow: generate/download RFO → **Mark RFO approved** → Pastel RFO # + order # → mark sent → operators see the order under **Receive Local**.
- Deploy Pulse hosting separately for board tips + RFO flow.

### For admins

- Pilot channel: **Version 2.3.0 / Build 157**, **Channel APK URL** = `https://ctp-job-cards-landing.web.app/releases/pilot.apk`. Keep Shared/Default on factory `latest.apk`.

---

## 2026-07-10 — Pilot 2.3.0+155

### What you will notice

- Analyzer cleanups (waste screens unused imports, share API, update service mounted checks).
- **Admin stale job follow-up** is on **CTP Pulse** (web, admins only) + Cloud Functions — not a new mobile screen. Affected people get an **inbox** message only (no push re-alert).

### For admins

- Deployed: `onJobCardAdminFollowUp` (jobcards codebase). Pulse must be deployed separately for the dialog UI.
- Pilot channel: point Departments/People **Channel APK URL** at `…/releases/pilot.apk`. Keep **Shared / Default** on factory `latest.apk`.

---

## 2026-07-09 — Lighter Firestore reads (Phase B)

### What you will notice

- **Ink daily readings** banner on Home only appears when readings are still incomplete (not a constant live update).
- **Waste on-site stock** lists load once; **pull down to refresh** when you need newer stock.
- **View Jobs** loads 100 jobs per status tab; pull to refresh, use **Load more** for older rows.
- **Fleet urgent banner** clears when issues are fixed without extra loading lag (server keeps inbox in sync).
- **Copper transactions** default to the **last 90 days** (pick a custom range if needed).
- Security gate / visitor screens use cached deny list, vehicles, and contractors (pull to refresh on Security home / on-foot).

### For admins

- Fleet CF already parks `issueStatus` / `issueDeleted` on inbox items. Optional one-off:  
  `node firebase/functions/scripts/backfill_fleet_inbox_denorm.mjs --dry-run` then without `--dry-run`.
- See monorepo `docs/Firestore_Cost_Discipline.md` Phase A + B.
- Pilot smoke before factory APK rollout.

---

## 2026-07-09 — Lighter Firestore reads (Manager desk on Pulse)

### What you will notice

- **Manager Dashboard** is no longer a tab in the mobile app. Department KPIs and analytics live on **CTP Pulse** (web) under **Job Cards**.
- **View Jobs** only loads the status tab you are looking at (Open / In Progress / Monitoring / Closed).
- **My Work → Closed** shows the most recently closed jobs first.
- Open/in-progress count badges on Home are for **managers** (saves battery/data for operators).

### For admins

- Deploy composite indexes for My Work closed queries (`firebase/firestore.indexes.json`) before relying on Closed tab sort in production.
- See monorepo `docs/Firestore_Cost_Discipline.md` Phase A.

---

## 2026-07-09 — Update check uses Admin publish first (build 147)

### What you will notice

- **Check for update** / in-app update now follows **Admin App Update Control** (Hosting APK URL), not an old Firebase App Distribution link from Remote Config.
- Soft and required updates still download and install inside the app from the official company file.

### For admins

- Shared download URL must stay: `https://ctp-job-cards-landing.web.app/releases/latest.apk`
- Settings → Check for update shows **Config source** (e.g. `firestore:default`).
- Playbook: `docs/RELEASE_PLAYBOOK.md` · `/mobile-app-release`

---

## 2026-07-09 — Official download page + release 2.3.0 (build 146)

### What you will notice

- **First install** from the company download page (**Download app** or QR) — no Firebase App Distribution register step.
- After install: **Create account** or **Log in** inside the app (clock number + email).
- **Updates** still install in-app from the same official APK when Admin publishes a new build.
- Reliable required-update prompts and soft **Later** (about one day).

### For admins

- Shared download URL: `https://ctp-job-cards-landing.web.app/releases/latest.apk`
- Ship steps: `docs/RELEASE_PLAYBOOK.md` · skill `/mobile-app-release`

---

## 2026-07-09 — More reliable app updates (build 145)

### What you will notice

- **Required updates** reappear as soon as you return to the app (not only after a full restart or a long wait).
- Soft **Later** only hides the orange banner for about a day — it can come back until you install.
- First-time in-app install: clearer guidance when Android asks you to **allow CTP Job Cards to install apps**.
- **Official download** is this company page (Download app) — then create account or log in inside the app. Later updates install from the same official source in-app.

### For admins

- Full ship steps: **`docs/RELEASE_PLAYBOOK.md`**. Channels: `docs/admin_app_update_guide.md`.
- Shared download URL must be the Hosting APK (`…/releases/latest.apk`), not App Distribution.
- Always set Shared download URL before raising **min supported build**.

---

## 2026-07-09 — Targeted updates & department/people pickers (build 136+)

### Easier app updates (for everyone)

- **Download & install inside the app** — when an update is available, use **Update** (banner) or **Download & install** (force screen). Progress shows while the APK downloads; Android opens the system installer.
- **Soft updates** no longer take over the whole screen — an orange **banner** on Home is enough; **Later** snoozes about a day.
- **Force updates** (when Admin turns them on for your group) still block until you install.
- **Check anytime** — Settings → **Check for Update**.

### For admins

- Full operator guide: **`docs/admin_app_update_guide.md`** (also linked from docs hub after landing rebuild).
- **App Update Control** — three channels: **Default** (factory), **Departments** (multi-select from employee/structure lists), **People / pilot** (multi-select people, optional departments). Match order: People → Departments → Default.
- **Force per channel** — e.g. force Ink Factory only without forcing the plant.
- **24-hour** automatic check; force re-blocks on resume. Kill-switch (`min supported build`) remains factory-wide.
- **Save publish** writes `settings/app.updateChannels` + legacy Default fields for older APKs. **Copy RC keys** = Default only.

### First-time setup by role (unchanged)

- **Security / Fleet / Ink** staff get a shorter first-run tour; classic job-card roles keep the full tour.

---

## 2026-07-08 — In-app install path (build 131+)

### Install path

- In-app APK download + system installer; install-unknown-apps permission; browser fallback.
- Settings → Check for Update; What's changed after install (multi-build rollup).

---

## 2026-07-06 — Version 2.3.0 (build 121) — My Timesheet + waste hardening + Pre Press fix

Follow-up to the wide **v2.3.0** rollout. First open shows this summary in **What's changed**.

### New — My Timesheet (pilot: clock 10338)

- **Home tile** — enabled workers see **My Timesheet** (teal). Admins configure enrolment in **CTP Pulse → Settings → My Timesheet**.
- **Job hours** — pick a calendar month; job cards you were assigned to, started, or completed in that period appear with editable hours and an optional billing summary line per job.
- **Additional work** — log ad-hoc tasks (date, hours, description, optional job-card link).
- **PDF for Accounts** — export a monthly PDF (hours only; department + position on the header). Soft-lock warning if you edit after exporting.
- **Offline** — line edits queue locally and sync when back online.

### Waste Recovery — queue-first capture (dedicated device)

- **Save never blocks on Wi‑Fi** — collection submit, finish loading, and large creates write to local queue + persistent photo folder first; sync runs in the background.
- **Large loads** — 25+ items/photos use batched local I/O so the guard is not stuck copying media.
- **Offline create** — on-site stock selected at schedule time is snapshotted so items queue without a live Firestore read.
- **Rates** — costing stays on CTP Pulse only (mobile does not stamp `rate_per_kg` on add-item).

### Pre Press Specialist — job-card access fix

- **Workshop | Pre Press Specialist** now resolves correctly (position title is authoritative, not department alone).
- Can **Start / Complete / Monitor** any job assigned to them; **Pre Press Spec** jobs still auto-assign when the specialist is on-site.

---

## 2026-07-06 — Version 2.3.0 — everything since v2.1.1 (build 38)

This is the wide rollout. If you have been on **v2.1.1 (build 38)** since 17 June, here is everything that has changed in **v2.3.0**. Four whole modules are new — **Site Security**, **Fleet Maintenance**, **Ink Factory**, and **Waste Recovery** — alongside major reliability work, a refreshed Home screen, and a long list of job-card and Admin improvements. The dated entries below carry finer detail; role guides for each module are in **Settings → Documentation**.

The first time you open this build, a **What's changed** sheet shows this summary. Tap **Full changelog** any time for the complete history.

### New module — Site Security (gate staff)

Security guards get a dedicated module for controlling the main gate:

- **Two gate entry points** — **Visitor / Contractor Vehicle** and **Company Car** (shorter, purpose-built forms instead of one combined screen). Gate tools live on the **Security** tab, not the Home quick-actions grid.
- **Scan-first vehicle flows** — scan the licence disc and the **number plate** is read automatically (including newer MVL disc formats). Scanning the wrong document (e.g. the disc again on the licence step) shows **Incorrect scan** and does not accept it.
- **Disc → licence chain** — after a successful disc scan on visitor entry (or company-car exit), the driver's-licence scanner opens automatically. You can tick **Driver's licence not scanned** and pick a reason (**No licence**, **Disc expired**, **Licence expired**, **Other**) when needed.
- **Damaged disc** — visitors type the registration; company cars pick from the registered list only. If a typed visitor plate matches a company car, a **Switch** banner opens the Company Car flow.
- **Compliance & audit** — expired disc/licence needs an override reason (shown only when compliance actually warns). **Force sign out** (⋮ menu on **On Site**) clears stuck vehicles/visitors with a recorded reason. Re-entry without an exit auto-closes the stale visit and flags it for review.
- **Photos on every gate flow** — attach photos on visitor entry/exit and company-car exit/return. Company-car trips and mileage survive going offline.
- **On-Foot Visitor** — walk-in capture with optional ID scan.
- **On Site view** — tabbed live view of vehicles and visitors, ordered by server event time so multiple devices agree.
- **Guard home hub** — guards see a **Your modules** home (Site Security + Waste Recovery) instead of job-card tiles; the app can open straight into Security. Managers and admins keep the full job-card home plus Security and Waste tabs.
- **Scan tester** — **Settings → Admin → Scan Tester** for verifying disc and licence scanning before go-live.
- **Kiosk mode** — a dedicated gate tablet can be locked to this app only (no home screen, no other apps, survives reboots).

### New module — Fleet Maintenance (forklifts, grabs & BT)

A full fault-and-fix system for the fleet:

- **Who gets it** — configured in **Fleet Settings** on CTP Pulse. **Reporters** by department; machines can be department-scoped. **Mechanics** and **cost managers** by clock number.
- **Report a problem** — guided wizard: machine, urgency, description, optional photo. Reports are **permanent**; the mechanic's fix is recorded separately.
- **Daily pre-use safety check** — 14-item checklist with start hour meter; **Faulty** auto-raises a mechanic fault. End-shift captures closing hour meter. Separate from fault reporting.
- **Mechanic view** — work queue, log work records, machine hours. Work records lock after a set window. Mechanics **never see costs** on mobile.
- **Mechanic polish** — urgent banner clears when the linked issue is resolved; log-work forms show all fields flat (no collapsed "More details"). Dismissible on-screen tips while learning the module.
- **Notifications** — out-of-service reports push immediately; fleet notifications deep-link to the fault.

### New module — Ink Factory

Ink store and Lurgi operations move off paper. **Phone = capture; CTP Pulse = management** — operators never see money on mobile.

- **Mobile hub** — receive stock, meter readings, production runs, Toloul recovery, IBC register, stock balances. Month-end, costing, recipes, corrections, and reports live on CTP Pulse.
- **Barcode-driven receiving** — IBCs and raw materials against a Pulse shipment or PO; scanner validates serials, pre-fills colour/weight, torch in low light.
- **Consume by QR** — scan-and-confirm with wash quantities; damaged-IBC toggle keeps broken containers out of waste-bin stock.
- **Combined daily readings** — all ink meters and Toloul points on one screen, one submit; blank fields skipped. Cyan **Daily readings incomplete** banner on Home when today's readings are outstanding.
- **Toloul factory vs Lurgi** — separate factory-tank and Lurgi balances; **Lurgi low** alert when below threshold.
- **Safe corrections** — production runs, IBC consumptions, and meter sessions can be **voided** (fully reversed). Month-end counts snapshot stock values; backdating past month-end is admin-only.
- **Ink tiles are cyan** — Ink Factory and Daily Readings use cyan (#06B6D4), distinct from job-card orange.

### New module — Waste Recovery

Tracks every waste load leaving the site (permanent **W-NNNN** load numbers):

- **Managers schedule, guards capture** — schedule on Pulse; **Begin Collection** on the phone. Create-from-scratch at the gate follows the same rules (paper doc ref, photos/signatures per settings, audited overrides). Vehicle and trailer registrations captured.
- **On-site stock builds itself** — IBC consume auto-adds **IBC Bins** stock; copper at **400 kg** auto-creates **Copper Waste** for managers.
- **Offline you can trust** — photos and signatures stored safely, retry automatically, status on the Queued screen; unrecoverable media flagged clearly.
- **14-day home window** — lists show the last 14 days; full history on Pulse.

### Job cards & Home

- **Off-site made clear** — Create Job Card greys out off-site with a reason; tapping explains why.
- **Quick Actions** — colour-grouped tiles (job cards orange, Ink cyan, Fleet slate, Daily Review gold); uniform size on every screen size; centred on phones; gate tiles removed from Home (use Security tab).
- **Job card tiles** — flatter cards, priority border, compact description, grouped comments/notes; orange job-number badge on lists (Home, View Jobs, My Work, History, Daily Review).
- **Job Card History** — auto-loads last 30 days; date chips always visible; location filters in a bottom sheet.
- **Tips you can hide** — guidance tips on Create Job Card have a **×** dismiss; restore in **Settings → Preferences → Job Card Tips**.
- **Presence app bars** — orange → green/red gradient on pushed Job Cards screens when on/off site.
- **Brand orange** updated to terracotta (`#C25F3A`).
- **Fits your screen** — edge-to-edge with corrected safe areas; submit bars no longer hidden behind the gesture bar.
- **My Feedback** — Home FAB opens your submissions with two-way reply threads; admins triage from Admin.

### Reliability & updates

- **What's changed sheet** — first launch after each update shows release notes (once per build); **Settings → Documentation → Changelog** for full history.
- **No more blank Home after sign-in** — if lists were refused briefly after login, the app self-heals: refreshes access, retries streams, shows **Waiting for connection…** instead of false empty states. **Session expired** banner with **Sign in** when your account lapsed.
- **Geofence resume fix** — opening the app after an **arrived on-site** notification no longer leaves Home incomplete (missing Fleet/Security tabs, empty Recent Job Cards). Presence, module settings, and job streams refresh on resume.
- **Steadier scanners** — document scanners wait for the camera to be ready before starting, reducing rare crashes on some Android devices.
- **Smoother navigation** — consistent slide transitions and edge-swipe back.

### Notifications & presence

- **Permission health** — Home banner watches all six Android settings job alerts depend on, with one-tap **Fix** for each.
- **iPhone / web** — notifications delivered reliably to the in-app inbox.
- **Steadier on-site detection** — fixes for multi-device snackbar spam and less trigger-happy boundary transitions.

### Admin

- **Refreshed Admin** — five tabs opening on Settings; searchable employee cards with tap-to-toggle on-site; Structures with search and duplicate protection. Job-card exports moved to CTP Pulse.
- **User feedback board** — triage submissions (New → Planned → Implemented → Declined) with private notes and two-way reply threads.
- **Role testing** — preview as any role with **all writes blocked**.
- **Targeted broadcasts** — message specific clock numbers; On Site tab shows permission health and 14-hour stuck-on-site flags.

---

## 2026-07-05 — Gate-friendly security flows, job-card polish

### Site Security

- **Two gate entry points.** Site Security home now has **Visitor / Contractor Vehicle** and **Company Car** instead of one combined **Vehicle at Gate** screen — shorter forms for guards.
- **Damaged disc on visitors.** Tick **Disc damaged / cannot scan**, type the registration (no company-car dropdown). If the plate matches a company car, a **Switch** banner opens the Company Car flow with that vehicle pre-selected.
- **Damaged disc on company cars.** Pick the vehicle from the registered list only — no typing the plate manually.

### Look & feel

- **Brand orange** updated to terracotta (`#C25F3A`). Home Quick Actions centre on phone.
- **Presence app bars** (`CtpAppBar`): orange → green/red gradient on pushed Job Cards screens when on/off site.
- **Job Card History** auto-loads last 30 days; date chips always visible; location filters in a bottom sheet.
- **Fleet mechanic** urgent banner clears when the linked issue is resolved; log-work forms show all fields flat (no collapsed "More details").

---

## 2026-07-04 — Sharper job cards, cyan Ink tiles (build 2.2.0+110)

### Look & feel

- **Job card lists read cleaner.** The shared job card tile (Home **Recent Job Cards**, View Jobs, My Work, History, Daily Review) uses a flatter card with a thin priority border and coloured left edge, a more compact description line, and comments / notes / corrective action grouped in a small inset block. Job numbers use the brand-orange badge.
- **Quick Actions on wide screens.** Fixed a one-pixel bottom overflow on full-width desktop and tablet layouts. Home and Ink reminder tiles use a consistent 10px corner radius.
- **Ink module is cyan.** Ink Factory, Daily Readings, and the daily-readings reminder banner use cyan (#06B6D4) instead of indigo — clearer on dark theme and distinct from job-card orange.

---

## 2026-07-04 — Site Security fixes, clearer job-card tips, ink reminder colour

### Site Security

- **Vehicle disc scan now reads the number plate.** Scanning a licence disc was showing the internal vehicle-register reference (e.g. VCG592W) instead of the actual number plate (e.g. CG24MTZN). It now shows the plate as printed on the disc.
- **After a disc scan, the app goes straight to the driver's-licence scan.** For a visitor entry (and company-car exit) a successful disc scan now automatically opens the licence scanner — it previously only did this after a manual re-scan.
- **You can proceed when a driver has no licence.** Previously, if the licence-required setting was on and the driver had no licence, you were stuck. Now you can tick **"Driver's licence not scanned"** and pick a **reason** — **No licence**, **Disc expired**, **Licence expired**, or **Other** (with a detail) — and continue. The reason is recorded on the entry. The old free-text "licence not available" note and the separate "override reason" box are combined into this one clear reason picker.
- **Force sign-out for stuck vehicles/visitors.** If someone's exit was never captured and they're stuck showing as on-site, tap the **⋮** menu on their row in **On Site** and choose **Force sign out (no scan)**. You must pick a reason; the action is recorded in the security audit log.
- **Damaged/dirty disc? Type the registration.** On a visitor entry, if the licence disc can't be scanned you can now enter the registration manually — the entry is logged and flagged as a missing disc scan, instead of leaving you unable to admit the vehicle.
- **Re-entry without an exit keeps the line moving.** If you scan a vehicle in while it's still shown on site (its exit was missed), the app auto-closes the old visit with a **flagged-for-review** exit and logs the new entry — no need to log an exit first and hold up the queue.
- **Company-car exit now checks the disc/licence expiry.** Like a visitor entry, a company car with an expired disc or licence now needs an override reason before it can leave — recorded for audit.
- **Photos on every gate flow.** You can now attach a photo on company-car exit/return **and** visitor exit — not just visitor entry.
- **Trips and mileage survive going offline.** Company-car trip and odometer records are now durably saved on the device and sync when you're back online, instead of only being written when connected.
- **On Site tabs are readable again.** The Vehicles / Visitors tabs no longer render orange-on-orange in dark mode.

### Job Cards

- **Tips can be hidden.** The guidance tips on the Create Job Card screen now have a small **×** to hide them once you know the ropes — freeing up space. Turn them back on any time from **Settings → Preferences → Job Card Tips**.

### Ink

- **Daily-readings reminder matches the Ink colour.** The "Daily readings incomplete" banner now uses the Ink module tint (cyan from build 2.2.0+110; briefly indigo) instead of pink/red.

---

## 2026-07-03 — Steadier start-up, smoother navigation, tidier desktop

### Reliability

- **Fixed the "logged in but nothing shows up" problem.** Occasionally you could sign in and the Home screen would sit empty — no jobs, no counts, no inbox badge — until you force-closed and reopened the app. The app now automatically retries in the background and refreshes your access the moment it's ready, so your data fills in on its own within a few seconds instead of staying blank.
- **Offline no longer looks broken.** When you open the app with no signal, lists now show a "Waiting for connection…" state instead of a misleading "No recent jobs". As soon as you're back online everything loads — no restart needed.
- **"Session expired" is now recoverable.** If your sign-in has lapsed (for example your account was changed on the back office), a clear banner appears with a **Sign in** button instead of the app silently showing nothing. Anything you captured offline is kept and syncs after you sign back in.
- **Faster, more reliable first sign-in.** Registering a new account is quicker and no longer leaves you without notifications; if a step is interrupted, tapping **Create Account** again simply finishes the job.
- **Your module tabs come back on their own.** Fleet, Waste, and Site Security tabs that were missing because you opened the app offline now appear automatically once you reconnect.

### Look & feel

- **Smoother screen transitions.** Moving between screens — especially going back — is now a clean, consistent slide instead of the occasional stutter, with an edge-swipe-back gesture.
- **Tidier Home quick actions.** The Quick Actions tiles are now grouped by colour so linked actions read as a set — job-card actions in orange, Ink Factory and Daily Readings in cyan (indigo in earlier 2.2.0 builds), Report a Problem and Daily Check in slate, and Daily Review in gold. On wide screens the tiles stretch across the full width but keep a fixed height, so they no longer balloon and push Recent Job Cards off the bottom. "Daily Safety Check" is shortened to "Daily Check" on the Home tile.
- **A cleaner Home for the gate and admin tools.** **Vehicle at Gate** and **On-Foot Visitor** are no longer Home tiles — reach them from the **Security** tab, where the rest of the gate tools live. The admin **Scan Tester** has moved to **Settings → Admin → Scan Tester**.

---

## 2026-07-03 — "What's changed" after every update

- **The app now tells you what's new.** The first time you open the app after an update, a **What's changed** sheet slides up with the latest release notes — so you don't have to guess what's different. Tap **Got it** to dismiss it (it only shows once per update) or **Full changelog** to read the complete history.
- Brand-new users don't see the sheet on first install — it only appears from your first update onwards.
- The release notes come straight from this changelog, which you can always find under **Settings → Documentation → Changelog**.

---

## 2026-07-02 — Home screen tile grid + login screen polish

### Home screen

- **Quick Actions is now a fixed-column grid** instead of a centre-aligned wrap. Tiles line up in true rows/columns at every screen size (3 columns on phones, 4 on tablets, 6 on desktop/web) instead of the last row centring 1–2 leftover tiles.
- **Every tile is the same size**, including the badge count and the manager-only **Daily Review** tile — previously those two rendered narrower than a plain tile because of a layout bug in how they were stacked.
- **Bigger icons** — tiles now show a larger, more legible icon rather than a small icon lost in a lot of empty tile space.
- **Vehicle at Gate** now shows a car icon instead of the QR-scanner icon (which is also used for the unrelated **Scan Tester** admin tile), mirroring the walking-person icon on **On-Foot Visitor** next to it.
- Off-site disabled tiles (e.g. **Create Job Card**) no longer wrap to a second "(off-site)" line — the existing greyed icon + "location off" badge already communicates the disabled state, and tapping still explains why via a SnackBar.

### Login screen

- The orange perimeter glow around the login screen has been toned down — it was overpowering the branding panel and form.

---

## 2026-06-29 — Site Security docs + guard-shell alignment

### Site Security — documentation

- **New guides:** `security_guard_guide.md` (module hub home, no job-card tiles) and `security_manager_mobile_guide.md` (mobile + Pulse desk split).
- **Screens reference** — Home guard-hub layout + full Site Security screen catalog.
- **Employee / Manager / Executive guides** — security roles and integrated modules (Waste, Site Security, Fleet, Ink).
- **In-app Documentation** — `requiresSecurity` catalog gate; guards no longer see job-card-centric Employee Guide / App Features.

### Engineering

- `wasteSettingsProvider` + `documentation_screen` passes waste + security settings into `docsForUser`.
- `tools/build-docs.ps1` — fixed document title generation on Windows PowerShell.
- `test/doc_catalog_test.dart` — security guard / manager doc filtering.

---

## 2026-06-24 — Waste cross-links (IBC bins + copper) and stock visibility

### Waste — IBC bins from Ink Factory

When an ink operator **consumes an IBC**, the app now auto-adds one **IBC Bins** row to on-site waste stock (identified by IBC number). Security links it on **collection day** via **Begin Collection → From stock**. Voiding ink consumption removes the stock item if it is still on site.

### Waste — Copper ready to sell (managers only)

When copper in the sell bucket reaches **400 kg**, the system auto-creates **Copper Waste** on-site stock (rods/nuggets). Security **managers** see a **Copper ready to sell** panel and the stock inventory; **guards** do not browse inventory but can still **From stock** at collection. Completing cost review on Pulse for a Copper Waste load records the sale in copper transactions.

### Docs & onboarding

- **Waste Recovery Guide** (`waste_user_guide.md`) — updated roles, IBC/copper flows, collection-day linking.
- **Permissions onboarding** — manager vs guard bullets aligned with stock visibility.

---

## 2026-06-23 — Admin layout refresh, Ink capture on mobile, read optimisations

### Admin — Settings first, five tabs, no Job Cards tab

The Admin screen now opens on **Settings** (the tab you use most often). There are **five** tabs — **Settings**, **Employees**, **Structures**, **On Site**, and **Comms** — in that order.

The old **Job Cards** tab (spreadsheet export and bulk delete) has been **removed from the mobile app**. Job card browsing, history, and KPIs live on **CTP Pulse** (`/jobs`) — use the web board for read-only oversight and exports. Mobile Admin stays focused on people, structure, escalation, and comms.

**Employees** is no longer a wide spreadsheet. You get a searchable **card list**: clock number, name, position, department, and an on-site / off-site pill you can tap to toggle. CSV template download, import, and bulk delete sit in a toolbar card at the top. FCM token editing moved into the **Edit employee** dialog (not shown on every row).

**Structures** has a stats row (department / area / machine counts), a search box, and expandable cards per department. Add-new forms for departments, areas, and machines sit in the same card style as Settings. Duplicate names are blocked with a clear message.

### Ink Factory — operators capture on mobile; managers use CTP Pulse

The Ink Factory hub on mobile is **capture-only**: receive stock, meter readings, production, Toloul recovery, IBC register, and stock balances. The old manager tile grid (pending costs, month-end, recipes, corrections, and so on) is **gone from the app**.

Everyone with Ink access now sees a **Management & costing** card that opens **CTP Pulse** (`https://ctp-pulse.web.app/ink`) in the browser — month-end, pending costs, recipes, reports, and adjustments live there. Operators still never see money on mobile; managers do that work on Pulse.

Stock item detail shows a **bounded recent ledger** (last 20 movements) so opening an item does not pull the full transaction history.

### Other user-visible tweaks

- **Waste load detail** — removed the suggested rand estimate; only approved cost values are shown where relevant.
- **Home / job lists** — active job card listening is merged into one stream where possible, reducing duplicate Firestore reads when the home screen is open.

---

## 2026-06-18 — Admin: user feedback tracking board

Admins can now review and track the feedback that staff submit from the **Give Feedback** button on the Home screen.

A new **User Feedback** screen — reached from **Admin → Settings → Feedback** — lists every submission with who sent it and when. For each one you can:

- Set a tracking status: **New → Planned → Implemented → Declined**. Anything submitted before this feature shows as **New** until you triage it.
- Add private **implementation notes** — what you did, what's planned, or why it was declined.
- Filter by status, with live counts, to see at a glance what's still outstanding versus done.
- Delete a submission you no longer need.

The board is **admin-only** — regular staff never see it; they just get the confirmation that their feedback was submitted.

---

## 2026-06-18 — Ink Factory: combined daily readings screen + recovery history

Two quality-of-life improvements for Ink Factory and Lurgi staff.

### Ink meters and Toloul meters combined on one screen

The daily meter capture flow has been simplified. Previously the **Daily Readings** hub showed two separate cards — one for ink meters and one for Toloul meter points — and each opened its own screen. You now land directly on a **single scrollable screen** that shows all ink meters (Yellow, Red, Blue, Black, Gravure Binder) and all Toloul meter points (Recovery and Usage) together.

- One reading date at the top, shared across all entries.
- Enter whichever readings you have — fields you leave blank are skipped, so you can still submit ink-only or Toloul-only readings when needed.
- One **Record readings** button at the bottom submits everything in a single tap.
- The history strip on each card (showing the last few readings) works as before.
- The reset checkbox (for when a meter was zeroed) works as before.

The **Daily Readings** tile on the Lurgi home screen opens this combined screen directly. The **Meter Readings** tile in the Ink Factory hub does the same.

### Toloul Recovery — previous entries shown below the form

The **Toloul Recovery** screen now shows your most recent recovery entries directly below the capture form, so you can see at a glance what was last entered without leaving the screen. Each entry shows the volume, the Lurgi source, the date, and who entered it.

The form also stays open after a successful submit — fields clear and the date resets to now — so back-to-back entries (e.g. morning and afternoon recovery from the same Lurgi) can be captured without navigating away.

---

## 2026-06-17 — More reliable on-site detection + required security update (v2.1.1)

A focused update that makes on-site / off-site detection dependable, gives you a one-tap fix for the phone settings that silently block job alerts, and prepares the app for a server-side security tightening. **This is a required update** — see the note at the end.

### User-facing changes

**More reliable on-site / off-site detection**

The app is now much better at registering when you arrive at and leave the site. Background detection is more consistent, so you receive the job alerts meant for you while you're on site — and they correctly stop once you've left. Behind this, every presence change (the geofence, the 30-minute on-site check, and the check when you open the app) now flows through one consistent path.

**Location & battery health banner**

If a setting that background geofencing depends on gets switched off — **Location set to "Allow all the time"** or the **battery-optimisation exemption** — the Home screen now shows an orange banner warning that your on-site alerts may not work, with a one-tap **Fix**. Android won't always re-show the "Allow all the time" prompt, so Fix takes you straight to the right Settings page when it's needed. The banner clears itself once both are granted.

**Web app — automatic sign-off when idle**

On the web version, if you leave the app open and step away, you're now automatically marked **off-site** after a period of inactivity, or as soon as the browser tab is hidden or closed. This stops managers who leave the dashboard open on a PC from being left showing "on site" after they've gone home. (The web app never marks you on-site by itself — arriving on site is still detected only by the phone.)

**Onboarding shows the real site radius**

The permissions walkthrough now reads the live geofence radius from settings instead of a fixed "800 m", so what new staff are told matches the barrier the admin has actually configured.

**Admin — on-site presence view**

The **On Site** tab in Admin Settings now shows how long each person has been on site, and flags anyone who has been on site for more than **14 hours** so you can check whether their detection has stopped updating. Manually toggling someone on / off-site is now recorded with a timestamp.

### Under the hood (no UI change)

- **One central presence log** — the geofence, the 30-minute check, the app-open check, web inactivity, and admin changes now all write to a single `app_geofence` record, replacing two separate (and partly mismatched) logs. Every adjustment is stored with its source.
- **Server-stamped presence times** — the server now stamps each on-site / off-site change with a trustworthy time and its source, which is what powers the new admin view and the 14-hour flag.
- **Background write prepared for the security update** — the native geofence write now updates only your own presence fields, through a path that stays valid once the server-side lockdown below is switched on.
- **Required update / security tightening** — this build routes employee and job-number writes through server-validated functions, ahead of locking those collections down. **Older versions will stop being able to create job cards and refresh their notifications once the lockdown is switched on shortly — so please update.**

### A note on update frequency

Thank you for bearing with the frequent updates while the app was being built out. The core is now stabilising, so updates will become **much less frequent** from here on.

---

## 2026-06-11 — Job Cards data integrity overhaul + admin upgrade

Mobile app and backend hardening across all data paths, plus a full Admin screen redesign.

### User-facing changes

**Job History is now fully populated**

Closed job cards from April 2026 onwards now have correct close dates. The **Job History** screen, Manager Dashboard KPIs (Avg Resolution Time, Closed Today, Completion %, Overdue counts), and CTP Pulse resolution metrics are now accurate going back to the start of the system. Previously, `closedAt` was never written by the app, leaving those metrics blank.

**Offline create — informative early block**

The Create Job Card screen now checks connectivity immediately on open and before the final save. If you are offline, a full-width red banner appears: *"No connection — technicians cannot be alerted. Move to signal to submit."* The Save button is disabled while the banner is showing. Previously the form could be submitted offline but the notification system was never triggered, meaning technicians had no idea a job existed.

> The Create Job Card tile on the Home screen also shows a greyed disabled state with a reason when you are offline or off-site, instead of silently hiding.

**Sync indicator now works correctly**

The orange sync badge at the top of the Home screen now correctly reflects queued offline writes. Previously it never showed because the indicator was watching the wrong storage key.

**"Assign Self" from notification now works correctly**

Tapping "Assign Self" from a push notification no longer accidentally resets the job to Open status or removes co-assignees. The job correctly moves to In-Progress, the technician is added to the assigned list, and other assignments are preserved.

**Daily Review: mark on view**

A job card is now stamped as reviewed the moment you open it in Daily Review, not when the screen first loads. The pending count decrements one-by-one as you work through the queue.

**Admin — new Comms tab**

Admins have a new **Comms** tab in Admin Settings for sending broadcast update notifications to all employees. A pre-filled message template is provided and can be edited before sending. After sending, a result summary shows how many devices received it, how many are parked for off-site users, and how many have no registered token. Recent broadcasts are listed below.

**Admin — kill-switch in Settings tab**

The Settings tab in Admin Settings now includes an **App Update Control** card with two fields: **Minimum Supported Build** and **Download URL**. Setting a minimum build number blocks any device running an older version on next app launch — the app shows a blocking update screen with the download link. This works as a server-side control independent of Remote Config.

**Admin screen — full design system update**

The Admin screen is fully updated to the app's design system (theme colours, typography, input styles, card surfaces, section headers) and now has six tabs with outlined icons.

### Under the hood (no UI change, affects data reliability)

- **Stream error isolation** — all Firestore list streams now skip corrupted or unparseable documents instead of crashing. One bad document can no longer break the View Jobs, Home, or Daily Review screen for all users.
- **Sync replay fix** — offline edits replayed on reconnect now preserve Firestore `Timestamp` fields correctly. Previously, replayed edits could write ISO date strings that caused every list screen to error.
- **Field-scoped writes** — status changes and assignments now write only the changed fields (`update`) instead of the full document. This prevents concurrent writes from reverting each other's changes.
- **Comments dual-write** — comment and note updates are now written to a structured `commentsLog` array alongside the legacy string field. CTP Pulse reads the structured log for the Jobs table.
- **Bounded queries** — View Job Cards and Daily Review now use per-status server-filtered queries with a page limit instead of streaming every job card. Significantly reduces Firestore read costs on large collections.
- **`onJobCardWritten` audit trigger** — new server-side trigger appends an entry to `job_card_audit` on every job card write, regardless of which client made the change.
- **`onJobCardAssigned` rewritten** — diffs the `assignedClockNos` array to detect actual changes; sends assignment notifications only to newly-added assignees.
- **`closedAt` backfill** — 50 existing closed job cards had `closedAt` populated from `completedAt` via a one-time repair script run 2026-06-11.

---

## 2026-06-10 — WasteTrack production-grade overhaul

### User-facing changes

**New load number format — W-NNNN**

Load numbers are now **global sequential**: `W-0001`, `W-0042`, `W-1500`. They never reset and are unique forever. The old date-bucketed format (`WT-YYYYMMDD-NNN`) has been retired. All new loads receive a `W-NNNN` number automatically; existing loads keep their old number until they are reassigned on next sync.

**Home screen — active loads + last 10 completed**

The Loads tab now shows:
- **All active loads** (Scheduled, Draft, Pending Weighbridge, Pending Cost Review) — no page limit, every in-flight load is always visible.
- **Last 10 completed/cancelled** loads below a divider, ordered by completion date (most recent first).

Previously, a 50-load page limit could silently hide active loads when many completed loads existed.

**Admin cost review — itemized per-item table**

The Review tab now shows a **line-by-line cost breakdown** for each waste item on the load:

| Subtype | Weight | R/kg | Value |
|---------|--------|------|-------|
| Reelends | 320 kg | 0.90 | R 288.00 |
| Slab Waste | 180 kg | 0.85 | R 153.00 |

- **R/kg** is pre-filled from the contractor's rate register when available; leave it blank if unknown and the system will warn with ⚠.
- **Calculated total** (sum of line values) is shown read-only.
- **Approved amount** defaults to the calculated total but can be edited to match the physical accounts document.
- Rates entered or corrected during review are saved back to the rate register automatically for future loads.
- Both the **calculated** and **approved** amounts are stored separately for audit — any discrepancy is visible in CTP Pulse Reports.

**PDF share on completed loads**

On any completed load, tap the **share icon** (↑) in the load detail app bar to generate and share a PDF summary: load number, contractor, driver, itemized weights and costs, weighbridge details, and approval record.

**Offline schedule improvements**

- Loads scheduled while offline are queued and sync automatically when connectivity returns. The load number (`W-NNNN`) is assigned on sync.
- Stock items linked to an offline-submitted collection are also queued — they will not be permanently stuck as *Loaded* if the parent load never reached Firestore.

### Under the hood (no UI change but affects data reliability)

- Deleting a waste item is now a **single atomic transaction** — the load weight and stock status can no longer end up inconsistent if the network drops mid-delete.
- The `updateLoad` operation now correctly queues its payload when offline without leaking `FieldValue.serverTimestamp()` into the local Hive store.
- `deleteWasteItem` blocks with a clear error if offline — supervised admin action, not a field worker action.

---

## 2026-06-05 — Production release: new job types, module toggles, admin improvements

### User-facing changes

**New job types**

- **Building Maintenance** — a new job card type for building faults. Routes directly to the on-site Building Maintenance team and the Workshop Manager. No escalation timer fires — like Maintenance type, it is excluded from the escalation engine.
- **Pre Press Specialist** — a new type visible only when the selected department is "Pre Press". Routes to the on-site Pre Press Specialist and the Workshop Manager. Also excluded from escalation.
- Both new types show a contextual info banner in the Create Job Card form explaining how they are routed.

**Module enable / disable now in Settings**

- Admins can now enable or disable the **Waste Management** module and the **Fleet Maintenance** module directly from **Settings → Modules**. Previously this required navigating inside each module's own admin tab. Turning a module off hides its tab from all users immediately.

**Admin access now Firestore-driven**

- Admin status is now set per user in Firestore (`isAdmin: true` on the employee document) instead of being hardcoded to a single clock number. To grant or revoke admin access, edit the employee's Firestore record — no code change or app release required.

**Waste Management — production release**

- The pilot-mode controls have been removed from the Waste Admin screen. WasteTrack is now a full production module — no clock-number restriction or pilot list.
- The disabled state for Waste now shows a plain "Waste Management is disabled — contact your administrator" message instead of pilot-mode wording.

### Developer / maintenance changes

- **Update service** — In-app update checks now run every 4 hours (was 24 hours). When Remote Config keys are not yet published, the service retries after 1 hour instead of waiting the full interval — prevents a misconfigured RC from silencing update prompts indefinitely.
- **AppColors null crash fixed** — `Theme.of(context).appColors` now falls back to the light theme defaults instead of throwing a null check error when a dialog or route loses the theme extension context. Resolves a Crashlytics crash (1.2.1).
- **USE_FULL_SCREEN_INTENT permission** — The Android 14+ full-screen intent settings redirect has been moved from `MainActivity.onCreate` (which fired on every cold start) to the user-initiated permissions flow inside the app. The system settings page no longer appears automatically on first launch.

---

## 2026-06-04 — Crash fix, in-app docs fixes, Fleet user guide

### User-facing changes

- **Crash fix** — A crash affecting some devices has been resolved. On certain devices, the home screen or daily review screen would crash silently after being opened from the background or after a network disruption. This has been fixed and will no longer occur.
- **WasteTrack User Guide now opens correctly** — The in-app WasteTrack User Guide was showing raw page boilerplate instead of its content. The guide is now bundled correctly and displays as intended.
- **New: Fleet Maintenance User Guide** — A full Fleet Maintenance guide is now available in Settings → Documentation for fleet users (reporters, the Hyster mechanic, cost managers, and admins). It covers reporting forklift/grab faults, logging work, recording costs, and reports. It only appears for users with Fleet access when the module is enabled.
- **Documentation list cleaned up** — Two developer-only references (Cloud Functions Deployment, Firebase Security Rules) that could not open in-app have been removed from the documentation list. They remain available to developers outside the app.

### Developer / maintenance changes

- **Firestore stream `onError` handlers** — Added `onError` callbacks to all five Firestore `.snapshots()` stream subscriptions in `home_screen.dart` (employee stream, open jobs, in-progress jobs, review count) and `daily_review_screen.dart` (all job cards). Previously a `PlatformException(channel-error)` from the Firestore Pigeon transport propagated as an unhandled stream error and crashed the app. The error is now caught, logged to debug output, and the screen remains functional with its last known data.
- **FCM subscription leak fixed** — `FirebaseMessaging.onMessageOpenedApp.listen()` in `HomeScreen` was never stored or cancelled on `dispose()`. Each login session added a permanent listener that accumulated in memory and could trigger `setState()` on disposed widgets. Now stored in `_messagingSubscription` and cancelled in `dispose()`.
- **Landing page — Remote Config driven** — `ctp-job-cards-landing.web.app` now fetches `latest_version`, `latest_build`, `download_url`, and `release_notes` from Firebase Remote Config on every page load. Future releases only require a Remote Config update — no HTML edits or redeployment needed. Fallback values in the HTML ensure the page renders instantly even if Remote Config is unreachable.

---

## 2026-06-03 — CTP Pulse web dashboard: theme & contrast fixes

Web-only update to CTP Pulse (factory board at port 3003). No mobile changes.

### What changed

- **Status badge contrast** — Overtime entry status badges (Pending, Workshop Approved, Approved, Cancelled) now use correctly contrasting colours in both light and dark modes. Previously the coloured text was too light to read in light mode.
- **KPI trend colours** — Declining-trend indicators on KPI cards now correctly show in red (destructive colour). Previously they had no colour at all.
- **Fleet severity labels** — Issue severity labels (Out of Service, High, Medium, Low) in the Fleet page open-issues table now render in legible colours in dark mode.
- **Fleet cost chart** — The "Cost by Category per Asset" stacked bar chart now has correctly themed axis labels, gridlines, tooltip, and legend in dark mode. Previously axis text was near-invisible in dark mode.
- **Native date/select inputs** — Date pickers and dropdown filter selects now follow the app's dark theme; previously the browser rendered them with a white background in dark mode.

---

## 2026-06-03 — Fleet Maintenance module (Hyster forklifts & grabs)

A new **Fleet** tab for tracking forklift and grab maintenance — separate from normal job cards. It appears once an admin enables it in Fleet Settings and you have a fleet role.

### User-facing changes

**New: Fleet tab**

- **Report a problem** — operators and shift leads in the configured departments can report an issue on a forklift or grab: pick the asset, choose severity (Low / Medium / High / Out of Service), confirm the shift (auto-detected), describe the fault, and attach up to 3 photos.
- **Out of Service alerts** — when an asset is reported out of service, the Hyster mechanic and the cost manager(s) get an immediate push notification (or it waits in their notification inbox if they're off-site). The asset shows an orange **OOS** badge everywhere it appears. High-severity issues go to the notification inbox without a push.
- **Mechanic queue & work logging** — the mechanic sees open issues sorted by severity, can **Acknowledge** an issue, then resolve it either by logging the work (work type, labour hours, machine-hour reading, parts used, photos) or with a quick resolution note. Each work record gets a number like `FM-20260603-001`.
- **Costs (managers only)** — the overseeing manager records cost lines per asset (parts / labour / invoice / other, with amount, invoice ref and supplier), views month and year-to-date spend per machine, and exports a full CSV. **The mechanic never sees money** — work records only show a "Costs pending / Costs entered" label.
- **Admin** — the asset register (add/edit forklifts and grabs), reporter departments, cost-manager list, asset/work types, and the module on/off switch all live in **Fleet Settings**.

### Who sees what

| Role | How you're recognised | What you can do |
|------|----------------------|-----------------|
| Fleet Mechanic | Workshop department + "Hyster Mechanic" position | Log work, acknowledge/resolve issues |
| Fleet Reporter | Your department is enabled in Fleet Settings | Report issues, track your own |
| Cost Manager | Your clock number is on the cost-manager list | Enter costs, view reports, export CSV |
| Fleet Admin | System admin | Manage assets and all settings |

### Developer / architecture changes

- New `fleet_*` Firestore collections (`fleet_assets`, `fleet_issues`, `fleet_work_records` + `fleet_work_parts`, `fleet_cost_lines`, `fleet_types`, `fleet_settings`, `fleet_counters`, `fleet_audit`). Same signed-in auth model as WasteTrack; role enforcement is client-side.
- Cloud Functions in the monorepo `firebase/functions` codebase: `createFleetWorkRecord` (atomic FM-number), `onFleetIssueCreated` (OOS notifications + asset badge), `onFleetIssueUpdated` (clears badge on resolve).
- CTP Pulse gains a **Fleet Maintenance** board module (open issues, work hours MTD, cost MTD, avg resolution time) plus a `/fleet` detail page with cost-by-asset and cost-by-category charts and a live open-issues table. Access via the `fleet` board module in `/admin/users`.
- See `docs/architecture/visualization.md` for the full role/screen matrix and `docs/COLLECTIONS.md` for the schemas.

---

## 2026-06-03 — Job Card History screen, Firestore read cost fixes

### User-facing changes

**New: Job Card History screen**

- A dedicated **Job History** quick-action tile is now on the Home screen for all roles.
- The screen lets you search the full closed job card archive without streaming the entire collection — only the records matching your filter are downloaded.
- **Server-side filters**: date preset (Last 7 / 30 / 90 days, custom range, or all time), department, area, and machine. Each change triggers a fresh Firestore fetch capped at 50 records per page. Use **Load More** for pagination.
- **Client-side refinement** (no extra reads): Type chips (Mechanical / Electrical / Mech-Elec / Maintenance), Priority chips (P1–P5), and free-text search across description, machine, part, notes, and operator.
- Tap any result to open the full Job Card Detail screen.

**Create Job Card — similar jobs panel**

- The "previous jobs for this machine" sidebar previously downloaded every job card in the system and filtered on-device. It now uses server-filtered indexed queries — only the records that match the current department → area → machine → part selection are fetched.

### Developer / architecture changes

- **`FirestoreService.getInProgressJobCards()`** — new server-filtered stream for `status == inProgress` jobs.
- **`FirestoreService.searchClosedJobCards()`** — new one-shot fetch with server-side equality filters (department, area, machine) and an optional date range on `closedAt`, plus cursor-based pagination. Type and priority filtering applied client-side on the returned page.
- **Home screen count badge** — the two `getAllJobCards()` live listeners used to count the open/in-progress badge and render the recent jobs panel have been replaced with `getOpenJobCards()` + `getInProgressJobCards()` streams. Closed documents are never downloaded to the home screen.
- **`closed_jobs_screen.dart` removed** — superseded by `job_card_history_screen.dart`.
- **3 new Firestore composite indexes** in `firestore.indexes.json`: `status + department + closedAt DESC`, `+ area`, `+ machine`. Required for the server-side history queries. Deploy with `firebase deploy --only firestore:indexes`.

---

## 2026-06-02 — WasteTrack UX overhaul, notification inbox fixes

### User-facing changes

**WasteTrack home screen**

- **Live updates** — The load list now updates automatically in real time. You no longer need to pull down to refresh; new or updated loads appear as soon as they change.
- **Actions moved to overflow menu** — The toolbar buttons (Pending Weighbridge, Reports, Waste Admin, Enable/Disable toggle) are now grouped under a **⋮ More actions** menu at the top right. The cloud sync retry button remains visible at all times when there are queued items.
- **Filter empty states** — When the Today or This Week filter returns no results, the screen now shows a clear "No loads match" message with a tap-to-clear button instead of a blank list.
- **Contractor name on scheduled load cards** — Incoming scheduled load cards now show the contractor's display name instead of the internal contractor ID.

**WasteTrack load detail screen**

- **Waste items now listed** — The load detail screen now shows all waste items in the load (subtype, weight, photo count) directly on the page. Previously you could not see the item breakdown from the detail view.
- **Status progress stepper** — A four-step progress bar (Created → Signature → Weighbridge → Complete, or Scheduled → Collecting → Weighbridge → Complete for two-phase loads) is shown at the top of the detail screen so you can see at a glance where the load is in its lifecycle.
- **Weighbridge action banner** — When a load is in **Pending Weighbridge** status, a highlighted amber banner now appears at the top of the screen prompting the manager to enter the weighbridge weight. Previously this was easy to miss.
- **Collector name shown** — The "Collected by" field now shows the guard's name instead of their clock number.

**WasteTrack create load flow**

- **Opens load detail after saving** — After creating a new load, the app now navigates you directly to the load detail screen. You can immediately capture the driver signature without going back to the home screen to find the load.
- **Waste type icons** — The waste type selection grid now shows category-specific icons (hazardous, recyclables, cardboard, metal, e-waste, organic) instead of a generic trash icon for every type.
- **Add item is a slide-up sheet** — The "Add Waste Item" form is now a slide-up bottom sheet instead of a pop-up dialog. This is more stable when the camera is involved and easier to use on smaller screens.

**WasteTrack begin collection**

- Same camera-stable slide-up sheet for adding waste items during collection (consistent with create load flow above).

**Notification inbox**

- **On-site status indicator in app bar** — The notification inbox screen's app bar now shows the same orange → green (on-site) / orange → red (off-site) gradient as every other screen in the app.

### Developer / architecture changes

- **Firestore rules: notification_inbox added** — The `notification_inbox/{clockNo}/items` subcollection was missing from the Firestore security rules, causing permission denied errors when the Flutter app tried to read or mark inbox items. Rule added to the Job Cards tier. Deployed to production.
- **`WasteLoad` model: `contractorName`, `collectedByName` fields** — Both are now stored on the load document at creation/collection time and read back for display, avoiding secondary lookups.
- **`WasteService.getLoad()`** — New method for fetching a single load by ID, used by the post-creation navigation.

---

## 2026-06-01 — WasteTrack module, offsite notification inbox, admin on-site view, settings redesign

### User-facing changes

**WasteTrack — Waste Management Module**

A full waste management module is now integrated into the app for Security department staff. Accessible via the **Waste** tab in the bottom navigation bar (only visible to Security Manager, Security Guard, and Admin roles).

- **Security Manager** — Schedule waste loads with contractor, waste type, and date. Edit or cancel scheduled loads before collection begins. Review completed loads and deviation reports. Export CSV reports by date range.
- **Security Guard** — Begin collections for scheduled loads. Add waste items with recorded weights and photos. Capture the contractor's on-screen signature. Enter the actual weighbridge weight after the truck returns from the external scale.
- **Deviation alerts** — When the difference between the recorded weight and the actual weighbridge weight exceeds 5% or 50 kg, the load is flagged for manager review.
- **Load numbering** — Each load is assigned an automatic daily sequence number (format: WT-YYYYMMDD-NNN).
- **Admin** — Full WasteTrack configuration panel: manage waste types, sub-types, cost rates, and contractor records.

**Offsite Notification Hold (Notification Inbox)**

- **Notification Inbox** — Notifications are no longer sent as push alerts when you are off site. Instead they are held in a new **Notification Inbox** (bell icon in the top bar). Unread items show a live count badge. When you come back on site and open the app, a banner tells you how many are waiting. Tap any item in the inbox to open the related job card and mark it as read.

- **Notifications affected by offsite hold** — All of the following are now held rather than pushed when the recipient is off-site:
  - Job assignment (assigned directly by a manager while you are off shift)
  - Job completion and update acknowledgements (sent back to the person who raised the job)
  - "I'm Busy" responses from technicians (sent back to the job creator)
  - Copper sell threshold alert (for authorised users only)

**Admin & Settings**

- **Admin — On Site tab** — A new **On Site** tab in Admin Settings shows every employee currently marked on-site, grouped by department, updating in real time. Useful for supervisors to see who is available on the floor.

- **Admin — Employee list** — The `isOnSite` column in the employee table is now a green **"On Site"** / grey **"Off Site"** status chip. Tapping the chip toggles the employee's status directly — no need to open the edit row.

- **Settings screen redesigned** — Reorganised into labelled sections: Your Profile, Preferences, Notifications, App & Connectivity, App Permissions, Admin, Account. Notification test buttons moved to a dedicated sub-screen (Settings → Notifications → Notification Tests) to reduce clutter.

- **Admin settings — Tab icons** — All five admin tabs now display an icon alongside the label for faster navigation.

- **Waste screens — contrast fixes** — Several waste screens had light-grey text or icons that were hard to read on white backgrounds:
  - Weight boxes on the load detail screen now use dark text when no weighbridge data has been entered (was grey-on-grey).
  - Disabled-state block icons across create, home, and reports screens are now a darker grey.
  - The empty items placeholder in the begin-collection screen has a more visible border.

### Developer / architecture changes

- **WasteTrack collections** — 11 new Firestore collections added under the `waste_` prefix (see `lib/constants/collections.dart`).
- **`createWasteLoad` Cloud Function** — Callable function in `africa-south1` handles atomic load creation and daily sequence numbering.
- **`lib/constants/collections.dart`** — New canonical constants file for all Firestore collection names. All services now use constants instead of inline string literals.
- **Functions codebase named `jobcards`** — Deploys from this repo are now scoped to Job Cards functions only; cannot accidentally wipe WasteTrack/Overtime functions in the shared Firebase project.

---

## 2026-05-23 — Dashboard overhaul, screen consistency, and UI improvements

### User-facing changes

- **Manager Dashboard rebuilt** — department and date-range filters are now displayed above the KPI section. Nine KPI cards replace the previous four: Open Jobs, High Priority (P4–P5), Monitoring, Closed Today, Pending Assignment, Avg Resolution Time, Overdue >3 days, Overdue >7 days, and Completion %. Every KPI card that represents a job list is now tappable — tapping it opens a filtered list of exactly those jobs. KPI section is collapsible. Priority breakdown bar chart labels updated to P1 Low / P2 Med / P3 Mid / P4 High / P5 Crit.
- **Manager Dashboard analytics** — technician leaderboard replaced with a **Team Performance table** showing each technician's closed count, average resolution time, and currently assigned count. New **Open Jobs by Day** area chart shows the last 30 days of open job stock, department-filtered. Trendline chart now includes a legend.
- **Daily Review: responsive layout** — on narrow screens (< 700 px) the list and detail panels stack vertically with a back-navigation button. On wider screens both panels display side by side.
- **Daily Review: date range filter** — the two separate date pickers have been replaced with a single date-range picker. The selected range is shown as a deletable chip.
- **Daily Review: Monitor status badge** — the Monitor badge colour changed from green to amber to better reflect "watch" state (not yet resolved).
- **Daily Review: tab switching** — switching between Pending and Reviewed tabs now clears the selected card and any text in the input field.
- **Unified gradient app bar** — every screen now shows a gradient app bar: orange on the left fading to **green** when the current user is on-site, or **red** when off-site. This provides a persistent on-site status cue across the entire app.
- **Tab bars moved into body** — on View Job Cards and Job Card Detail the tab bar is now part of the scrollable body, not pinned to the app bar chrome.
- **Login screen** — left panel background changed to pure black.

---

## 2026-05-21 — Job card detail redesign, onboarding fix, off-site gate, docs accuracy pass

### User-facing changes

- **Job card detail screen redesigned** — unified tile layout, streamlined sections and visual hierarchy across the Details, Assignment, and Timeline tabs.
- **Home screen: Create Job Card tile hidden when off-site** — employees whose `isOnSite` flag is `false` no longer see the Create Job Card tile. This prevents creating jobs while off-site without overriding the on-site check.
- **Registration now routes through onboarding** — first-time registrants are routed through the full 7-page `PermissionsOnboardingScreen` (same as existing users) so location monitoring and permission grants happen immediately after account creation.
- **Unified job card tile** — `JobCardTile` widget refactored for consistent display across Home recent-jobs list, ViewJobCards, MyAssignedJobs, ClosedJobs, and DailyReview.

### Documentation corrections

- **Permissions onboarding**: corrected page count from 3 to 7; listed all pages (Welcome, Your Role, Job Card Flow, Job Status, Priority Levels, Escalation, Grant Permissions).
- **View Job Cards**: role corrected from "Manager, Admin" to "All" — operators and technicians can browse job lists.
- **Role-Based Visibility** section: corrected inference order (Admin → Manager → Technician → Operator catch-all); removed incorrect "Technician = anyone else" statement.
- **CLAUDE.md**: added `utils/` to architecture tree; documented all 4 Riverpod providers; added missing services (`ConnectivityService`, `JobAlertService`, `UpdateService`); expanded Cloud Functions inventory to all 13 functions; fixed Manager role key screens (removed non-existent "NotificationHistory", added MonitoringDashboard and DailyReview).

---

## 2026-05-18 — Documentation portal, role-aware onboarding, accuracy pass

### New for users

- **One docs portal** — `docs/index.html` is the single entry point. Sidebar nav links to every guide (employee, manager, executive, app features, escalation, screens, troubleshooting). Open it in any browser.
- **Role-aware onboarding** — first-login carousel now branches on your role (Technician / Manager / Operator / Admin). The shared pages on P1–P5 priorities, escalation, and permissions stay the same for everyone — that's the part everyone needs to know.
- **P1–P5 explained explicitly** — onboarding now shows all five priority levels with the exact notification behaviour (banner / persistent / full-screen alarm) tied to each.
- **4-stage escalation diagram** — onboarding includes a stage-by-stage walkthrough with the actual defaults (5 / 10 min enabled; 30 / 60 min disabled, configurable by Admin).

### New for admins

- **Three new docs** —
  - [Cloud Functions deployment guide](cloud_functions_deployment.md) — function inventory, two-region layout (`africa-south1` + `europe-west1`), deployment commands, common failure modes.
  - [Troubleshooting & FAQ](troubleshooting.md) — symptom-driven fixes for notifications, geofence, sync, login, and escalation.
  - [Firebase security rules guide](firebase_security_rules.md) — what `storage.rules` enforces, what Firestore rules *should* enforce, action items for tightening.

### Documentation toolchain

- **Markdown is now the single source of truth.** Every doc lives as `.md` first; HTML and PDF are generated by `tools/build-docs.ps1`. To update a guide: edit the `.md`, run the script, commit all three.
- **Backfilled orphans** — `app_features.html`, `escalation_system.html`, `screens_reference.html` now have corresponding `.md` files so future edits go through markdown.
- **CI workflow** — `.github/workflows/docs.yml` regenerates and validates HTML on every PR.

### Accuracy fixes

- `CLAUDE.md` — escalation corrected from 3-stage to 4-stage; the `Employee.role` field reference removed (role is inferred from `position`); region split between `africa-south1` and `europe-west1` documented.
- Role guides — escalation defaults corrected to 5 / 10 / 30 / 60 min with stages 3 and 4 disabled by default (previously documented as 2 / 7 / 30 / 60 with all enabled).
- `manager_guide.md` — Daily Review (web) added; previously undocumented.

### Removed

- `migrate.html` — orphan build artifact at repo root, not linked anywhere.

---

<!-- Add new entries above this line. Keep entries scoped to a single release. -->
