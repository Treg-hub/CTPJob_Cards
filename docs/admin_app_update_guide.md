# Admin guide — App Update Control (in-app APK)

**Who this is for:** Admins who publish Job Cards Android APKs from **Settings → Factory Admin → Overview → App releases**.  
**Audience:** Operators install via **in-app download** (not Play Store).  
**Last updated:** 2026-07-09 (targeted channels, soft banner, department/people pickers).

---

## What this screen does

You control which devices are **offered** or **forced** to install a new APK **without** sideloading by hand for every phone.

| Concept | Meaning |
|---------|---------|
| **Soft update** | Home shows an **orange banner** (Update / Later). User can keep working. **Later snoozes ~24 hours** (banner returns after that for the same build). |
| **Force update** | **Full-screen** block until they install. Back button blocked. **Re-fetches on every app resume** (and cold start) so a force publish is not delayed by the soft 24h check window. |
| **Kill-switch** | `Min supported build` — **everyone** below that number is blocked **at app launch**. Use only for broken builds factory-wide. Download URL: shared `updateDownloadUrl`, else default/channel URLs. |
| **Channel** | A named offer (Default / Departments / People) with its own version, build, notes, URL, and force flag. |

**In-app install path:** device downloads the APK URL → system installer (same as before). Shared URL falls back if a channel has no URL of its own.

---

## Channels (who gets what)

Match order on the phone (**first match wins**):

1. **People / pilot** (`testers`) — selected people and/or departments  
2. **Departments** (`ink`) — selected departments and/or people  
3. **Default** (`default`) — everyone else  

| Channel (UI label) | Stored id | Typical use |
|--------------------|-----------|-------------|
| Default (factory) | `default` | Normal factory soft release |
| Departments | `ink` | Force/soft **Ink Factory** (or any depts) without forcing everyone |
| People / pilot | `testers` | Dev/pilot clocks (highest priority) |

### Selecting who

**Do not type free-text lists.** Use:

- **Select / Edit → departments** — multi-select from **live employees + factory structure**. Shows headcount per department.  
- **Select / Edit → people** — multi-select from the **employee list** (search name, clock, department, position). Chips show `Name (clock)`.

Both channels can use **both** department and people pickers.

Department names must match `employees.department` (e.g. `Ink Factory`), case-insensitive.

---

## Step-by-step workflows

### A. Soft release for the whole factory

1. Build APK, host it at a stable HTTPS URL.  
2. **Shared download URL** = that URL.  
3. **Default** enabled: set version + build, notes optional, **Force = off**.  
4. Leave Departments / People **disabled** (or not forced).  
5. **Save publish**.  
6. Optional: **Copy RC keys** into Firebase Remote Config (Default only).  

**Users:** soft banner when behind; can Later.

### B. Force update **only** Ink Factory (or other depts)

1. Host the APK.  
2. Keep **Default** build **lower** than this APK (or Default not forced) so old phones factory-wide are not forced via legacy fields.  
3. Enable **Departments** channel.  
4. **Select departments** → tick `Ink Factory` (and others if needed).  
5. Set version/build (higher than Default), notes, Force **on**.  
6. **Save publish**.  

**Users:**

| Who | New APK (channel-aware) | Old APK (legacy only) |
|-----|-------------------------|------------------------|
| Ink Factory dept | Forced if behind | Only sees Default — **not** forced by this channel |
| Other depts | Unaffected by this channel | Same |

### C. Dev / pilot group only

1. Enable **People / pilot**.  
2. **Select people** from the employee list (and/or departments).  
3. Set version/build, Force on or off.  
4. Save.  

These users win over Departments and Default.

### D. Retire a broken APK for **everyone**

1. Set **Min supported build** to the first **good** build number.  
2. Ensure shared download URL is set.  
3. Save.  

This is **not** a substitute for Ink-only force. It blocks **all** devices below that build at launch.

---

## Checklist before Save publish

1. Bump `pubspec.yaml` version/build and prepend `docs/CHANGELOG.md` with `(build N)`.  
2. Build release APK and upload to the URL you will publish.  
3. Optional SHA-256 for integrity check on download.  
4. Configure the right **channel(s)** and pick departments/people from lists.  
5. **Save publish**.  
6. Optional: paste **Copy RC keys** into Remote Config (Default channel only).  
7. Raise **min supported build** only when retiring bad builds factory-wide.  

**Warning dialog:** if Departments force build equals Default build, the form warns that **old APKs** (which only read Default) may prompt the whole factory. Prefer a higher Departments-only build, or keep Default lower.

---

## How devices check

| Event | Behaviour |
|-------|-----------|
| Home open (cold) | Network check; re-check once employee clock/dept is available (targeted channels). Soft banner or force screen. |
| App resume | **Always re-fetches** (no 24h skip) so newly published force still blocks. |
| Soft “Later” | Snoozes soft banner ~**24 hours** only (not permanent for that build). |
| Force still needed | Full-screen again after check; back blocked until installed. |
| Kill-switch | Every cold start before login; URL from shared field or channel fallback. |
| Settings → Check for update | Immediate check + diagnostic (channel, force, URL); clears soft snooze. |

