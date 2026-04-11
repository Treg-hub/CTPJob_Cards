const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'ctp-job-cards'
});

async function callMigrate() {
  try {
    const result = await admin.firestore().runTransaction(async (transaction) => {
      // Can't call callable directly, but since it's server, run the logic here
      const employeesRef = admin.firestore().collection('employees');
      const snapshot = await employeesRef.get();
      const migrated = [];
      const batch = admin.firestore().batch();

      for (const doc of snapshot.docs) {
        const docData = doc.data();
        const clockNo = docData.clockNo;
        if (doc.id !== clockNo) {
          const newRef = employeesRef.doc(clockNo);
          batch.set(newRef, docData);
          batch.delete(doc.ref);
          migrated.push({oldId: doc.id, newId: clockNo, name: docData.name});
        }
      }

      await batch.commit();
      return {migrated, count: migrated.length};
    });

    console.log('Migration result:', result);
  } catch (e) {
    console.error('Error:', e);
  }
}

callMigrate();