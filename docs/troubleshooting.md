# Troubleshooting & FAQ

This guide covers the most common symptoms users hit in production and the fastest fix path for each. Sections are grouped by what the user sees, not by component.

---

## Home screen is empty or incomplete after signing in

### Symptoms

- You signed in but Home shows no jobs, no counts, and no inbox badge
- After tapping an **arrived on-site** notification, Home is missing Fleet/Security tabs, quick-action tiles, or Recent Job Cards (skeleton placeholders that never fill in)
- It used to only fix itself after force-closing and reopening the app

### What the app now does automatically (v2.3.0 onward)

1. **Self-healing data streams** — if a live list is refused right after sign-in (a brief permissions/timing race while your access token catches up), the app refreshes your access and retries in the background with a short backoff. It also re-tries whenever your connection returns or you switch back to the app. You should see the screen fill in within a few seconds without doing anything.
2. **Resume hydration** — when you open the app from the background (including after a geofence notification), Home refreshes your on-site status, module settings (Fleet, Waste, Security tabs), and job-card streams so tiles and lists match reality without a restart.
3. **Offline vs empty** — an empty list from a cold start now shows **"Waiting for connection…"** with placeholders, not "No recent jobs". If you genuinely have no jobs, it says so only once the server has confirmed it.
4. **Session-expired banner** — if the emptiness is because your sign-in has lapsed (signed out elsewhere, account disabled/changed), a red **"Session expired — sign in again"** banner appears at the top of Home. Tap **Sign in**. Your queued offline work is preserved and syncs after you re-authenticate.

### If it's still empty or incomplete

1. Check the signal and the sync badge at the top of Home (see "Sync stuck" below).
2. Pull the app to the foreground / background once — this re-arms the retries, permission re-checks, and resume hydration.
3. If a **"Your account is no longer active"** banner shows, your employee profile was removed on the back office — contact Admin.
4. As a last resort, sign out (Settings → Sign out) and back in.

---

## App update banner or force screen

### Symptoms

- Orange **Update available** banner on Home, or a full-screen **must update** screen
- Wrong people got forced / nobody got the offer
- “Later” stopped the banner but you want it back

### What the app does (v2.3.0+ with channel builds)

1. **Soft** offers show a **banner** only (not a blocking dialog). **Update** installs in-app; **Later** snoozes ~**24 hours** (banner can return for the same build after the snooze).
2. **Force** (per publish channel) is full-screen; the app **re-fetches on every resume** so a new force is not stuck behind an “up to date” cache for 24h.
3. **Who is targeted** is decided by Admin channels: People (clock list) → Departments → Default. Channel match re-runs when the employee profile loads if it was missing at first open. See `docs/admin_app_update_guide.md`.
4. **Kill-switch** (`min supported build`) blocks **everyone** below that build at launch — different from channel force. Needs a download URL (shared or channel fallback).

### Check, in order

1. **Settings → Check for update** — shows channel, force flag, URL, current vs latest build.
2. **URL should be Hosting**, not App Distribution:  
   `https://ctp-job-cards-landing.web.app/releases/latest.apk`  
   On **build 147+**, Admin/Firestore is read first; RC only fills empty fields. Older builds could keep a stale RC App Distribution URL — upgrade or set Shared download URL and Save. Diagnostic shows **Config source** (`firestore:…` vs `remote_config`).
3. Confirm Admin published the right channel and selected the right departments/people (list pickers, not free text).
4. Confirm your `employees.department` matches a selected department (e.g. `Ink Factory`).
5. Confirm Default build is **not** equal to a Departments force build if you only meant to force one dept (old APKs only read Default).
6. Install the APK URL manually once if download fails (network / “install unknown apps” permission). See `docs/RELEASE_PLAYBOOK.md`.

---

## Notifications not arriving

### Symptoms

- You're on site but didn't get an alert for a P3+ job in your trade
- Other technicians did get it
- Manager dashboards show the job was created and alerts were sent

### Check, in order

