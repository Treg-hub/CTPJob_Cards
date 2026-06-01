# Cloud Functions — Deployment Guide

> Source: `/functions/index.js` (Node.js 24, Firebase Functions v2).
> This guide describes the function inventory, the two-region layout, deployment commands, and common failure modes.

---

## Function inventory

The global default region is `africa-south1` (set in `functions.setGlobalOptions`). Scheduled functions override this and run in `europe-west1` — see the **Regions** section below for why.

### `africa-south1`

| Function | Type | Trigger | Purpose |
|----------|------|---------|---------|
| `createCustomToken` | Callable | HTTPS | Issues a Firebase custom auth token for clock-number-based login. |
| `sendJobAssignmentNotification` | Callable | HTTPS | Pushes an FCM message to the recipient. Checks `isOnSite` for all priorities — if off-site, parks the notification to `notification_inbox/{clockNo}/items` instead. |
| `sendCreatorNotification` | Callable | HTTPS | Pushes an FCM message back to the job creator on completion, self-assign, or update. Looks up creator's `isOnSite` via `jobCardId`; parks to inbox if off-site. |
| `onJobCardCreated` | Firestore trigger | `onDocumentCreated('job_cards/{jobId}')` | Routes the initial notification to on-site mechanics/electricians per `creation_recipients_by_type`. Already onsite-safe via rule-based resolution. |
| `onJobCardAssigned` | Firestore trigger | `onDocumentUpdated('job_cards/{jobId}')` | Fires when `assignedTo` transitions from null → value. Checks `isOnSite`; parks to inbox if off-site, else sends FCM push. Sets `escalationStopped: true` in both paths. |
| `onAlertResponseCreated` | Firestore trigger | `onDocumentCreated('alertResponses/{responseId}')` | Handles "I'm Busy" responses — notifies the job creator if on-site, parks to inbox if off-site. Logs dismissals. |
| `onCopperTransactionWrite` | Firestore trigger | `onDocumentWritten('copperTransactions/{docId}')` | Alerts employee #22 when total sell copper exceeds 400 kg. Checks `isOnSite`; parks to inbox if off-site. |
| `migrateEmployeeIds` | Callable | HTTPS | One-time migration helper. |
| `migrateJobStatuses` | Callable | HTTPS | One-time migration helper. |
| `clearEscalationStamps` | Callable | HTTPS | Resets `notifiedAtStage1..4` fields when an admin changes recipient rules (so old jobs don't bombard the new audience). |

### `europe-west1`

| Function | Type | Schedule | Purpose |
|----------|------|----------|---------|
| `escalateNotifications` | Scheduled | every 5 minutes | Reads `notification_configs/global` (cached 10 min), fetches employees (cached 5 min), advances jobs through stages 1→4. All stages use onsite-only rules; no offsite push during escalation. |
| `autoCloseMonitoringJobs` | Scheduled | `0 8 * * *` (08:00 daily) | Auto-closes Monitor-status jobs older than 7 days. |

### Why two regions

Firebase scheduled functions require a region that supports Google App Engine. **`africa-south1` does not support App Engine**, so any function using `functions.scheduler.onSchedule({...})` must declare `region: "europe-west1"` (or another App-Engine-supported region). Do not change these to `africa-south1` — deployment will fail.

This split is captured in the memory note `feedback_scheduled_functions_region.md`.

---

## Deployment

From the repo root:

```bash
# Install / update dependencies
cd functions
npm install

# Deploy everything
firebase deploy --only functions

# Deploy a single function
firebase deploy --only functions:escalateNotifications
firebase deploy --only functions:onJobCardCreated

# Deploy multiple
firebase deploy --only functions:onJobCardCreated,functions:onJobCardAssigned
```

> Per-function deploys are strongly preferred during routine work — they're faster and avoid touching the scheduled functions (which take longer to roll over).

The npm scripts in `functions/package.json` shortcut the common commands:

```bash
npm --prefix functions run deploy   # firebase deploy --only functions
npm --prefix functions run logs     # firebase functions:log
```

---

## Notification Inbox collection

Functions write to `notification_inbox/{clockNo}/items/{itemId}` when a recipient is off-site. The Flutter app reads this via a real-time listener (no composite index needed — single-field `read` query only). Documents are never auto-deleted; the user marks them read via the app.

**Fields per item:** `type`, `jobCardId`, `jobCardNumber`, `title`, `body`, `department`, `area`, `machine`, `part`, `priority`, `triggeredBy`, `createdAt` (server timestamp), `read` (bool), `readAt` (timestamp|null), `initiatedByClockNo`, `initiatedByName`.

**Security rules** must allow each employee to read/write only their own `notification_inbox/{clockNo}` subtree (match by UID or custom claim). Currently not tracked in `firestore.rules` in repo — add before going to production.

---

## Required Firestore composite indexes

The escalation function relies on composite indexes for the staged query `where(status == "open").where(notifiedAtStageN == null).where(createdAt <= cutoff)`. The indexes are:

- `status, notifiedAtStage1, createdAt`
- `status, notifiedAtStage2, createdAt`
- `status, notifiedAtStage3, createdAt`
- `status, notifiedAtStage4, createdAt`

These live in `firestore.indexes.json` at the repo root. After modifying:

```bash
firebase deploy --only firestore:indexes
```

> **Index quirk**: Firestore composite indexes only include documents that actually have the indexed field. Legacy job cards created before the four stamp fields existed won't be returned by these queries until they're backfilled. Use the `clearEscalationStamps` callable to write `null` stamps onto old documents.

---

## Local emulation

```bash
cd functions
firebase emulators:start --only functions,firestore
```

Override the region in your client when calling the local emulator:

```dart
FirebaseFunctions.instanceFor(region: 'africa-south1').useFunctionsEmulator('localhost', 5001);
```

Scheduled functions don't fire on a schedule in the emulator — invoke them manually:

```bash
curl http://localhost:5001/ctp-job-cards/europe-west1/escalateNotifications
```

---

## Common failure modes

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `escalateNotifications` deploy fails with "scheduler not supported in region" | Region was changed to `africa-south1` | Restore `region: "europe-west1"` and redeploy |
| Escalation isn't firing for any job | `notification_configs/global` is missing, or stages are all disabled | Check the doc exists, and `stages.stageN.enabled === true` for at least one stage |
| Escalation isn't firing for a specific job | `createdAt <= enabled_at` (stage was enabled after the job was created) | Either backfill `enabled_at`, or run `clearEscalationStamps` if recipients changed |
| `failed-precondition: query requires an index` | Composite index missing | Open the Firebase Console error link to auto-create, then redeploy `firestore.indexes.json` |
| Cold-start timeouts on `onJobCardCreated` | Function instance was idle | Acceptable — first invocation after idle warms up; subsequent calls are fast |
| Notifications go to the wrong recipients | `recipients_by_type` keys don't match (mechanical vs mech/elec) | Check `jobTypeKey()` in `index.js` — the Dart enum `mechanicalElectrical` maps to `mech/elec` (with slash) |
| Employee receives no push notification after assignment | Employee's `isOnSite` is `false` — notification was parked to inbox | Expected behaviour. Check `notification_inbox/{clockNo}/items` in the Firebase Console to confirm the inbox item was written |
| Inbox items never appear in the app | Employee is reading a different clockNo's inbox | Confirm `currentEmployee.clockNo` matches the Firestore doc ID in the `notification_inbox` collection |
| Schema drift between admin app and Cloud Function | `_buildStageDoc` in `admin_screen.dart` writes a field that `getNotificationConfig` doesn't read (or vice versa) | Keep both in sync — see `escalation_config_structure.md` |

---

## Logs

```bash
firebase functions:log
firebase functions:log --only escalateNotifications --lines 200
```

For real-time monitoring, the Firebase Console → Functions → Logs view streams live.

---

## Related docs

- [Escalation system](escalation_system.md) — the algorithm and config schema
- [Troubleshooting](troubleshooting.md) — user-facing symptoms that often trace back to functions
- [Firebase security rules](firebase_security_rules.md) — Firestore + Storage access control
