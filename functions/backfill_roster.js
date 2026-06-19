// One-shot backfill for directory/roster — seeds the denormalised employee roster
// that onEmployeeWritten then keeps in sync. Run ONCE right after deploying the
// roster changes so escalation switches from full-collection scans to a single-doc
// read immediately, instead of waiting for the nightly rebuildEmployeeRosterDaily.
//
//   cd functions && node backfill_roster.js
//
// Requires ../serviceAccountKey.json (same as the other admin scripts in this dir).
// Safe to re-run any time — it overwrites directory/roster with a fresh full scan.
const admin = require("firebase-admin");
const serviceAccount = require("../serviceAccountKey.json");
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: "ctp-job-cards",
});

const db = admin.firestore();

(async () => {
  const snap = await db.collection("employees").get();
  const emps = {};
  snap.docs.forEach((d) => { emps[d.id] = d.data(); });
  await db.collection("directory").doc("roster").set({
    emps,
    count: snap.size,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    rebuiltAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log(`directory/roster seeded with ${snap.size} employees`);
  process.exit(0);
})().catch((e) => {
  console.error("backfill failed:", e);
  process.exit(1);
});
