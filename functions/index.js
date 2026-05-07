/* eslint-disable max-len */
const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const messaging = admin.messaging();
const db = admin.firestore();

functions.setGlobalOptions({ region: "africa-south1" });

// ==================== HELPER: Log to notifications collection ====================
async function logNotification({
  jobCardId = null,
  jobCardNumber = null,
  triggeredBy,
  sentTo = [],
  level,
  priority = null,
  title,
  body,
  initiatedByClockNo = null,
  initiatedByName = null,
  department = "",
  area = "",
  machine = "",
  part = "",
}) {
  try {
    await db.collection("notifications").add({
      jobCardId,
      jobCardNumber,
      triggeredBy,
      sentTo,
      level,
      priority,
      title,
      body,
      initiatedByClockNo,
      initiatedByName,
      department,
      area,
      machine,
      part,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    console.error("Failed to write to notifications collection:", e);
  }
}

// ==================== HELPER: Get notification level ====================
function getNotificationLevel(priority) {
  if (priority >= 5) return "full-loud";
  if (priority >= 4) return "medium-high";
  return "normal";
}

// ==================== CUSTOM TOKEN AUTH ====================
exports.createCustomToken = functions.https.onCall(async (data, context) => {
  const clockNo = data.clockNo || (data.data && data.data.clockNo) || data;
  if (!clockNo) throw new functions.https.HttpsError("invalid-argument", "clockNo is required");

  const employeeDoc = await db.collection("employees").doc(clockNo).get();
  if (!employeeDoc.exists) throw new functions.https.HttpsError("not-found", "Employee not found");

  const employeeData = employeeDoc.data();
  const uid = `employee_${clockNo}`;

  const customToken = await admin.auth().createCustomToken(uid, {
    clockNo,
    name: employeeData.name || "",
    type: "employee",
  });
  return { customToken };
});

// ==================== SEND JOB ASSIGNMENT NOTIFICATION ====================
exports.sendJobAssignmentNotification = functions.https.onCall(async (data) => {
  const innerData = data.data || data;
  const {
    recipientToken,
    jobCardId,
    jobCardNumber,
    operator,
    creator,
    area,
    description,
    priority = 1,
    initiatedByClockNo,
    initiatedByName,
    department,
    machine,
    part,
    recipientClockNo,
  } = innerData;

  if (!recipientToken) throw new functions.https.HttpsError("invalid-argument", "Missing recipientToken");
  
  // ==================== NEW: P5 On-Site Check ====================
  if (priority >= 5 && recipientClockNo) {
    const empDoc = await db.collection("employees").doc(recipientClockNo).get();
    if (empDoc.exists && empDoc.data().isOnSite !== true) {
      console.log(`🚫 P5 assignment blocked - ${recipientClockNo} is off-site`);
      return { success: false, reason: "Recipient is off-site" };
    }
  }
  // ===============================================================
  const level = getNotificationLevel(priority);
  const title = `Job Assigned by ${operator} #${jobCardNumber || "N/A"}`;
  const body = `Created by ${creator}\nLocation: ${area}\n${description}`;
  const isFullLoud = level === "full-loud";

  const messagePayload = {
    token: recipientToken,
    data: {
      click_action: "FLUTTER_NOTIFICATION_CLICK",
      jobId: jobCardId,
      jobCardNumber: jobCardNumber?.toString() || "Unknown",
      notificationType: "assigned",
      triggeredBy: "job_assigned",
      notificationLevel: level,
      title,
      body,
      chanelId: isFullLoud ? "full_loud_channel" : "normal_channel",
    },
    android: { priority: "high" },
  };

  if (!isFullLoud) {
    messagePayload.notification = { title, body };
  }

  await messaging.send(messagePayload);

  await logNotification({
    jobCardId,
    jobCardNumber,
    triggeredBy: "job_assigned",
    sentTo: [innerData.recipientClockNo || "unknown"],
    level,
    priority,
    title,
    body,
    initiatedByClockNo,
    initiatedByName,
    department,
    area,
    machine,
    part,
  });

  return { success: true };
});

// ==================== SEND CREATOR NOTIFICATION ====================
exports.sendCreatorNotification = functions.https.onCall(async (data) => {
  const innerData = data.data || data;
  const {
    recipientToken,
    jobCardId,
    jobCardNumber,
    area,
    description,
    notificationType,
    assigneeName,
    priority = 1,
    initiatedByClockNo,
    initiatedByName,
    department,
    machine,
    part,
  } = innerData;

  if (!recipientToken || !recipientToken.trim()) {
    throw new functions.https.HttpsError("invalid-argument", "Missing or invalid recipientToken");
  }

  const level = getNotificationLevel(priority);
  const isFullLoud = level === "full-loud";

  let title, body, triggeredByValue;
  if (notificationType === "self_assign") {
    title = `Job Self-Assigned #${jobCardNumber || "N/A"}`;
    body = `${assigneeName} self-assigned\nLocation: ${area}\nDescription: ${description}`;
    triggeredByValue = "self_assigned";
  } else if (notificationType === "closed") {
    title = `Job Completed - Job#${jobCardNumber || "N/A"}`;
    body = `Completed by ${assigneeName}\nLocation: ${area}\nDescription: ${description}`;
    triggeredByValue = "job_closed";
  } else {
    title = `Job Update - Job#${jobCardNumber || "N/A"}`;
    body = `Update from ${assigneeName}\nLocation: ${area}\nDescription: ${description}`;
    triggeredByValue = "job_updated";
  }

  const messagePayload = {
    token: recipientToken,
    data: {
      click_action: "FLUTTER_NOTIFICATION_CLICK",
      jobId: jobCardId,
      notificationType,
      triggeredBy: triggeredByValue,
      notificationLevel: level,
      title,
      body,
    },
    android: { priority: "high" },
  };

  if (!isFullLoud) {
    messagePayload.notification = { title, body };
  }

  await messaging.send(messagePayload);

  await logNotification({
    jobCardId,
    jobCardNumber,
    triggeredBy: triggeredByValue,
    sentTo: [innerData.recipientClockNo || "unknown"],
    level,
    priority,
    title,
    body,
    initiatedByClockNo,
    initiatedByName,
    department,
    area,
    machine,
    part,
  });

  return { success: true };
});

// ==================== DYNAMIC RECIPIENT HELPERS ====================
async function getOnsiteMechanics() {
  const snaps = await db.collection("employees").where("isOnSite", "==", true).get();
  return snaps.docs
    .filter((doc) => {
      const pos = doc.data().position || "";
      const lower = pos.toLowerCase();
      return /mechanical|mechanic/i.test(lower) && !/manager/i.test(lower);
    })
    .map((doc) => ({ token: doc.data().fcmToken, clockNo: doc.id, ...doc.data() }));
}

async function getOnsiteElectricians() {
  const snaps = await db.collection("employees").where("isOnSite", "==", true).get();
  return snaps.docs
    .filter((doc) => {
      const pos = doc.data().position || "";
      const lower = pos.toLowerCase();
      return /electrician|electrical/i.test(lower) && !/manager/i.test(lower);
    })
    .map((doc) => ({ token: doc.data().fcmToken, clockNo: doc.id, ...doc.data() }));
}

async function getInitialRecipients(jobType) {
  if (jobType === "mechanical") return getOnsiteMechanics();
  if (jobType === "electrical") return getOnsiteElectricians();
  return [...(await getOnsiteMechanics()), ...(await getOnsiteElectricians())];
}

async function getRelevantManagers(jobType) {
  const snaps = await db.collection("employees")
    .where("position", "==", "Manager")
    .get();

  return snaps.docs
    .filter((doc) => {
      const dept = doc.data().department || "";
      if (jobType === "mechanical" || jobType === "mechanicalElectrical") {
        return dept.toLowerCase().includes("mechanical");
      }
      if (jobType === "electrical" || jobType === "mechanicalElectrical") {
        return dept.toLowerCase().includes("electrical");
      }
      return false;
    })
    .map((doc) => ({ token: doc.data().fcmToken, clockNo: doc.id, ...doc.data() }));
}

async function getOnsiteDeptForemenShiftLeaders(dept) {
  const snaps = await db.collection("employees")
    .where("department", "==", dept)
    .where("isOnSite", "==", true)
    .get();

  return snaps.docs
    .filter((doc) => {
      const pos = (doc.data().position || "").toLowerCase();
      return /foreman|shift leader/i.test(pos);
    })
    .map((doc) => ({ token: doc.data().fcmToken, clockNo: doc.id, ...doc.data() }));
}

async function getDeptManagers(dept) {
  const snaps = await db.collection("employees")
    .where("department", "==", dept)
    .get();

  return snaps.docs
    .filter((doc) => {
      const pos = (doc.data().position || "").toLowerCase();
      return /manager/i.test(pos);
    })
    .map((doc) => ({ token: doc.data().fcmToken, clockNo: doc.id, ...doc.data() }));
}

async function getWorkshopManager() {
  const snaps = await db.collection("employees")
    .where("department", "==", "Workshop")
    .get();

  return snaps.docs
    .filter((doc) => {
      const pos = (doc.data().position || "").toLowerCase();
      return /manager/i.test(pos) && !/mechanical|electrical/i.test(pos);
    })
    .map((doc) => ({ token: doc.data().fcmToken, clockNo: doc.id, ...doc.data() }))[0] || null;
}

// ==================== CORE SEND NOTIFICATION ====================
async function sendNotification({
  token,
  title,
  body,
  jobCardNumber,
  level,
  priority,
  createdBy,
  department,
  area,
  machine,
  part,
  triggeredBy,
  initiatedByClockNo = null,
  initiatedByName = null,
}) {
  if (!token) return;

  const isFullLoud = level === "full-loud";

  const messagePayload = {
    token,
    data: {
      click_action: "FLUTTER_NOTIFICATION_CLICK",
      jobCardNumber: jobCardNumber?.toString() || "",
      notificationLevel: level,
      triggeredBy,
      priority: priority?.toString() || "",
      createdBy: createdBy || "Unknown",
      department: department || "",
      area: area || "",
      machine: machine || "",
      part: part || "",
      title,
      body,
    },
    android: { priority: "high" },
  };

  if (!isFullLoud) {
    messagePayload.notification = { title, body };
  }

  try {
    await messaging.send(messagePayload);

    await logNotification({
      jobCardNumber,
      triggeredBy,
      sentTo: [token],
      level,
      priority,
      title,
      body,
      initiatedByClockNo,
      initiatedByName,
      department,
      area,
      machine,
      part,
    });
  } catch (e) {
    console.error("FCM send error:", e);
  }
}

// ==================== FIRESTORE TRIGGER: JOB CREATED ====================
exports.onJobCardCreated = functions.firestore.onDocumentCreated({ document: "job_cards/{jobId}" }, async (event) => {
  const job = event.data.data();
  const jobId = event.params.jobId;
  const priority = job.priority || 1;
  const level = getNotificationLevel(priority);

  const recipients = await getInitialRecipients(job.type);

  if (priority >= 5 && job.operatorClockNo) {
    const creatorDoc = await db.collection("employees").doc(job.operatorClockNo).get();
    if (creatorDoc.exists) recipients.push(creatorDoc.data());
  }

  const createdBy = job.operator || "Unknown";

  const title = `Job #${job.jobCardNumber || jobId} - Priority ${priority} - ${createdBy}`;
  const body = job.description;

  for (const emp of recipients) {
    await sendNotification({
      token: emp.token,
      title,
      body,
      jobCardNumber: job.jobCardNumber || jobId,
      level,
      priority,
      createdBy,
      department: job.department,
      area: job.area,
      machine: job.machine,
      part: job.part,
      triggeredBy: "job_created",
      initiatedByClockNo: job.operatorClockNo || null,
      initiatedByName: createdBy,
    });
  }
});

// ==================== FIRESTORE TRIGGER: JOB ASSIGNED ====================
exports.onJobCardAssigned = functions.firestore.onDocumentUpdated({ document: "job_cards/{jobId}" }, async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();

  if (!before.assignedTo && after.assignedTo) {
    const priority = after.priority || 1;
    const level = getNotificationLevel(priority);

    const assigneeDoc = await db.collection("employees").doc(after.assignedTo).get();
    if (assigneeDoc.exists) {
      await sendNotification({
        token: assigneeDoc.data().fcmToken,
        title: "New Job Assigned",
        body: `${after.department} - ${after.machine}\n${after.area} - ${after.part}\n${after.description}`,
        jobCardNumber: after.jobCardNumber || event.params.jobId,
        level,
        priority,
        createdBy: after.operator || "Unknown",
        department: after.department,
        area: after.area,
        machine: after.machine,
        part: after.part,
        triggeredBy: "job_assigned",
        initiatedByClockNo: after.lastUpdatedBy || null,
        initiatedByName: after.lastUpdatedByName || null,
      });
    }
  }
});

// ==================== SCHEDULED: ESCALATION ====================
exports.escalateNotifications = functions.scheduler.onSchedule({
  schedule: "every 2 minutes",
  region: "europe-west1",
  timeZone: "Africa/Johannesburg",
}, async () => {
  const now = admin.firestore.FieldValue.serverTimestamp();
  const twoMinAgo = new Date(Date.now() - 2 * 60 * 1000);
  const sevenMinAgo = new Date(Date.now() - 7 * 60 * 1000);

  // 2-minute escalation
  const jobs2min = await db.collection("job_cards")
    .where("status", "==", "open")
    .where("assignedClockNos", "==", null)
    .where("createdAt", "<=", twoMinAgo)
    .where("notifiedAt2min", "==", null)
    .get();

  for (const doc of jobs2min.docs) {
    const job = doc.data();
    const priority = job.priority || 1;
    const level = priority <= 3 ? "normal" : "medium-high";

    const creatorDoc = await db.collection("employees").doc(job.operatorClockNo).get();
    const createdBy = creatorDoc.exists ? creatorDoc.data().name : "Unknown";

    // ==================== UPDATED: Only get ON-SITE people ====================
    const mgrs = await getOnsiteRelevantManagers(job.type);           // ← Changed
    const foremen = await getOnsiteDeptForemenShiftLeaders(job.department);

    const recipients = [
      creatorDoc.exists ? creatorDoc.data() : null,
      ...mgrs,
      ...foremen,
    ].filter(Boolean);
    // ========================================================================

    for (const emp of recipients) {
      await sendNotification({
        token: emp.token,
        title: "Escalation: Unassigned Job (2min)",
        body: `${job.department} - ${job.machine}\n${job.area} - ${job.part}\n${job.description}`,
        jobCardNumber: job.jobCardNumber || doc.id,
        level,
        priority,
        createdBy,
        department: job.department,
        area: job.area,
        machine: job.machine,
        part: job.part,
        triggeredBy: "2min_escalation",
        initiatedByClockNo: null,
        initiatedByName: null,
      });
    }
    await doc.ref.update({ notifiedAt2min: now });
  }

  // 7-minute escalation
  const jobs7min = await db.collection("job_cards")
    .where("status", "==", "open")
    .where("assignedClockNos", "==", null)
    .where("createdAt", "<=", sevenMinAgo)
    .where("notifiedAt7min", "==", null)
    .get();

  for (const doc of jobs7min.docs) {
    const job = doc.data();
    const priority = job.priority || 1;
    const level = priority <= 3 ? "normal" : "full-loud";

    const creatorDoc = await db.collection("employees").doc(job.operatorClockNo).get();

    // ==================== UPDATED: Only get ON-SITE people ====================
    const mgrs = await getOnsiteRelevantManagers(job.type);           // ← Changed
    const foremen = await getOnsiteDeptForemenShiftLeaders(job.department);
    const deptMgrs = await getOnsiteDeptManagers(job.department);     // ← Changed
    const workshopMgr = await getOnsiteWorkshopManager();             // ← Changed

    const recipients = [
      creatorDoc.exists ? creatorDoc.data() : null,
      ...mgrs,
      ...foremen,
      ...deptMgrs,
      workshopMgr,
    ].filter(Boolean);
    // ========================================================================

    for (const emp of recipients) {
      await sendNotification({
        token: emp.token,
        title: "Urgent Escalation: Unassigned Job (7min)",
        body: `${job.department} - ${job.machine}\n${job.area} - ${job.part}\n${job.description}`,
        jobCardNumber: job.jobCardNumber || doc.id,
        level,
        priority,
        createdBy: creatorDoc.exists ? creatorDoc.data().name : "Unknown",
        department: job.department,
        area: job.area,
        machine: job.machine,
        part: job.part,
        triggeredBy: "7min_escalation",
        initiatedByClockNo: null,
        initiatedByName: null,
      });
    }
    await doc.ref.update({ notifiedAt7min: now });
  }
});

// ==================== SCHEDULED: AUTO-CLOSE MONITORING JOBS ====================
exports.autoCloseMonitoringJobs = functions.scheduler.onSchedule({
  schedule: "0 8 * * *",
  region: "europe-west1",
  timeZone: "Africa/Johannesburg",
}, async () => {
  const now = admin.firestore.Timestamp.now();
  const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);

  const monitoringJobs = await db.collection("job_cards")
    .where("status", "==", "monitor")
    .where("monitoringStartedAt", "<=", admin.firestore.Timestamp.fromDate(sevenDaysAgo))
    .get();

  const batch = db.batch();
  let closedCount = 0;

  for (const doc of monitoringJobs.docs) {
    const job = doc.data();
    const monitoringStartedAt = job.monitoringStartedAt?.toDate();
    const lastUpdatedAt = job.lastUpdatedAt?.toDate();

    if (monitoringStartedAt && lastUpdatedAt) {
      const sevenDaysAfterStart = new Date(monitoringStartedAt.getTime() + 7 * 24 * 60 * 60 * 1000);
      if (lastUpdatedAt <= sevenDaysAfterStart) {
        const autoNote = `\n\n[${now.toDate().toLocaleString()}] Auto-closed: 7-day monitoring complete, no adjustments.`;
        batch.update(doc.ref, {
          status: "closed",
          closedAt: now,
          monitoringStartedAt: null,
          notes: (job.notes || "") + autoNote,
        });
        closedCount++;
      }
    }
  }

  if (closedCount > 0) await batch.commit();
});

