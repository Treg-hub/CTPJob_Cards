/* eslint-disable no-console */
// =============================================================================
// repair_job_cards.js — one-off data repair + backfill for the job_cards
// collection. Fixes the damage described in the 2026-06 job-cards review:
//
//   1. String timestamps → Firestore Timestamps. The mobile sync queue used to
//      replay offline edits with ISO-8601 strings in every *At field (and in
//      assignmentHistory[].timestamp), which makes JobCard.fromFirestore throw
//      and poisons every list stream in the app.
//   2. Cloud-Function-shaped assignmentHistory entries
//      ({clockNo, name, assignedAt, assignedBy, assignedByName}) → the Dart
//      AssignmentEvent shape the mobile model can parse.
//   3. Scalar assignedClockNos / assignedNames (written by the old
//      "Assign Self" notification action) → single-element arrays, so
//      arrayContains queries (My Work) match again.
//   4. Drops the legacy `assignedTo` scalar field (nothing reads it).
//   5. Backfills closedAt := completedAt ?? lastUpdatedAt ?? createdAt for
//      closed jobs missing it, so Job History / closed queries / Pulse KPIs
//      see them again.
//
// USAGE
//   node repair_job_cards.js                 # dry run — prints the diff only
//   node repair_job_cards.js --apply         # writes the changes
//   $env:FIRESTORE_EMULATOR_HOST="127.0.0.1:8080"; node repair_job_cards.js
//                                            # run against the emulator
//
// Requires ./serviceAccountKey.json (same as migrate_job_cards.js) unless
// running against the emulator or using Application Default Credentials
// (gcloud auth login). TAKE A FIRESTORE EXPORT BACKUP BEFORE --apply.
// =============================================================================

const admin = require("firebase-admin");
const fs = require("fs");

const APPLY = process.argv.includes("--apply");
const usingEmulator = !!process.env.FIRESTORE_EMULATOR_HOST;

if (usingEmulator) {
  admin.initializeApp({ projectId: "ctp-job-cards" });
} else if (fs.existsSync("./serviceAccountKey.json")) {
  // eslint-disable-next-line global-require
  const serviceAccount = require("./serviceAccountKey.json");
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
} else {
  // Fall back to Application Default Credentials (gcloud auth login / ADC).
  admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId: "ctp-job-cards" });
  console.log("Using Application Default Credentials (no serviceAccountKey.json found).");
}

const db = admin.firestore();
const { Timestamp, FieldValue } = admin.firestore;

// Every Timestamp-typed field on a job card document.
const TIMESTAMP_FIELDS = [
  "createdAt", "assignedAt", "startedAt", "lastUpdatedAt",
  "notificationReceivedAt",
  "notifiedAtStage1", "notifiedAtStage2", "notifiedAtStage3", "notifiedAtStage4",
  "completedAt", "monitoringStartedAt", "closedAt",
];

// Returns a Timestamp if [value] is a parseable ISO/date string, else null.
function timestampFromString(value) {
  if (typeof value !== "string" || value.length === 0) return null;
  const d = new Date(value);
  if (isNaN(d.getTime())) return null;
  return Timestamp.fromDate(d);
}

function isTimestamp(value) {
  return value instanceof Timestamp ||
    (value && typeof value.toMillis === "function");
}

// Normalises one assignmentHistory entry to the Dart AssignmentEvent shape.
// Returns { entry, changed }.
function repairHistoryEntry(entry, fallbackTimestamp) {
  if (!entry || typeof entry !== "object") return { entry, changed: false };

  let changed = false;
  const out = { ...entry };

  // CF auto-assign shape → Dart shape
  if (out.timestamp === undefined && (out.assignedAt !== undefined || out.clockNo !== undefined)) {
    out.assignedByName = out.assignedByName || "Auto-assigned (Pre Press Specialist)";
    out.assignedByClockNo = out.assignedByClockNo || out.assignedBy || "system";
    out.assigneeClockNos = Array.isArray(out.assigneeClockNos)
      ? out.assigneeClockNos
      : (out.clockNo ? [String(out.clockNo)] : []);
    out.assigneeNames = Array.isArray(out.assigneeNames)
      ? out.assigneeNames
      : (out.name ? [String(out.name)] : []);
    out.timestamp = isTimestamp(out.assignedAt)
      ? out.assignedAt
      : (timestampFromString(out.assignedAt) || fallbackTimestamp);
    out.isUnassign = out.isUnassign === true;
    delete out.clockNo;
    delete out.name;
    delete out.assignedAt;
    delete out.assignedBy;
    changed = true;
  }

  // String timestamp → Timestamp (offline-replay damage)
  if (typeof out.timestamp === "string") {
    const ts = timestampFromString(out.timestamp);
    out.timestamp = ts || fallbackTimestamp;
    changed = true;
  }

  // Still no usable timestamp → fall back so the Dart cast can't throw.
  if (!isTimestamp(out.timestamp)) {
    out.timestamp = fallbackTimestamp;
    changed = true;
  }

  return { entry: out, changed };
}

function describe(value) {
  if (value === null || value === undefined) return "null";
  if (isTimestamp(value)) return `Timestamp(${value.toDate().toISOString()})`;
  if (Array.isArray(value)) return `[${value.length} items]`;
  return JSON.stringify(value);
}

