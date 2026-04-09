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
    const pos = doc.data().position.toLowerCase();
    return /mechanical|mechanic/i.test(pos) && !/manager/i.test(pos);
  }).map(doc => ({token: doc.data().fcmToken, ...doc.data()}));
}

async function getOnsiteElectricians() {
  const snaps = await admin.firestore().collection('employees').where('isOnSite', '==', true).get();
  return snaps.docs.filter(doc => {
    const pos = doc.data().position.toLowerCase();
    return /electrician|electrical/i.test(pos) && !/manager/i.test(pos);
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
  if (jobType === 'mechanical' || jobType === 'mechanicalElectrical') mgrs.push(mechMgr.data());
  if (jobType === 'electrical' || jobType === 'mechanicalElectrical') mgrs.push(elecMgr.data());
  return mgrs.filter(Boolean);
}

async function getOnsiteDeptForemenShiftLeaders(dept) {
  const snaps = await admin.firestore().collection('employees')
    .where('department', '==', dept)
    .where('isOnSite', '==', true).get();
  return snaps.docs.filter(doc => {
    const pos = doc.data().position.toLowerCase();
    return /foreman|shift leader/i.test(pos);
  }).map(doc => doc.data());
}

async function getDeptManagers(dept) {
  const snaps = await admin.firestore().collection('employees')
    .where('department', '==', dept).get();
  return snaps.docs.filter(doc => /manager/i.test(doc.data().position.toLowerCase())).map(doc => doc.data());
}

async function getWorkshopManager() {
  const snaps = await admin.firestore().collection('employees')
    .where('department', '==', 'Workshop').get();
  return snaps.docs.filter(doc => /manager/i.test(doc.data().position.toLowerCase()) && !/mechanical|electrical/i.test(doc.data().position.toLowerCase())).map(doc => doc.data())[0];
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
exports.onJobCardCreated = functions.firestore.onDocumentCreated({ document: 'jobCards/{jobId}' }, async (event) => {
  const job = event.data.data();
  const recipients = await getInitialRecipients(job.type);
  for (const emp of recipients) {
    await sendNotification(emp.token, 'New Job Available', `${job.department} - ${job.machine}\n${job.area} - ${job.part}\n${job.description}`, event.data.id);
  }
});

exports.onJobCardAssigned = functions.firestore.onDocumentUpdated({ document: 'jobCards/{jobId}' }, async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!before.assignedTo && after.assignedTo) {
    const assignee = await admin.firestore().doc(`employees/${after.assignedTo}`).get();
    if (assignee.exists) {
      await sendNotification(assignee.data().fcmToken, 'New Job Assigned', `${after.department} - ${after.machine}\n${after.area} - ${after.part}\n${after.description}`, event.data.after.id);
    }
  }
});

// Escalation timer
exports.escalateNotifications = functions.scheduler.onSchedule({ schedule: 'every 1 minutes', region: 'us-central1' }, async (event) => {
  const now = admin.firestore.FieldValue.serverTimestamp();
  const twoMinAgo = new Date(Date.now() - 2 * 60 * 1000);
  const sevenMinAgo = new Date(Date.now() - 7 * 60 * 1000);

  // 2min escalation
  const jobs2min = await admin.firestore().collection('jobCards')
    .where('status', '==', 'open')
    .where('assignedTo', '==', null)
    .where('createdAt', '<=', twoMinAgo)
    .where('notifiedAt2min', '==', null).get();
  for (const doc of jobs2min.docs) {
    const job = doc.data();
    const creator = await admin.firestore().doc(`employees/${job.operatorClockNo}`).get();
    const mgrs = await getRelevantManagers(job.type);
    const foremen = await getOnsiteDeptForemenShiftLeaders(job.department);
    const recipients = [creator.data(), ...mgrs, ...foremen].filter(Boolean);
    for (const emp of recipients) {
      await sendNotification(emp.fcmToken, 'Escalation: Unassigned Job (2min)', `${job.department} - ${job.machine}\n${job.area} - ${job.part}\n${job.description}`, doc.id);
    }
    await doc.ref.update({ notifiedAt2min: now });
  }

  // 7min escalation
  const jobs7min = await admin.firestore().collection('jobCards')
    .where('status', '==', 'open')
    .where('assignedTo', '==', null)
    .where('createdAt', '<=', sevenMinAgo)
    .where('notifiedAt7min', '==', null).get();
  for (const doc of jobs7min.docs) {
    const job = doc.data();
    const creator = await admin.firestore().doc(`employees/${job.operatorClockNo}`).get();
    const mgrs = await getRelevantManagers(job.type);
    const foremen = await getOnsiteDeptForemenShiftLeaders(job.department);
    const deptMgrs = await getDeptManagers(job.department);
    const workshopMgr = await getWorkshopManager();
    const recipients = [creator.data(), ...mgrs, ...foremen, ...deptMgrs, workshopMgr].filter(Boolean);
    for (const emp of recipients) {
      await sendNotification(emp.fcmToken, 'Urgent Escalation: Unassigned Job (7min)', `${job.department} - ${job.machine}\n${job.area} - ${job.part}\n${job.description}`, doc.id);
    }
    await doc.ref.update({ notifiedAt7min: now });
  }
});
