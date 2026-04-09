const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const messaging = admin.messaging();

functions.setGlobalOptions({ region: "africa-south1" });

exports.sendJobAssignmentNotification = functions.https.onCall(async (data) => {
  const { recipientToken, operator, department, area, machine, part, description } = data;

  if (!recipientToken) {
    throw new functions.https.HttpsError("invalid-argument", "Missing recipientToken");
  }

  // Build rich notification body
  const body = `Operator: ${operator}\n` +
               `${department} - ${area} - ${machine} - ${part}\n` +
               `Description: ${description}`;

  try {
    const response = await messaging.send({
      token: recipientToken,
      notification: {
        title: "New Job Assigned",
        body: body
      },
      data: { click_action: "FLUTTER_NOTIFICATION_CLICK" },
      android: { priority: "high" }
    });

    console.log("✅ Notification sent successfully");
    return { success: true, messageId: response };
  } catch (error) {
    console.error("FCM Error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

// Helper functions
async function getOnsiteMechanics() {
  const snaps = await admin.firestore().collection('employees').where('isOnSite', '==', true).get();
  return snaps.docs.filter(doc => {
    const pos = doc.data().position;
    if (!pos || typeof pos !== 'string') return false;
    const lowerPos = pos.toLowerCase();
    return /mechanical|mechanic/i.test(lowerPos) && !/manager/i.test(lowerPos);
  }).map(doc => ({token: doc.data().fcmToken, ...doc.data()}));
}

async function getOnsiteElectricians() {
  const snaps = await admin.firestore().collection('employees').where('isOnSite', '==', true).get();
  return snaps.docs.filter(doc => {
    const pos = doc.data().position;
    if (!pos || typeof pos !== 'string') return false;
    const lowerPos = pos.toLowerCase();
    return /electrician|electrical/i.test(lowerPos) && !/manager/i.test(lowerPos);
  }).map(doc => ({token: doc.data().fcmToken, ...doc.data()}));
}

async function getInitialRecipients(jobType) {
  if (jobType === 'mechanical') return getOnsiteMechanics();
  if (jobType === 'electrical') return getOnsiteElectricians();
  return [...await getOnsiteMechanics(), ...await getOnsiteElectricians()];
}

async function getRelevantManagers(jobType) {
  const mechMgr = await admin.firestore().doc('employees/23194').get();
  const elecMgr = await admin.firestore().doc('employees/23162').get();
  const mgrs = [];
  if (jobType === 'mechanical' || jobType === 'mechanicalElectrical') {
    if (mechMgr.exists) mgrs.push(mechMgr.data());
  }
  if (jobType === 'electrical' || jobType === 'mechanicalElectrical') {
    if (elecMgr.exists) mgrs.push(elecMgr.data());
  }
  return mgrs.filter(Boolean);
}

async function getOnsiteDeptForemenShiftLeaders(dept) {
  const snaps = await admin.firestore().collection('employees')
    .where('department', '==', dept)
    .where('isOnSite', '==', true).get();
  return snaps.docs.filter(doc => {
    const pos = doc.data().position;
    if (!pos || typeof pos !== 'string') return false;
    const lowerPos = pos.toLowerCase();
    return /foreman|shift leader/i.test(lowerPos);
  }).map(doc => doc.data());
}

async function getDeptManagers(dept) {
  const snaps = await admin.firestore().collection('employees')
    .where('department', '==', dept).get();
  return snaps.docs.filter(doc => {
    const pos = doc.data().position;
    if (!pos || typeof pos !== 'string') return false;
    const lowerPos = pos.toLowerCase();
    return /manager/i.test(lowerPos);
  }).map(doc => doc.data());
}

async function getWorkshopManager() {
  const snaps = await admin.firestore().collection('employees')
    .where('department', '==', 'Workshop').get();
  return snaps.docs.filter(doc => {
    const pos = doc.data().position;
    if (!pos || typeof pos !== 'string') return false;
    const lowerPos = pos.toLowerCase();
    return /manager/i.test(lowerPos) && !/mechanical|electrical/i.test(lowerPos);
  }).map(doc => doc.data())[0];
}

async function sendNotification(token, title, body, jobId) {
  if (!token) return;
  try {
    await messaging.send({
      token,
      notification: { title, body },
      data: { click_action: 'FLUTTER_NOTIFICATION_CLICK', jobId },
      android: { priority: 'high' }
    });
  } catch (e) {
    console.error('FCM send error:', e);
  }
}

// Triggers
exports.onJobCardCreated = functions.firestore.onDocumentCreated({ document: 'job_cards/{jobId}' }, async (event) => {
  const job = event.data.data();
  const recipients = await getInitialRecipients(job.type);
  for (const emp of recipients) {
    await sendNotification(emp.token, 'New Job Available', `${job.department} - ${job.machine}\n${job.area} - ${job.part}\n${job.description}`, event.data.id);
  }
});

exports.onJobCardAssigned = functions.firestore.onDocumentUpdated({ document: 'job_cards/{jobId}' }, async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!before.assignedTo && after.assignedTo) {
    const assignee = await admin.firestore().doc(`employees/${after.assignedTo}`).get();
    if (assignee.exists) {
      await sendNotification(assignee.data().fcmToken, 'New Job Assigned', `${after.department} - ${after.machine}\n${after.area} - ${after.part}\n${after.description}`, event.data.after.id);
    }
  }
});

// Escalation timer - FULLY UPDATED with extra logging + europe-west1 + Johannesburg timezone
// NOTE: The two queries below each need a composite Firestore index.
// The 2-minute one should already have a creation link in your logs.
// The 7-minute one will show a new link the next time it runs - just click it and create the index.
exports.escalateNotifications = functions.scheduler.onSchedule({
  schedule: 'every 2 minutes',
  region: 'europe-west1',
  timeZone: 'Africa/Johannesburg'
}, async (event) => {
  console.log('🚀 escalateNotifications started at', new Date().toISOString());

  try {
    const now = admin.firestore.FieldValue.serverTimestamp();
    const twoMinAgo = new Date(Date.now() - 2 * 60 * 1000);
    const sevenMinAgo = new Date(Date.now() - 7 * 60 * 1000);

    console.log('⏰ twoMinAgo:', twoMinAgo.toISOString(), 'sevenMinAgo:', sevenMinAgo.toISOString());

    // ==================== 2-MINUTE ESCALATION ====================
    console.log('🔍 Running 2min query: status=open, assignedTo=null, createdAt<=2minAgo, notifiedAt2min=null');
    const jobs2min = await admin.firestore().collection('job_cards')
      .where('status', '==', 'open')
      .where('assignedTo', '==', null)
      .where('createdAt', '<=', twoMinAgo)
      .where('notifiedAt2min', '==', null)
      .get();

    console.log(`📊 Found ${jobs2min.size} jobs for 2min escalation`);

    for (const doc of jobs2min.docs) {
      const job = doc.data();
      console.log(`📌 Processing 2min job ${doc.id} | type:${job.type} | operator:${job.operatorClockNo}`);

      const creator = await admin.firestore().doc(`employees/${job.operatorClockNo}`).get();
      const mgrs = await getRelevantManagers(job.type);
      const foremen = await getOnsiteDeptForemenShiftLeaders(job.department);
      const creatorData = creator.exists ? creator.data() : null;
      const recipients = [creatorData, ...mgrs, ...foremen].filter(Boolean);

      console.log(`👥 2min recipients: ${recipients.length}`);

      for (const emp of recipients) {
        await sendNotification(emp.fcmToken, 'Escalation: Unassigned Job (2min)', `${job.department} - ${job.machine}\n${job.area} - ${job.part}\n${job.description}`, doc.id);
      }

      await doc.ref.update({ notifiedAt2min: now });
      console.log(`✅ Updated notifiedAt2min for job ${doc.id}`);
    }

    // ==================== 7-MINUTE ESCALATION ====================
    console.log('🔍 Running 7min query: status=open, assignedTo=null, createdAt<=7minAgo, notifiedAt7min=null');
    const jobs7min = await admin.firestore().collection('job_cards')
      .where('status', '==', 'open')
      .where('assignedTo', '==', null)
      .where('createdAt', '<=', sevenMinAgo)
      .where('notifiedAt7min', '==', null)
      .get();

    console.log(`📊 Found ${jobs7min.size} jobs for 7min escalation`);

    for (const doc of jobs7min.docs) {
      const job = doc.data();
      console.log(`📌 Processing 7min job ${doc.id} | type:${job.type} | operator:${job.operatorClockNo}`);

      const creator = await admin.firestore().doc(`employees/${job.operatorClockNo}`).get();
      const mgrs = await getRelevantManagers(job.type);
      const foremen = await getOnsiteDeptForemenShiftLeaders(job.department);
      const deptMgrs = await getDeptManagers(job.department);
      const workshopMgr = await getWorkshopManager();
      const creatorData = creator.exists ? creator.data() : null;
      const recipients = [creatorData, ...mgrs, ...foremen, ...deptMgrs, workshopMgr].filter(Boolean);

      console.log(`👥 7min recipients: ${recipients.length}`);

      for (const emp of recipients) {
        await sendNotification(emp.fcmToken, 'Urgent Escalation: Unassigned Job (7min)', `${job.department} - ${job.machine}\n${job.area} - ${job.part}\n${job.description}`, doc.id);
      }

      await doc.ref.update({ notifiedAt7min: now });
      console.log(`✅ Updated notifiedAt7min for job ${doc.id}`);
    }

    console.log('🎉 escalateNotifications completed successfully');
  } catch (error) {
    console.error('❌ escalateNotifications error:', error);
    throw error; // Re-throw so Cloud Scheduler sees the 500 (for retry logic)
  }
});