async function repair() {
  console.log(`repair_job_cards: ${APPLY ? "APPLY MODE — writing changes" : "DRY RUN — no writes"}${usingEmulator ? " (emulator)" : ""}`);

  const snapshot = await db.collection("job_cards").get();
  console.log(`Scanned ${snapshot.size} job cards`);

  let docsChanged = 0;
  const counts = {
    stringTimestamps: 0,
    historyEntries: 0,
    scalarAssignArrays: 0,
    assignedToDropped: 0,
    closedAtBackfilled: 0,
  };

  let batch = db.batch();
  let batchSize = 0;
  const commits = [];

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const update = {};
    const notes = [];

    // 1. String timestamps in top-level fields
    for (const field of TIMESTAMP_FIELDS) {
      const value = data[field];
      if (typeof value === "string") {
        const ts = timestampFromString(value);
        // Unparseable strings are cleared — null is safe for every field here.
        update[field] = ts || FieldValue.delete();
        notes.push(`${field}: "${value}" → ${ts ? describe(ts) : "deleted"}`);
        counts.stringTimestamps++;
      }
    }

    // 2. assignmentHistory entries
    const fallbackTs = isTimestamp(data.createdAt) ? data.createdAt : Timestamp.now();
    if (Array.isArray(data.assignmentHistory)) {
      let anyEntryChanged = false;
      const repaired = data.assignmentHistory.map((entry) => {
        const { entry: fixed, changed } = repairHistoryEntry(entry, fallbackTs);
        if (changed) {
          anyEntryChanged = true;
          counts.historyEntries++;
        }
        return fixed;
      });
      if (anyEntryChanged) {
        update.assignmentHistory = repaired;
        notes.push(`assignmentHistory: repaired entries`);
      }
    }

    // 3. Scalar assignment fields → arrays
    if (typeof data.assignedClockNos === "string") {
      update.assignedClockNos = data.assignedClockNos.length > 0 ? [data.assignedClockNos] : [];
      notes.push(`assignedClockNos: "${data.assignedClockNos}" → array`);
      counts.scalarAssignArrays++;
    }
    if (typeof data.assignedNames === "string") {
      update.assignedNames = data.assignedNames.length > 0 ? [data.assignedNames] : [];
      notes.push(`assignedNames: "${data.assignedNames}" → array`);
      counts.scalarAssignArrays++;
    }

    // 4. Drop legacy assignedTo
    if (data.assignedTo !== undefined) {
      update.assignedTo = FieldValue.delete();
      notes.push(`assignedTo: dropped ("${data.assignedTo}")`);
      counts.assignedToDropped++;
    }

    // 5. closedAt backfill for closed jobs
    const closedAtAfterRepair = update.closedAt !== undefined && isTimestamp(update.closedAt)
      ? update.closedAt
      : (isTimestamp(data.closedAt) ? data.closedAt : null);
    if (data.status === "closed" && !closedAtAfterRepair) {
      const completedAt = update.completedAt !== undefined && isTimestamp(update.completedAt)
        ? update.completedAt
        : (isTimestamp(data.completedAt) ? data.completedAt : null);
      const lastUpdatedAt = update.lastUpdatedAt !== undefined && isTimestamp(update.lastUpdatedAt)
        ? update.lastUpdatedAt
        : (isTimestamp(data.lastUpdatedAt) ? data.lastUpdatedAt : null);
      const createdAt = isTimestamp(data.createdAt) ? data.createdAt : null;
      const backfill = completedAt || lastUpdatedAt || createdAt;
      if (backfill) {
        update.closedAt = backfill;
        notes.push(`closedAt: backfilled from ${completedAt ? "completedAt" : lastUpdatedAt ? "lastUpdatedAt" : "createdAt"} → ${describe(backfill)}`);
        counts.closedAtBackfilled++;
      } else {
        notes.push(`closedAt: NO source timestamp available — left unset`);
      }
    }

    if (Object.keys(update).length === 0) continue;

    docsChanged++;
    console.log(`\n#${data.jobCardNumber ?? "?"} ${doc.id} (status=${data.status}):`);
    for (const n of notes) console.log(`   • ${n}`);

    if (APPLY) {
      batch.update(doc.ref, update);
      batchSize++;
      if (batchSize >= 400) {
        commits.push(batch.commit());
        batch = db.batch();
        batchSize = 0;
      }
    }
  }

  if (APPLY && batchSize > 0) commits.push(batch.commit());
  if (APPLY) await Promise.all(commits);

  console.log("\n================ SUMMARY ================");
  console.log(`Docs needing repair:        ${docsChanged} / ${snapshot.size}`);
  console.log(`String timestamps fixed:    ${counts.stringTimestamps}`);
  console.log(`History entries repaired:   ${counts.historyEntries}`);
  console.log(`Scalar assign fields fixed: ${counts.scalarAssignArrays}`);
  console.log(`assignedTo fields dropped:  ${counts.assignedToDropped}`);
  console.log(`closedAt backfilled:        ${counts.closedAtBackfilled}`);
  console.log(APPLY ? "Changes WRITTEN." : "Dry run only — re-run with --apply to write.");
}

repair()
  .catch((e) => {
    console.error("repair_job_cards failed:", e);
    process.exitCode = 1;
  })
  .finally(() => admin.app().delete());
