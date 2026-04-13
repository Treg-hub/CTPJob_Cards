const admin = require('firebase-admin');

// Initialize Firebase Admin SDK
const serviceAccount = require('./serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: 'https://your-project-id.firebaseio.com' // Replace with your project ID
});

const db = admin.firestore();

async function migrateJobCards() {
  try {
    console.log('Starting migration...');

    // Get all job cards ordered by createdAt ascending
    const snapshot = await db.collection('job_cards')
      .orderBy('createdAt', 'asc')
      .get();

    if (snapshot.empty) {
      console.log('No job cards found.');
      return;
    }

    console.log(`Found ${snapshot.size} job cards to migrate.`);

    let number = 1;
    const batch = db.batch();

    for (const doc of snapshot.docs) {
      const jobCardRef = doc.ref;
      batch.update(jobCardRef, { jobCardNumber: number });
      console.log(`Assigning number ${number} to job card ${doc.id}`);
      number++;
    }

    // Set the counter to the next number
    const counterRef = db.collection('counters').doc('jobCards');
    batch.set(counterRef, { nextJobCardNumber: number }, { merge: true });

    await batch.commit();
    console.log('Migration completed successfully!');
    console.log(`Next job card number set to ${number}`);

  } catch (error) {
    console.error('Migration failed:', error);
  } finally {
    admin.app().delete();
  }
}

// Run the migration
migrateJobCards();