1. **Notifications permission** — Settings → Apps → CTP Job Cards → Notifications → "Allowed". On Android 13+, the app must hold `POST_NOTIFICATIONS`.
2. **Battery optimization** — Settings → Apps → CTP Job Cards → Battery → Unrestricted. Aggressive battery savers (Samsung, Xiaomi, Huawei) kill background FCM listeners after a few minutes idle. This is the #1 cause.
3. **DND bypass** — for P4/P5 to break through Do Not Disturb, the app needs DND access. Settings → Sound & Vibration → Do Not Disturb → App exceptions.
4. **FCM token registered** — open Settings inside the app and tap "Refresh FCM Token". If the token is null or stale, the Cloud Function has no way to reach you.
5. **On-site status** — geofencing only alerts on-site technicians. If you're showing as off-site when you're physically on site, see "Geofence not triggering" below.
6. **Home health banner** — if orange "On-site alerts may not work" (or "Some alerts may not reach you") appears at the top of Home, tap **Fix** and grant every listed permission. Settings → App Permissions shows the same six checks with a **Fix all permissions** button.

If all of those check out, ask Admin to look at the `notifications` Firestore collection — it logs every send attempt and lists exactly which clock numbers were targeted. Admin can send a **targeted broadcast** (Admin → Comms → Targeted Message) to specific clock numbers asking users to fix permissions.

---

## Full-screen P5 alarm not firing

### Symptoms

- P5 jobs arrive as a regular banner instead of a screen-takeover with loud alarm
- The phone is on silent or DND when the alert should bypass

### Check, in order

1. **"Display over other apps" / System Alert Window** — Settings → Apps → CTP Job Cards → Special access → Display over other apps → Allow. Without this, the lock-screen takeover falls back to a banner.
2. **Schedule exact alarms** — Settings → Apps → Special App Access → Alarms & Reminders → CTP Job Cards → Allow. P5 uses the exact-alarm API; without it the alarm fires late or not at all.
3. **DND bypass** — see Notifications section.
4. **Lock screen notifications** — Settings → Notifications → Lock screen → Show all content. Some OEMs hide content by default.
5. **Sound profile** — even with bypass granted, some firmware mutes alarms in DND. Test by setting DND on and running the in-app "Test P5 Full Screen Alert" button on the Permissions onboarding page.

---

## Geofence not triggering

### Symptoms

- Walking onto site doesn't flip you to on-site
- You never receive job alerts even with all other permissions granted

### Check, in order

1. **Location permission level** — must be "Allow All the Time", not "Only while using the app". Background location is the *only* thing that triggers the geofence when the screen is off.
2. **Location services on** — phone-wide location switch must be enabled.
3. **Geofence radius** — the active geofence is ~400 m around the configured centre (live value comes from Admin geofence settings). If you're outside it, you're correctly off-site; the radius can be reconfigured by Admin via the **Geofence Editor** screen.
4. **Re-registration after reboot** — Android removes geofences on device reboot. The app re-registers on next launch; if you rebooted and didn't open the app, do so once.
5. **Force-refresh location** — Settings → "Check Current Location" button. This calls `LocationService.checkCurrentLocation()` and updates `isOnSite` immediately.

If the geofence still doesn't fire, Admin can check the device's reported lat/lng in the `employees` document — that confirms whether the OS is even sending location updates.

---

## Job card creation blocked — "No connection" banner

### Symptoms

- The Create Job Card screen shows a red banner and the Save button is disabled
- The Create Job Card tile on the Home screen is greyed out

### What this means

Creating a job card while offline would mean no technicians are notified. The app intentionally blocks submission until connectivity is restored — the job would be invisible to the system otherwise.

### Fix

Move to an area with network signal (Wi-Fi or mobile data). The banner dismisses automatically when connectivity is detected and the Save button re-enables. Your form entries are preserved — you will not lose anything.

If the banner appears even though you have signal, check that mobile data or Wi-Fi is actually connected (not just "on") and that airplane mode is not active.

---

## Job cards not syncing

### Symptoms

- You updated a job but the change doesn't appear for others
- Closure note didn't save after going offline
- The orange sync badge is showing

### Check, in order