// ==================== COPPER SELL NOTIFICATION ====================
exports.onCopperTransactionWrite = functions.firestore.onDocumentWritten({ document: "copperTransactions/{docId}" }, async (event) => {
  const after = event.data.after.data();
  if (!after) return;

  const sellTypes = ["sellNuggets", "sellRods"];
  const snapshot = await db.collection("copperTransactions").where("type", "in", sellTypes).get();
  const sellTotal = snapshot.docs.reduce((sum, d) => sum + (d.data().kg || 0), 0);

  if (sellTotal > 400) {
    const emp22 = await db.collection("employees").doc("22").get();
    if (emp22.exists && emp22.data().fcmToken) {
      await messaging.send({
        token: emp22.data().fcmToken,
        notification: { title: "Copper Sell Ready", body: `Total sell copper: ${sellTotal}kg` },
        data: { click_action: "FLUTTER_NOTIFICATION_CLICK", triggeredBy: "copper_sell" },
        android: { priority: "high" },
      });

      await logNotification({
        triggeredBy: "copper_sell",
        sentTo: ["22"],
        level: "normal",
        title: "Copper Sell Ready",
        body: `Total sell copper: ${sellTotal}kg`,
        initiatedByClockNo: null,
        initiatedByName: null,
      });
    }
  }
});

