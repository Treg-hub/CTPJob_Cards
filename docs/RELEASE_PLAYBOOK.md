# Job Cards Android — Release Playbook

**Who this is for:** You (or an agent) shipping a new CTP Job Cards APK.  
**Last updated:** 2026-07-09  

**Canonical APK URL (first install + in-app update):**

```text
https://ctp-job-cards-landing.web.app/releases/latest.apk
```

| Path | Purpose |
|------|---------|
| **Landing page** | New users: **Download app** + QR → that APK → install → **Create account / Login in the app** |
| **In-app updater** | Returning users: banner / force / Settings → Check for update → same APK URL |
| **Admin App Update Control** | Source of truth for version, build, force, channels, Shared download URL |
| **Remote Config** | Optional seed / legacy; should match the same URL if you keep it updated |

Auth for the app is **always in-app** (not App Distribution, not the landing register flow).

---

## Quick reference — every release

```text
1. Bump pubspec + CHANGELOG
2. flutter build apk --target-platform android-arm64 --release
3. pwsh .\scripts\publish-landing-apk.ps1   (or node build-landing.js + deploy landing)
4. Browser: open latest.apk URL → must download ~45–50 MB
5. Admin → Shared download URL = canonical URL above
6. Admin → version + build (+ channel force as needed) → Save publish
7. Optional: RC latest_version / latest_build / download_url (same URL) / release_notes
8. Pilot: Settings → Check for update → Download & install
9. Soft factory Default when ready
```

Working directory for app commands:

```powershell
cd C:\Users\Admin\CTP-Factory-System\mobile\CTPJob_Cards
```

---

## Full checklist

### A. Before you build

| # | Step | Detail |
|---|------|--------|
| A1 | Bump version | `pubspec.yaml` → `version: X.Y.Z+BUILD` (**build number must increase**) |
| A2 | Changelog | Prepend `docs/CHANGELOG.md` with `## … (build N)` using the **exact** build number |
| A3 | Decide release mode | Soft factory / force group / pilot (People) / kill-switch only if broken |
| A4 | Signing | Same keystore as all previous factory installs |

### B. Build APK

| # | Step | Command / note |
|---|------|----------------|
| B1 | Build | `flutter build apk --target-platform android-arm64 --release` |
| B2 | Output | `build\app\outputs\flutter-apk\app-release.apk` |

### C. Host APK on landing (official file)

| # | Step | Command / note |
|---|------|----------------|
| C1 | Assemble + deploy | **Preferred:** `pwsh .\scripts\publish-landing-apk.ps1` |
| C1b | Manual | `node build-landing.js` then `firebase deploy --only hosting:landing --project ctp-job-cards` |
| C2 | Order | `build-landing.js` **wipes** `landing-deploy/`. APK is copied **at the end** only if `app-release.apk` already exists. Always build APK **before** `build-landing.js`. |
| C3 | Verify | Browser (or incognito): open canonical URL → large APK download, **not** Google login, **not** 404 |
| C4 | Optional archive | Keep a local copy named `ctp-job-cards-X.Y.Z-BUILD.apk` for rollback |

### D. Tell the app (Admin — required)

Open Job Cards as **admin** → **Admin → Settings → App Update Control**.

| # | Field | Value |
|---|--------|--------|
| D1 | **Shared download URL** | `https://ctp-job-cards-landing.web.app/releases/latest.apk` |
| D2 | **Version** | e.g. `2.3.0` (left of `+` in pubspec) |
| D3 | **Build** | e.g. `145` (right of `+`) |
| D4 | **Channel** | Pilot: **People** first. Factory soft: **Default**, Force **off**. Dept force: **Departments** + pickers; keep Default lower if others must not force |
| D5 | Force | On only when that cohort must update before using the app |
| D6 | Notes | Short (optional). What’s changed uses bundled CHANGELOG |
| D7 | **Save publish** | Writes `settings/app` (channels + legacy Default mirror) |
| D8 | Min supported build | **Only** when retiring broken builds factory-wide — after URL works |

### E. Remote Config (optional, keep in sync)

Firebase Console → **Remote Config** (project `ctp-job-cards`).

| Key | Should be |
|-----|-----------|
| `latest_version` | Same as Admin version |
| `latest_build` | Same as Admin build |
| `download_url` | **Same Hosting URL** as Shared download URL (not App Distribution) |
| `force_update` | Prefer controlling force via **Admin channels**; RC is seed only |
| `release_notes` | Short text for landing badge if used |

**Why both exist:** Check for update loads **RC first as a seed**, then **Firestore `settings/app` wins** when channel publish metadata is present (version/build set). Admin publish is the **source of truth**. Stale RC with an old App Distribution link can confuse diagnostics if Firestore is incomplete — keep RC aligned with the Hosting URL.

