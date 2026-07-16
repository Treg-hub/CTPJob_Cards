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
 * Clear stuck isOnSite flags when app_geofence has no recent check/enter proof.
 * @returns {Promise<{scanned:number, cleared:number, clearedClockNos:string[], staleMs:number, elapsedMs:number}>}
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
    recentProofDocs: recentSnap.size,
    aliveCount: alive.size,
    staleMs: STALE_MS,
    elapsedMs: Date.now() - started,
  };
  console.log("stalePresenceClear complete:", JSON.stringify(summary));
  return summary;
}

module.exports = {
  runStalePresenceClear,
  STALE_MS,
  PROOF_EVENT_TYPES,
  PROOF_SOURCES,
};