// ==================== ALERT RESPONSE HANDLER (Busy + Dismissed) ====================
exports.onAlertResponseCreated = functions.firestore
  .onDocumentCreated("alertResponses/{responseId}", async (event) => {
    const response = event.data.data();
    const responseId = event.params.responseId;

    const jobCardNumber = response.jobCardNumber;
    const clockNo = response.clockNo || response.userClockNo || "unknown";
    const userName = response.userName || response.user || "Unknown User";

    if (!jobCardNumber) {
      console.error("No jobCardNumber in alertResponse");
      return null;
    }

    // Find the job
    const jobSnap = await db.collection("job_cards")
      .where("jobCardNumber", "==", parseInt(jobCardNumber))
      .limit(1)
      .get();

    if (jobSnap.empty) {
      console.error(`Job #${jobCardNumber} not found`);
      return null;
    }

    const job = jobSnap.docs[0].data();
    const creatorClockNo = job.operatorClockNo;

    // ==================== BUSY ====================
    if (response.action === "busy") {
      if (!creatorClockNo) {
        console.error("Job has no operatorClockNo");
        return null;
      }

      const creatorDoc = await db.collection("employees").doc(creatorClockNo).get();
      if (!creatorDoc.exists || !creatorDoc.data().fcmToken) {
        console.error(`Creator ${creatorClockNo} has no FCM token`);
        return null;
      }

      const creatorToken = creatorDoc.data().fcmToken;

      const title = `Busy Response - Job #${jobCardNumber}`;
      const body = `${userName} (${clockNo}) is busy and cannot take this job right now.`;

      await messaging.send({
        token: creatorToken,
        notification: { title, body },
        data: {
          click_action: "FLUTTER_NOTIFICATION_CLICK",
          jobCardNumber: jobCardNumber.toString(),
          triggeredBy: "busy_response",
          busyClockNo: clockNo,
          busyUserName: userName,
        },
        android: { priority: "high" },
      });

      await logNotification({
        jobCardId: jobSnap.docs[0].id,
        jobCardNumber: parseInt(jobCardNumber),
        triggeredBy: "busy_response",
        sentTo: [creatorClockNo],
        level: "normal",
        priority: job.priority || null,
        title,
        body,
        initiatedByClockNo: clockNo,
        initiatedByName: userName,
        department: job.department,
        area: job.area,
        machine: job.machine,
        part: job.part,
      });

      console.log(`✅ Busy notification sent to creator ${creatorClockNo} for Job #${jobCardNumber}`);
      return null;
    }

    // ==================== DISMISSED ====================
    if (response.action === "dismissed") {
      console.log(`Alert dismissed for Job #${jobCardNumber} by ${userName} (${clockNo})`);

      // Optional: log dismissed actions too
      await logNotification({
        jobCardId: jobSnap.docs[0].id,
        jobCardNumber: parseInt(jobCardNumber),
        triggeredBy: "alert_dismissed",
        sentTo: [],
        level: "normal",
        priority: job.priority || null,
        title: `Alert Dismissed - Job #${jobCardNumber}`,
        body: `${userName} (${clockNo}) dismissed the alert`,
        initiatedByClockNo: clockNo,
        initiatedByName: userName,
        department: job.department,
        area: job.area,
        machine: job.machine,
        part: job.part,
      });

      return null;
    }

    console.log(`Ignoring alertResponse ${responseId} with action: ${response.action}`);
    return null;
  });

