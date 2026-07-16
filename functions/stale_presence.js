/**
 * Stale on-site presence clear — missing geofence heartbeat.
 *
 * Phones that enter the factory geofence set employees.isOnSite=true. While
 * on-site, WorkManager should write app_geofence eventType=check every ~30 min
 * (source workmanager_30min). OEM battery killers often stop that job, leaving
 * people stuck on-site for days and still receiving loud on-site pushes at home.
 *
 * This job finds isOnSite employees with no recent location proof in
 * app_geofence and force-clears them (Admin SDK). Schedule: every 2 hours.
 *
 * Proof window: 2 hours (aligned with the schedule). A healthy phone should
 * have ~4 WorkManager checks in that window.
 *
 * Exemption — iPhone/iPad Safari web: no geofence, deliberately left isOnSite
 * true so they stay in onsite escalation recipient queries; notifications are
 * always parked via notificationDelivery=inbox_only. Never clear those.
 */
const admin = require("firebase-admin");

/** No location proof for this long → treat as stale on-site. */
const STALE_MS = 2 * 60 * 60 * 1000;

const PROOF_EVENT_TYPES = new Set(["check", "enter"]);

/** Sources that prove the device (or an admin) still affirms presence. */
const PROOF_SOURCES = new Set([
  "workmanager_30min",
  "app_open_check",
  "native_geofence",
  "native_geofence_fg",
  "admin_manual",
]);

/**
 * @param {FirebaseFirestore.QueryDocumentSnapshot} doc
 * @returns {boolean}
 */
function isPresenceProof(doc) {
  const d = doc.data() || {};
  const eventType = String(d.eventType || "");
  const source = String(d.source || "");
  return PROOF_EVENT_TYPES.has(eventType) && PROOF_SOURCES.has(source);
}

/**
 * iPhone/iPad web (and any inbox_only client): no native geofence heartbeats by
 * design — must not be treated as OEM-stuck Android zombies.
 * @param {FirebaseFirestore.DocumentData|undefined|null} emp
 * @returns {boolean}
 */
function isGeofenceExempt(emp) {
  if (!emp) return false;
  if (emp.notificationDelivery === "inbox_only") return true;
  const platform = String(emp.clientPlatform || "").toLowerCase();
  const device = String(emp.clientDevice || "").toLowerCase();
  if (platform === "web" && (device === "iphone" || device === "ipad")) {
    return true;
  }
  return false;
}

/**
 * Clear stuck isOnSite flags when app_geofence has no recent check/enter proof.
 * Skips inbox_only / iPhone-iPad web (deliberate non-geofence on-site).
 * @returns {Promise<object>}
 */
