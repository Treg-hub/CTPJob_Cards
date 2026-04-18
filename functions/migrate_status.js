const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.migrateJobStatuses = functions.https.onCall(async (data, context) => {
  // Check if user is authenticated and is admin
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  // You can add admin check here if needed
  // if (!context.auth.token.admin) {
  //   throw new functions.https.HttpsError('permission-denied', 'Must be admin');
  // }

  try {
    console.log('Starting status migration...');

    const db = admin.firestore();
    const snapshot = await db.collection('job_cards').get();

    if (snapshot.empty) {
      return { message: 'No job cards found.', updated: 0 };
    }

    console.log(`Found ${snapshot.size} job cards to check for status migration.`);

    const batch = db.batch();
    let updatedCount = 0;
    const updates = [];

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const currentStatus = data.status;

      let newStatus = currentStatus;

      if (currentStatus === 'completed') {
        newStatus = 'closed';
        updates.push({ id: doc.id, from: 'completed', to: 'closed' });
      } else if (currentStatus === 'monitoring') {
        newStatus = 'monitor';
        updates.push({ id: doc.id, from: 'monitoring', to: 'monitor' });
      }

      if (newStatus !== currentStatus) {
        batch.update(doc.ref, { status: newStatus });
        updatedCount++;
      }
    }

    if (updatedCount > 0) {
      await batch.commit();
      console.log(`Migration completed! Updated ${updatedCount} job cards.`);
      return {
        message: `Migration completed! Updated ${updatedCount} job cards.`,
        updated: updatedCount,
        updates: updates
      };
    } else {
      return { message: 'No job cards needed status updates.', updated: 0, updates: [] };
    }

  } catch (error) {
    console.error('Migration failed:', error);
    throw new functions.https.HttpsError('internal', 'Migration failed: ' + error.message);
  }
});