---

## Data written (`settings/app`)

| Field | Role |
|-------|------|
| `updateDownloadUrl` | Shared APK URL fallback |
| `updateChannels.default` / `.ink` / `.testers` | Per-channel offer + `match.departments` / `match.clockNos` + `forceUpdate` |
| `publishedLatest*` + `publishedForceUpdate` | **Mirror of Default only** — old clients |
| `minSupportedBuild` | Launch kill-switch (everyone) |

Clients: `UpdateService`, `update_channels.dart`, `UpdateAvailableBanner`, `UpdateAvailableScreen`, `ApkInstallService`.

---

## Do / don’t

| Do | Don’t |
|----|--------|
| Use list pickers for depts/people | Rely on free-text clocks/depts (removed) |
| Keep Default lower when forcing one dept | Set Default force = same as Ink force for “Ink only” |
| Use kill-switch for broken APKs | Use kill-switch for module-only releases |
| Test with People/pilot first | Force Default accidentally during a pilot |
| Set **Shared download URL** before raising min build | Rely only on a channel URL for factory-wide kill-switch without verifying fallback |

---

## Release checklist (every new APK)

Use this every time you ship a Job Cards Android build.

### A. Before you build

1. Bump `pubspec.yaml` `version: X.Y.Z+BUILD` (build number must increase).
2. Prepend `docs/CHANGELOG.md` with a user-facing `## … (build N)` entry — exact build number in the heading (e.g. `(build 145)`), not only `136+`.
3. Confirm `CHANGELOG.md` is listed under Flutter assets (already wired) so What’s new ships in the APK.
4. Note anything that needs **force**, **soft**, **pilot-only**, or **kill-switch**.

### B. Build & host (official landing APK)

**Canonical download URL** (first install + in-app update):

```text
https://ctp-job-cards-landing.web.app/releases/latest.apk
```

Landing page: one **Download app** button + QR → that file. Auth is **in the app** (Create account / Login), not App Distribution.

5. Build the **release APK** (same signing key as previous installs):
   ```powershell
   cd mobile\CTPJob_Cards
   flutter build apk --target-platform android-arm64 --release
   ```
6. Assemble landing + copy APK + deploy Hosting:
   ```powershell
   # One-shot (from mobile/CTPJob_Cards):
   pwsh .\scripts\publish-landing-apk.ps1
   # Or manually:
   node build-landing.js
   # (build-landing copies app-release.apk → landing-deploy/releases/latest.apk if present)
   firebase deploy --only hosting:landing --project ctp-job-cards
   ```
   **Order matters:** `build-landing.js` wipes `landing-deploy/`; the APK is copied at the end of that script only if the release APK already exists.
7. Confirm the URL downloads ~45–50 MB in a browser (not 404 / not App Distribution login).
8. Optional: SHA-256 of the APK for Admin integrity check. Install that APK once on a test phone.

### C. Publish in Admin (App releases)

9. Set **Shared download URL** to  
   `https://ctp-job-cards-landing.web.app/releases/latest.apk`  
   (same every release if you keep overwriting `latest.apk`).
10. Configure the right **channel**:
    - Soft factory → Default, Force **off**
    - One dept → Departments channel + list pickers; keep Default build **lower** if others must not force
    - Pilot → People channel first
11. Version + build on the channel must be **newer** than devices you want to prompt (`X.Y.Z` and build number).
12. Paste release notes (short; What’s new sheet still uses bundled CHANGELOG).
13. **Save publish**.
14. Optional: **Copy RC keys** into Remote Config (Default only — cohorts are Firestore).

### D. Verify before wide rollout

15. **Settings → Check for update** on a pilot phone: channel, force, URL, current vs latest.
16. Soft: banner → Update → download → allow install if prompted → system installer → reopen → **What’s changed** once.
17. Soft: **Later** → banner gone ~24h; after snooze (or next day) soft offer can return; Settings check still works anytime.
18. Force (pilot channel): full-screen, back blocked; background app → resume → still blocked until installed.
19. Cold kill + reopen while force active → still blocked.
20. If using kill-switch: set **Min supported build** only after shared URL works; open an older APK and confirm download/install path (not empty URL).
21. **Kiosk / gate tablet**: exit kiosk → update → re-enter lock task.
22. Smoke login + Home + one module the release touched.

### E. After release

23. Watch Crashlytics for `update_check_*` / install errors.
24. If a bad build ships: raise **min supported build** to the first good build + ensure shared URL points at the good APK.
25. Prepend factory map / mobile memory-bank only if process changes (agents handle map when code changes).

---

## Related docs

- **`docs/RELEASE_PLAYBOOK.md`** — full step-by-step when shipping every new APK (host + Admin + verify)  
- `docs/CHANGELOG.md` — release notes for operators  
- `docs/troubleshooting.md` — update prompt issues  
- `docs/app_features.md` — Admin capabilities overview  
- Map: `Components/Modules/JobCardsCoreModule.md` §Startup & Update Surfaces  
- Grok skills: `/mobile-app-release` (factory `latest.apk`) · `/mobile-pilot-release` (pilot `pilot.apk` for Departments/People)
