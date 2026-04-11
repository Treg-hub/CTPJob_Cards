const admin = require('firebase-admin');

const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'ctp-job-cards'
});

const db = admin.firestore();

async function exportEmployees() {
  const snapshot = await db.collection('employees').get();
  const employees = [];
  snapshot.forEach(doc => {
    employees.push({id: doc.id, data: doc.data()});
  });
  require('fs').writeFileSync('employees_backup.json', JSON.stringify(employees, null, 2));
  console.log('Exported to employees_backup.json');
  process.exit(0);
}

exportEmployees();