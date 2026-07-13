/**
 * Retention purge — scheduled weekly (Sunday 02:00 SAST, europe-west1).
 *
 * Policy (board-approved 2026-07-12):
 * - app_geofence: delete where createdAt older than 90 days
 * - notifications: delete where timestamp older than 90 days
 * - notification_inbox items: delete when read is true and age older than 90 days
 * - security_entries: delete where createdAt older than 180 days (+ best-effort Storage photos)
 * - geo_fence_logs: dropped separately (one-shot wipe + rules deny)
 *
 * Batched deletes (max ~4000 docs per collection per run) to stay under CF time/memory.
 * Logs deleted counts for Monitoring / Functions logs correlation.
 */
const admin = require("firebase-admin");

const BATCH_SIZE = 400;
const MAX_DOCS_PER_COLLECTION = 4000;

function cutoffDate(days) {
  return new Date(Date.now() - days * 24 * 60 * 60 * 1000);
}

/**
 * Delete up to maxDocs matching a query, in batches of BATCH_SIZE.
 * @returns {Promise<number>} docs deleted
 */
async function deleteByQuery(query, maxDocs, label) {
  const db = admin.firestore();
  let deleted = 0;
  while (deleted < maxDocs) {
    const snap = await query.limit(Math.min(BATCH_SIZE, maxDocs - deleted)).get();
    if (snap.empty) break;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    deleted += snap.size;
    console.log(`retention[${label}]: deleted batch size=${snap.size} total=${deleted}`);
    if (snap.size < BATCH_SIZE) break;
  }
  return deleted;
}

async function purgeAppGeofence() {
  const cutoff = cutoffDate(90);
  const q = admin.firestore()
    .collection("app_geofence")
    .where("createdAt", "<", cutoff)
    .orderBy("createdAt", "asc");
  return deleteByQuery(q, MAX_DOCS_PER_COLLECTION, "app_geofence");
}

async function purgeNotifications() {
  const cutoff = cutoffDate(90);
  const q = admin.firestore()
    .collection("notifications")
    .where("timestamp", "<", cutoff)
    .orderBy("timestamp", "asc");
  return deleteByQuery(q, MAX_DOCS_PER_COLLECTION, "notifications");
}

async function purgeReadInboxItems() {
  const cutoff = cutoffDate(90);
  const db = admin.firestore();
  // Walk inbox parents (clockNos) — avoids depending on a collectionGroup composite
  // index on first deploy. Factory scale (~hundreds of employees) is fine.
  let deleted = 0;
  const parents = await db.collection("notification_inbox").limit(500).get();
  for (const parent of parents.docs) {
    if (deleted >= MAX_DOCS_PER_COLLECTION) break;
    let cursor = null;
    while (deleted < MAX_DOCS_PER_COLLECTION) {
      let q = parent.ref.collection("items").where("read", "==", true).limit(BATCH_SIZE);
      if (cursor) q = q.startAfter(cursor);
      const items = await q.get();
      if (items.empty) break;
      cursor = items.docs[items.docs.length - 1];
      const batch = db.batch();
      let n = 0;
      for (const d of items.docs) {
        const data = d.data() || {};
        const ts = data.readAt || data.createdAt || data.timestamp;
        const when = ts && typeof ts.toDate === "function" ? ts.toDate() : null;
        // If no timestamp, only delete if clearly old parent walk pass with read=true
        // and createdAt missing — skip to be safe.
        if (when && when < cutoff) {
          batch.delete(d.ref);
          n += 1;
        }
      }
      if (n > 0) {
        await batch.commit();
        deleted += n;
      }
      if (items.size < BATCH_SIZE) break;
    }
  }
  console.log(`retention[inbox]: deleted=${deleted}`);
  return deleted;
}

async function purgeSecurityEntries() {
  const cutoff = cutoffDate(180);
  const db = admin.firestore();
  const bucket = admin.storage().bucket();
  let deleted = 0;
  let photosRemoved = 0;

  while (deleted < MAX_DOCS_PER_COLLECTION) {
    const snap = await db.collection("security_entries")
      .where("createdAt", "<", cutoff)
      .orderBy("createdAt", "asc")
      .limit(BATCH_SIZE)
      .get();
    if (snap.empty) break;

    for (const d of snap.docs) {
      // Best-effort Storage cleanup under security_entries/{id}/
      try {
        const [files] = await bucket.getFiles({
          prefix: `security_entries/${d.id}/`,
          maxResults: 50,
        });
        await Promise.all(files.map(async (f) => {
          try {
            await f.delete();
            photosRemoved += 1;
          } catch (_) { /* ignore missing */ }
        }));
      } catch (_) { /* bucket optional */ }
    }

    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    deleted += snap.size;
    console.log(`retention[security_entries]: deleted=${deleted} photos≈${photosRemoved}`);
    if (snap.size < BATCH_SIZE) break;
  }
  return { deleted, photosRemoved };
}

/**
 * Run all retention purges. Exported for scheduled CF + manual callable.
 */
async function runRetentionPurge() {
  const started = Date.now();
  const results = {
    app_geofence: 0,
    notifications: 0,
    inbox_items: 0,
    security_entries: 0,
    security_photos: 0,
  };

  results.app_geofence = await purgeAppGeofence();
  results.notifications = await purgeNotifications();
  results.inbox_items = await purgeReadInboxItems();
  const sec = await purgeSecurityEntries();
  results.security_entries = sec.deleted;
  results.security_photos = sec.photosRemoved;

  const summary = {
    ...results,
    elapsedMs: Date.now() - started,
    policy: {
      app_geofence_days: 90,
      notifications_days: 90,
      inbox_read_days: 90,
      security_entries_days: 180,
    },
  };
  console.log("retention purge complete:", JSON.stringify(summary));
  return summary;
}

module.exports = { runRetentionPurge };
