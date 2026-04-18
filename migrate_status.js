const admin = require('firebase-admin');

// Initialize Firebase Admin SDK using Firebase CLI authentication
admin.initializeApp({
  projectId: 'ctp-job-cards'
});

const db = admin.firestore();

async function migrateJobStatus() {
  try {
    console.log('Starting status migration...');

    // Get all job cards
    const snapshot = await db.collection('job_cards').get();

    if (snapshot.empty) {
      console.log('No job cards found.');
      return;
    }

    console.log(`Found ${snapshot.size} job cards to check for status migration.`);

    const batch = db.batch();
    let updatedCount = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const currentStatus = data.status;

      let newStatus = currentStatus;

      if (currentStatus === 'completed') {
        newStatus = 'closed';
        console.log(`Updating job card ${doc.id}: 'completed' -> 'closed'`);
      } else if (currentStatus === 'monitoring') {
        newStatus = 'monitor';
        console.log(`Updating job card ${doc.id}: 'monitoring' -> 'monitor'`);
      }

      if (newStatus !== currentStatus) {
        batch.update(doc.ref, { status: newStatus });
        updatedCount++;
      }
    }

    if (updatedCount > 0) {
      await batch.commit();
      console.log(`Migration completed! Updated ${updatedCount} job cards.`);
    } else {
      console.log('No job cards needed status updates.');
    }

  } catch (error) {
    console.error('Migration failed:', error);
  } finally {
    admin.app().delete();
  }
}

// Run the migration
migrateJobStatus();