// ==================== MIGRATION HELPERS ====================
exports.migrateEmployeeIds = functions.https.onCall(async () => {
  const employeesRef = db.collection("employees");
  const snapshot = await employeesRef.get();
  const migrated = [];
  const batch = db.batch();

  for (const doc of snapshot.docs) {
    const docData = doc.data();
    const clockNo = docData.clockNo;
    if (doc.id !== clockNo) {
      const newRef = employeesRef.doc(clockNo);
      batch.set(newRef, docData);
      batch.delete(doc.ref);
      migrated.push({ oldId: doc.id, newId: clockNo, name: docData.name });
    }
  }

  await batch.commit();
  console.log(`Migrated ${migrated.length} employee docs`);
  return { migrated, count: migrated.length };
});

// ==================== NEW: On-site only manager helpers ====================
async function getOnsiteRelevantManagers(jobType) {
  const snaps = await db.collection("employees")
    .where("position", "==", "Manager")
    .where("isOnSite", "==", true)
    .get();

  return snaps.docs
    .filter((doc) => {
      const dept = doc.data().department || "";
      if (jobType === "mechanical" || jobType === "mechanicalElectrical") {
        return dept.toLowerCase().includes("mechanical");
      }
      if (jobType === "electrical" || jobType === "mechanicalElectrical") {
        return dept.toLowerCase().includes("electrical");
      }
      return false;
    })
    .map((doc) => ({ token: doc.data().fcmToken, clockNo: doc.id, ...doc.data() }));
}

