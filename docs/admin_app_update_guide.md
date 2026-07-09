# Admin guide — App Update Control (in-app APK)

**Who this is for:** Admins who publish Job Cards Android APKs from **Admin → Settings → App Update Control**.  
**Audience:** Operators install via **in-app download** (not Play Store).  
**Last updated:** 2026-07-09 (targeted channels, soft banner, department/people pickers).

---

## What this screen does

You control which devices are **offered** or **forced** to install a new APK **without** sideloading by hand for every phone.

| Concept | Meaning |
|---------|---------|
| **Soft update** | Home shows an **orange banner** (Update / Later). User can keep working. Later snoozes ~24 hours. |
| **Force update** | **Full-screen** block until they install. Back button blocked. Re-shows on app resume if still behind. |
| **Kill-switch** | `Min supported build` — **everyone** below that number is blocked **at app launch**. Use only for broken builds factory-wide. |
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
| Home open / resume | Soft: banner if offer and not snoozed. Force: full-screen. |
| Network re-fetch | About every **24 hours** when config is complete. |
| Force still needed | Re-blocks on resume even inside the 24h window. |
| Settings → Check for update | Immediate check + diagnostic (channel, force, URL). |

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

---

## Related docs

- `docs/CHANGELOG.md` — release notes for operators  
- `docs/troubleshooting.md` — update prompt issues  
- `docs/app_features.md` — Admin capabilities overview  
- Map: `Components/Modules/JobCardsCoreModule.md` §Startup & Update Surfaces  