async function runStalePresenceClear() {
  const db = admin.firestore();
  const started = Date.now();
  const cutoff = new Date(Date.now() - STALE_MS);
  const cutoffTs = admin.firestore.Timestamp.fromDate(cutoff);
  const now = admin.firestore.FieldValue.serverTimestamp();

  // One bounded read of recent geofence activity (2h window — small at factory scale).
  const recentSnap = await db
    .collection("app_geofence")
    .where("createdAt", ">=", cutoffTs)
    .get();

  const alive = new Set();
  for (const doc of recentSnap.docs) {
    if (!isPresenceProof(doc)) continue;
    const clockNo = doc.data().clockNo;
    if (clockNo != null && String(clockNo).length > 0) {
      alive.add(String(clockNo));
    }
  }

  const onSiteSnap = await db
    .collection("employees")
    .where("isOnSite", "==", true)
    .get();

  const clearedClockNos = [];
  const skippedExemptClockNos = [];
  // Batch in chunks of 400 (each clear = employee update + app_geofence add).
  let batch = db.batch();
  let opsInBatch = 0;

  const commitBatch = async () => {
    if (opsInBatch === 0) return;
    await batch.commit();
    batch = db.batch();
    opsInBatch = 0;
  };

  for (const empDoc of onSiteSnap.docs) {
    const clockNo = empDoc.id;
    if (alive.has(clockNo)) continue;

    const emp = empDoc.data() || {};
    if (isGeofenceExempt(emp)) {
      skippedExemptClockNos.push(clockNo);
      continue;
    }

    batch.set(
      empDoc.ref,
      {
        isOnSite: false,
        presenceSource: "stale_presence_cf",
        presenceUpdatedAt: now,
        lastOffSiteAt: now,
      },
      { merge: true },
    );
    opsInBatch++;

    const logRef = db.collection("app_geofence").doc();
    batch.set(logRef, {
      clockNo,
      eventType: "exit",
      source: "stale_presence_cf",
      isOnSite: false,
      notes: `Auto off-site: no app_geofence check/enter proof in last ${STALE_MS / 3600000}h`,
      timestamp: now,
      createdAt: now,
    });
    opsInBatch++;
    clearedClockNos.push(clockNo);

    if (opsInBatch >= 400) {
      await commitBatch();
    }
  }

  await commitBatch();

  const summary = {
    scanned: onSiteSnap.size,
    cleared: clearedClockNos.length,
    clearedClockNos,
    skippedExempt: skippedExemptClockNos.length,
    skippedExemptClockNos,
    recentProofDocs: recentSnap.size,
    aliveCount: alive.size,
    staleMs: STALE_MS,
    elapsedMs: Date.now() - started,
  };
  console.log("stalePresenceClear complete:", JSON.stringify(summary));
  return summary;
}

/**
 * One-shot heal: restore inbox_only / iPhone-iPad web users who were incorrectly
 * cleared by an earlier stale_presence_cf run (before the exemption shipped).
 * @returns {Promise<object>}
 */
async function restoreExemptClearedByStaleCf() {
  const db = admin.firestore();
  const started = Date.now();
  const now = admin.firestore.FieldValue.serverTimestamp();

  // Single-field equality only (no composite index). Filter isOnSite in memory.
  const snap = await db
    .collection("employees")
    .where("presenceSource", "==", "stale_presence_cf")
    .get();

  const restoredClockNos = [];
  let batch = db.batch();
  let opsInBatch = 0;

  const commitBatch = async () => {
    if (opsInBatch === 0) return;
    await batch.commit();
    batch = db.batch();
    opsInBatch = 0;
  };

  for (const empDoc of snap.docs) {
    const emp = empDoc.data() || {};
    if (emp.isOnSite === true) continue;
    if (!isGeofenceExempt(emp)) continue;

    const clockNo = empDoc.id;
    batch.set(
      empDoc.ref,
      {
        isOnSite: true,
        presenceSource: "stale_presence_cf_restore",
        presenceUpdatedAt: now,
        lastOnSiteAt: now,
      },
      { merge: true },
    );
    opsInBatch++;

    const logRef = db.collection("app_geofence").doc();
    batch.set(logRef, {
      clockNo,
      eventType: "enter",
      source: "stale_presence_cf_restore",
      isOnSite: true,
      notes: "Restore iPhone/web inbox_only user incorrectly cleared by stale_presence_cf",
      timestamp: now,
      createdAt: now,
    });
    opsInBatch++;
    restoredClockNos.push(clockNo);

    if (opsInBatch >= 400) {
      await commitBatch();
    }
  }

  await commitBatch();

  const summary = {
    candidates: snap.size,
    restored: restoredClockNos.length,
    restoredClockNos,
    elapsedMs: Date.now() - started,
  };
  console.log("restoreExemptClearedByStaleCf complete:", JSON.stringify(summary));
  return summary;
}

module.exports = {
  runStalePresenceClear,
  restoreExemptClearedByStaleCf,
  isGeofenceExempt,
  STALE_MS,
  PROOF_EVENT_TYPES,
  PROOF_SOURCES,
};