async function getOnsiteDeptManagers(dept) {
  const snaps = await db.collection("employees")
    .where("department", "==", dept)
    .where("isOnSite", "==", true)
    .get();

  return snaps.docs
    .filter((doc) => {
      const pos = (doc.data().position || "").toLowerCase();
      return /manager/i.test(pos);
    })
    .map((doc) => ({ token: doc.data().fcmToken, clockNo: doc.id, ...doc.data() }));
}

async function getOnsiteWorkshopManager() {
  const snaps = await db.collection("employees")
    .where("department", "==", "Workshop")
    .where("isOnSite", "==", true)
    .get();

  return snaps.docs
    .filter((doc) => {
      const pos = (doc.data().position || "").toLowerCase();
      return /manager/i.test(pos) && !/mechanical|electrical/i.test(pos);
    })
    .map((doc) => ({ token: doc.data().fcmToken, clockNo: doc.id, ...doc.data() }))[0] || null;
}

exports.migrateJobStatuses = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
  }

  const snapshot = await db.collection("job_cards").get();
  if (snapshot.empty) return { message: "No job cards found.", updated: 0 };

  const batch = db.batch();
  let updatedCount = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const currentStatus = data.status;
    let newStatus = currentStatus;

    if (currentStatus === "completed") newStatus = "closed";
    else if (currentStatus === "monitoring") newStatus = "monitor";

    if (newStatus !== currentStatus) {
      batch.update(doc.ref, { status: newStatus });
      updatedCount++;
    }
  }

  if (updatedCount > 0) {
    await batch.commit();
    return { message: `Migration completed! Updated ${updatedCount} job cards.`, updated: updatedCount };
  } else {
    return { message: "No job cards needed status updates.", updated: 0 };
  }
});