1. **Connectivity indicator** — the sync badge at the top of the Home screen shows a yellow/amber state when writes are queued and pulsing when actively syncing. If it has been stuck for more than a minute with a signal, continue below.
2. **Sync queue contents** — Settings → Diagnostics → "View Sync Queue" (admin/dev only) lists pending writes in the Hive `sync_queue` box.
3. **Force-sync action** — tap the sync badge to manually flush. `SyncService` listens to `connectivity_plus` and replays on reconnect, but the manual trigger is faster than waiting.
4. **Firebase Auth session** — if your session expired, writes will fail silently and stay queued. Sign out and sign back in.

If writes stay queued indefinitely, check Firestore security rules (Admin) — a rule rejection looks like a network error from the client.

---

## "Access denied. Manager role required"

### Symptom

- Dashboard tab shows the access-denied message instead of the dashboard

### Cause

Role is **not** a stored field — it's inferred from `Employee.position`. The Dashboard tab is gated by `position.toLowerCase().contains('manager')`. If your position string doesn't contain the word "manager" (case-insensitive), you're treated as a non-manager.

### Fix

Ask Admin to update your `position` field in the `employees` Firestore collection. Common examples that work:

- `"Production Manager"` ✓
- `"Workshop Manager"` ✓
- `"Manager - Electrical"` ✓

Examples that **don't** work even though they look manager-ish:

- `"Supervisor"` ✗ (no "manager" substring)
- `"Foreman"` ✗
- `"Team Lead"` ✗

If your role is in this grey area, talk to Admin about whether to extend `lib/utils/role.dart` to recognise it.

---

## Login fails / "No employee profile found"

### Symptoms

- Firebase Auth accepts the password
- App immediately shows "No employee profile found. Please register first."

### Cause

The `employees` collection is queried by `uid` (Firebase Auth UID). If your employee document exists but has no `uid` field, or has the wrong `uid`, the lookup fails.

### Fix

Admin needs to set the `uid` field on your `employees/{clockNo}` document to match your Firebase Auth UID. The Firebase Console → Authentication tab shows the UID for each user account.

If the document doesn't exist at all, use the Registration screen to create one.

---

## Escalation didn't reach me even though I'm a manager

### Symptoms

- A job hit Stage 2 escalation and the dashboard logged it
- You're on-site and have the right position, but you didn't get an alert

### Check, in order

1. **`notification_configs/global.stages.stage2.enabled === true`** — Admin can check this in the Admin → Escalation Config tab.
2. **Stage 2 recipient rules include your role** — typical Stage 2 rules: `onsite_dept_managers`, `onsite_workshop_manager`. If you're a general manager and only dept managers are listed, you won't be notified.
3. **`enabled_at` is in the past** — if Admin recently changed Stage 2's recipients, the function skips jobs created before `enabled_at` so the new recipients aren't blasted with backlog.
4. **You're recorded as on-site** — recipient rules with the `onsite_` prefix filter by `isOnSite == true`. Geofence section above.

---

## Operator follow-up alerts

### What they look like

> "No response yet — Job #123. 10 minutes passed with no assignment. We've notified 4 people. Follow up directly."

### What they mean

These are sent to the operator who created the job, at each escalation stage, *regardless* of whether the operator is on-site. They are informational — the operator doesn't need to do anything in the app, but they can phone or radio someone directly if the job is critical.

### Disabling for a specific job type

Add the job type to `excluded_job_types` in `notification_configs/global`. The Cloud Function skips initial notification *and* all escalation stages for excluded types. Common example: `"maintenance"`.

---

## Where to look when nothing else works

- **`notifications` Firestore collection** — every notification ever sent, with `sentTo`, `level`, `priority`, and timestamp. Authoritative log.
- **`job_card_audit` Firestore collection** — append-only log of every job card mutation, with who and when.
- **Firebase Console → Functions → Logs** — `escalateNotifications` logs each stage's query results; useful for tracing why a job did or didn't escalate.
- **`memory-bank/learnings.md`** (if present) — running list of gotchas the team has hit before.
- **Diagnostics screen inside the app** — surfaces FCM token, on-site status, last geofence event, and sync queue size in one place.