### F. Verify

| # | Check | Pass criteria |
|---|--------|----------------|
| F1 | Landing | Download button / QR installs APK |
| F2 | Old phone | **Settings → Check for update** shows current vs latest, channel, **Hosting** URL |
| F3 | Soft | Banner → Update → download → install → What’s changed |
| F4 | Later | Soft snoozes ~24h; Settings check still works |
| F5 | Force (if used) | Full screen; resume still blocks until installed |
| F6 | Smoke | Login/session + Home + modules you touched |
| F7 | Kiosk | Exit kiosk → update → re-enter |

### G. After release

| # | Step |
|---|------|
| G1 | Watch Crashlytics for update/install errors |
| G2 | Bad build: host good APK at `latest.apk`, Admin URL same, raise **min supported build** if needed |
| G3 | Kill old file only: redeploy landing without APK or rotate path — then update Admin URL if path changed |

---

## How “Check for update” resolves URLs

Order inside `UpdateService` (**build 147+** — Admin first):

1. **Firestore `settings/app`** — matched channel, then Shared `updateDownloadUrl` / legacy publish fields  
2. **Remote Config** — **only empty fields** (never overwrites an Admin download URL)  

Older builds (≤146) loaded RC first and kept App Distribution URLs when Admin left channel URL empty — fixed in code.

**Where it should point:** the Hosting APK:

```text
https://ctp-job-cards-landing.web.app/releases/latest.apk
```

Set that in **Admin Shared download URL** (and channel URL if separate). Optional: set RC `download_url` to the same value so gap-fill is not App Distribution.

If Check for update still shows App Distribution on a **new** build:

1. Admin Shared URL empty or not Saved  
2. Fix Admin → Save publish  
3. Settings → Check for update again  
4. Diagnostic **Config source** should be `firestore:default` (or channel id), not `remote_config`

---

## User journeys

### New user

1. Open https://ctp-job-cards-landing.web.app  
2. **Download app** (or QR)  
3. Install APK (allow unknown sources once)  
4. **Create account** (clock + email + password) — employee row must already exist  
5. Permissions onboarding  

### Returning user

1. Soft banner or force screen, or Settings → Check for update  
2. Download & install from official URL  
3. Reopen → What’s changed if new build  

---

## Pilot file (`pilot.apk`) — department / people only

Use when you want a **second binary** so landing Download stays on factory `latest.apk` while Ink (or selected people) update from pilot.

| URL | Role |
|-----|------|
| `…/releases/latest.apk` | Shared + Default + landing **Download** |
| `…/releases/pilot.apk` | Departments / People **Channel APK URL** only |

```powershell
cd mobile\CTPJob_Cards
flutter build apk --target-platform android-arm64 --release
pwsh .\scripts\publish-landing-pilot-apk.ps1
```

Then Admin: Shared = latest; Default build **lower**; Departments/People = pilot version/build + Channel APK URL = pilot.apk → Save.

Skill: **`/mobile-pilot-release`**.

---

## Kill / rotate the download URL

| Goal | Action |
|------|--------|
| Stop serving this binary | Redeploy landing without `releases/latest.apk`, or overwrite with good APK |
| Change location | New path or host → Admin Shared URL + landing button/QR → Save |
| Block old app versions | Raise **min supported build** + working Shared URL |
| Full site down | Hosting disable — kills page + APK; only if intentional |

In-app clients pick up a **new** Admin URL on next successful update check.

---

## One-shot commands

```powershell
cd C:\Users\Admin\CTP-Factory-System\mobile\CTPJob_Cards

# After bumping pubspec + CHANGELOG:
flutter build apk --target-platform android-arm64 --release
pwsh .\scripts\publish-landing-apk.ps1

# Then Admin Save publish (Shared URL + version + build)
```

Build APK as part of the script:

```powershell
pwsh .\scripts\publish-landing-apk.ps1 -BuildApk
```

Assemble only (no deploy):

```powershell
pwsh .\scripts\publish-landing-apk.ps1 -SkipDeploy
```

---

## Related docs

- `docs/admin_app_update_guide.md` — channels, force, kill-switch, Admin UI  
- `docs/troubleshooting.md` — update banner issues  
- Root `publish.md` — monorepo deploy notes  
- Map: `Components/Modules/JobCardsCoreModule.md` §Startup & Update  

**Agent skills:**

- `/mobile-app-release` — factory APK → `latest.apk` (landing Download + Default)  
- `/mobile-pilot-release` — pilot APK → `pilot.apk` (Departments/People channel URL only; keeps factory `latest.apk`)
