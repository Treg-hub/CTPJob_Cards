/* eslint-disable max-len */
const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const messaging = admin.messaging();

functions.setGlobalOptions({ region: "africa-south1" });

// ==================== Custom Token Auth (Option B) ====================
exports.createCustomToken = functions.https.onCall(async (data, context) => {
  const clockNo = data.clockNo || (data.data && data.data.clockNo) || data;

  console.log("🔄 createCustomToken called with clockNo:", clockNo);

  if (!clockNo) {
    console.error("❌ Missing clockNo");
    throw new functions.https.HttpsError("invalid-argument", "clockNo is required");
  }

  try {
    console.log("🔍 Looking up employee doc:", clockNo);
    const employeeDoc = await admin.firestore().collection("employees").doc(clockNo).get();

    if (!employeeDoc.exists) {
      console.error("❌ Employee not found for clockNo:", clockNo);
      throw new functions.https.HttpsError("not-found", "Employee not found");
    }

    const employeeData = employeeDoc.data();
    console.log("✅ Employee found:", employeeData.name);

    const uid = `employee_${clockNo}`;
    console.log("🔑 Creating custom token for UID:", uid);

    const customToken = await admin.auth().createCustomToken(uid, {
      clockNo: clockNo,
      name: employeeData.name || "",
      type: "employee",
    });

    console.log("✅ Custom token successfully created for", clockNo);
    return { customToken };
  } catch (error) {
    console.error("💥 Error in createCustomToken:", error);
    throw new functions.https.HttpsError("internal", "Failed to create custom token", error);
  }
});
// ==========================================================================

/**
 * Gets notification level based on priority.
 */
function getNotificationLevel(priority) {
  if (priority >= 5) return "full-loud";
  if (priority >= 4) return "medium-high";
  return "normal";
}

exports.sendJobAssignmentNotification = functions.https.onCall(async (data) => {
  const innerData = data.data || data;
  const { recipientToken, jobCardId, jobCardNumber, operator, creator, area, description, priority = 1 } = innerData;

  if (!recipientToken) throw new functions.https.HttpsError("invalid-argument", "Missing recipientToken");

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
      notificationLevel: level,
      title,
      body,
      chanelId: isFullLoud ? "full_loud_channel" : "normal_channel",
    },
    android: {
      priority: "high"
    },
  };

  if (!isFullLoud) {
    messagePayload.notification = { title, body };
  }

  try {
    const response = await messaging.send(messagePayload);
    return { success: true, messageId: response };
  } catch (error) {
    console.error("FCM Error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

exports.sendCreatorNotification = functions.https.onCall(async (data) => {
  const innerData = data.data || data;
  const recipientToken = innerData.recipientToken;
  const jobCardId = innerData.jobCardId;
  const jobCardNumber = innerData.jobCardNumber;
  const area = innerData.area;
  const description = innerData.description;
  const notificationType = innerData.notificationType;
  const assigneeName = innerData.assigneeName;
  const priority = innerData.priority || 1;
  const level = getNotificationLevel(priority);
  const isFullLoud = level === "full-loud";

  if (!recipientToken || !recipientToken.trim()) {
    throw new functions.https.HttpsError("invalid-argument", "Missing or invalid recipientToken");
  }

  let title; let body;
  if (notificationType === "self_assign") {
    title = `Job Self-Assigned #${jobCardNumber || "N/A"}`;
    body = `${assigneeName} self-assigned\nLocation: ${area}\nDescription: ${description}`;
  } else if (notificationType === "closed") {
    title = `Job Completed - Job#${jobCardNumber || "N/A"}`;
    body = `Completed by ${assigneeName}\nLocation: ${area}\nDescription: ${description}`;
  } else {
    title = `Job Update - Job#${jobCardNumber || "N/A"}`;
    body = `Update from ${assigneeName}\nLocation: ${area}\nDescription: ${description}`;
  }

  const messagePayload = {
    token: recipientToken,
    data: {
      click_action: "FLUTTER_NOTIFICATION_CLICK",
      jobId: jobCardId,
      notificationType: notificationType,
      notificationLevel: level,
      title,
      body,
    },
    android: { priority: "high" },
  };

  // Only add notification payload for non-P5 jobs
  if (!isFullLoud) {
    messagePayload.notification = { title, body };
  }

  try {
    const response = await messaging.send(messagePayload);
    console.log("✅ Creator notification sent successfully");
    return { success: true, messageId: response };
  } catch (error) {
    console.error("Creator FCM Error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

async function getOnsiteMechanics() {
  const snaps = await admin.firestore().collection("employees").where("isOnSite", "==", true).get();
  return snaps.docs.filter((doc) => {
    const pos = doc.data().position;
    if (!pos || typeof pos !== "string") return false;
    const lowerPos = pos.toLowerCase();
    return /mechanical|mechanic/i.test(lowerPos) && !/manager/i.test(lowerPos);
  }).map((doc) => ({token: doc.data().fcmToken, ...doc.data()}));
}

async function getOnsiteElectricians() {
  const snaps = await admin.firestore().collection("employees").where("isOnSite", "==", true).get();
  return snaps.docs.filter((doc) => {
    const pos = doc.data().position;
    if (!pos || typeof pos !== "string") return false;
    const lowerPos = pos.toLowerCase();
    return /electrician|electrical/i.test(lowerPos) && !/manager/i.test(lowerPos);
  }).map((doc) => ({token: doc.data().fcmToken, ...doc.data()}));
}

async function getInitialRecipients(jobType) {
  if (jobType === "mechanical") return getOnsiteMechanics();
  if (jobType === "electrical") return getOnsiteElectricians();
  return [...await getOnsiteMechanics(), ...await getOnsiteElectricians()];
}

async function getRelevantManagers(jobType) {
  const mechMgr = await admin.firestore().doc("employees/23194").get();
  const elecMgr = await admin.firestore().doc("employees/23162").get();
  const mgrs = [];
  if (jobType === "mechanical" || jobType === "mechanicalElectrical") if (mechMgr.exists) mgrs.push(mechMgr.data());
  if (jobType === "electrical" || jobType === "mechanicalElectrical") if (elecMgr.exists) mgrs.push(elecMgr.data());
  return mgrs.filter(Boolean);
}

async function getOnsiteDeptForemenShiftLeaders(dept) {
  const snaps = await admin.firestore().collection("employees")
      .where("department", "==", dept)
      .where("isOnSite", "==", true).get();
  return snaps.docs.filter((doc) => {
    const pos = doc.data().position;
    if (!pos || typeof pos !== "string") return false;
    const lowerPos = pos.toLowerCase();
    return /foreman|shift leader/i.test(lowerPos);
  }).map((doc) => doc.data());
}

async function getDeptManagers(dept) {
  const snaps = await admin.firestore().collection("employees")
      .where("department", "==", dept).get();
  return snaps.docs.filter((doc) => {
    const pos = doc.data().position;
    if (!pos || typeof pos !== "string") return false;
    const lowerPos = pos.toLowerCase();
    return /manager/i.test(lowerPos);
  }).map((doc) => doc.data());
}

async function getWorkshopManager() {
  const snaps = await admin.firestore().collection("employees")
      .where("department", "==", "Workshop").get();
  return snaps.docs.filter((doc) => {
    const pos = doc.data().position;
    if (!pos || typeof pos !== "string") return false;
    const lowerPos = pos.toLowerCase();
    return /manager/i.test(lowerPos) && !/mechanical|electrical/i.test(lowerPos);
  }).map((doc) => doc.data())[0];
}

async function sendNotification(token, title, body, jobCardNumber, level, priority, createdBy, department, area, location, part) {
  if (!token) return;

  const isFullLoud = level === "full-loud";

  const messagePayload = {
    token,
    data: {
      click_action: "FLUTTER_NOTIFICATION_CLICK",
      jobCardNumber: jobCardNumber.toString(),
      notificationLevel: level,
      priority: priority.toString(),
      createdBy: createdBy || "Unknown",
      department: department || "",
      area: area || "",
      location: location || "",
      part: part || "",
      title,
      body,
    },
    android: {
      priority: "high",
    },
  };

  if (!isFullLoud) {
    messagePayload.notification = { title, body };
  }

  try {
    await messaging.send(messagePayload);
  } catch (e) {
    console.error("FCM send error for token:", token, e);
  }
}

exports.onJobCardCreated = functions.firestore.onDocumentCreated({document: "job_cards/{jobId}"}, async (event) => {
  const job = event.data.data();
  const jobId = event.params.jobId;                    // ← Clean job ID
  const priority = job.priority || 1;
  const level = getNotificationLevel(priority);
  const recipients = await getInitialRecipients(job.type);

  const creator = await admin.firestore().doc(`employees/${job.operatorClockNo}`).get();
  const createdBy = creator.exists ? creator.data().name : "Unknown";

  if (priority >= 5) {
    if (creator.exists) recipients.push(creator.data());
  }

  console.log(`Job ${jobId} priority: ${priority}, level: ${level}, recipients: ${recipients.length}`);

  const title = `Job #${job.jobCardNumber || jobId} - Priority ${priority} - ${createdBy}`;
  const body = job.description;
  const subtext = `${job.department} > ${job.area} > ${job.machine} > ${job.part}`;

  for (const emp of recipients) {
    await sendNotification(emp.token, title, body, job.jobCardNumber || jobId, level, priority, createdBy, job.department, job.area, job.machine, job.part);
  }
});

exports.onJobCardAssigned = functions.firestore.onDocumentUpdated({document: "job_cards/{jobId}"}, async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!before.assignedTo && after.assignedTo) {
    const priority = after.priority || 1;
    const level = getNotificationLevel(priority);
    const assignee = await admin.firestore().doc(`employees/${after.assignedTo}`).get();
    const creator = await admin.firestore().doc(`employees/${after.operatorClockNo}`).get();
    const createdBy = creator.exists ? creator.data().name : "Unknown";
    if (assignee.exists) {
      await sendNotification(assignee.data().fcmToken, "New Job Assigned", `${after.department} - ${after.machine}\n${after.area} - ${after.part}\n${after.description}`, after.jobCardNumber || event.data.after.id, level, priority, createdBy, after.department, after.area, after.machine, after.part);
    }
  }
});

exports.escalateNotifications = functions.scheduler.onSchedule({
  schedule: "every 2 minutes",
  region: "europe-west1",
  timeZone: "Africa/Johannesburg",
}, async (event) => {
  console.log("🚀 escalateNotifications started at", new Date().toISOString());
  try {
    const now = admin.firestore.FieldValue.serverTimestamp();
    const oneMinAgo = new Date(Date.now() - 1 * 60 * 1000);
    const twoMinAgo = new Date(Date.now() - 2 * 60 * 1000);
    const sevenMinAgo = new Date(Date.now() - 7 * 60 * 1000);



    const jobs2min = await admin.firestore().collection("job_cards")
        .where("status", "==", "open")
        .where("assignedClockNos", "==", null)
        .where("createdAt", "<=", twoMinAgo)
        .where("notifiedAt2min", "==", null)
        .get();

    for (const doc of jobs2min.docs) {
      const job = doc.data();
      const priority = job.priority || 1;
      const level = priority <= 3 ? "normal" : "medium-high";
      const creator = await admin.firestore().doc(`employees/${job.operatorClockNo}`).get();
      const createdBy = creator.exists ? creator.data().name : "Unknown";
      const mgrs = await getRelevantManagers(job.type);
      const foremen = await getOnsiteDeptForemenShiftLeaders(job.department);
      const creatorData = creator.exists ? creator.data() : null;
      const recipients = [creatorData, ...mgrs, ...foremen].filter(Boolean);
      for (const emp of recipients) {
        await sendNotification(emp.fcmToken, "Escalation: Unassigned Job (2min)", `${job.department} - ${job.machine}\n${job.area} - ${job.part}\n${job.description}`, job.jobCardNumber || doc.id, level, priority, createdBy, job.department, job.area, job.machine, job.part);
      }
      await doc.ref.update({notifiedAt2min: now});
    }

    const jobs7min = await admin.firestore().collection("job_cards")
        .where("status", "==", "open")
        .where("assignedClockNos", "==", null)
        .where("createdAt", "<=", sevenMinAgo)
        .where("notifiedAt7min", "==", null)
        .get();

    for (const doc of jobs7min.docs) {
      const job = doc.data();
      const priority = job.priority || 1;
      const level = priority <= 3 ? "normal" : "full-loud";
      const creator = await admin.firestore().doc(`employees/${job.operatorClockNo}`).get();
      const mgrs = await getRelevantManagers(job.type);
      const foremen = await getOnsiteDeptForemenShiftLeaders(job.department);
      const deptMgrs = await getDeptManagers(job.department);
      const workshopMgr = await getWorkshopManager();
      const creatorData = creator.exists ? creator.data() : null;
      const recipients = [creatorData, ...mgrs, ...foremen, ...deptMgrs, workshopMgr].filter(Boolean);
      for (const emp of recipients) {
        await sendNotification(emp.fcmToken, "Urgent Escalation: Unassigned Job (7min)", `${job.department} - ${job.machine}\n${job.area} - ${job.part}\n${job.description}`, job.jobCardNumber || doc.id, level, priority);
      }
      await doc.ref.update({notifiedAt7min: now});
    }
    console.log("🎉 escalateNotifications completed successfully");
  } catch (error) {
    console.error("❌ escalateNotifications error:", error);
    throw error;
  }
});

exports.migrateEmployeeIds = functions.https.onCall(async (data, context) => {
  const employeesRef = admin.firestore().collection("employees");
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
  console.log(`Migrated ${migrated.length} employee docs`);
  return {migrated, count: migrated.length};
});

exports.autoCloseMonitoringJobs = functions.scheduler.onSchedule({
  schedule: "0 8 * * *",
  region: "europe-west1",
  timeZone: "Africa/Johannesburg",
}, async (event) => {
  console.log("🚀 autoCloseMonitoringJobs started at", new Date().toISOString());
  try {
    const now = admin.firestore.Timestamp.now();
    const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const monitoringJobs = await admin.firestore().collection("job_cards")
        .where("status", "==", "monitor")
        .where("monitoringStartedAt", "<=", admin.firestore.Timestamp.fromDate(sevenDaysAgo))
        .get();

    const batch = admin.firestore().batch();
    let closedCount = 0;

    for (const doc of monitoringJobs.docs) {
      const job = doc.data();
      const monitoringStartedAt = job.monitoringStartedAt ? job.monitoringStartedAt.toDate() : null;
      const lastUpdatedAt = job.lastUpdatedAt ? job.lastUpdatedAt.toDate() : null;

      if (monitoringStartedAt && lastUpdatedAt) {
        const sevenDaysAfterStart = new Date(monitoringStartedAt.getTime() + 7 * 24 * 60 * 60 * 1000);
        if (lastUpdatedAt <= sevenDaysAfterStart) {
          const autoNote = `\n\n[${now.toDate().toLocaleString()}] Auto-closed: 7-day monitoring complete, no adjustments.`;
          const currentNotes = job.notes || "";
          batch.update(doc.ref, {
            status: "closed",
            closedAt: now,
            monitoringStartedAt: null,
            notes: currentNotes + autoNote,
          });
          closedCount++;
        }
      }
    }

    if (closedCount > 0) {
      await batch.commit();
      console.log(`🎉 Auto-closed ${closedCount} jobs`);
    } else {
      console.log("ℹ️ No jobs to auto-close");
    }
  } catch (error) {
    console.error("❌ autoCloseMonitoringJobs error:", error);
    throw error;
  }
});

exports.onCopperTransactionWrite = functions.firestore.onDocumentWritten({document: "copperTransactions/{docId}"}, async (event) => {
  try {
    const after = event.data.after.data();
    if (!after) return;

    const sellTypes = ["sellNuggets", "sellRods"];
    const snapshot = await admin.firestore().collection("copperTransactions")
        .where("type", "in", sellTypes)
        .get();

    const sellTotal = snapshot.docs.reduce((sum, doc) => sum + (doc.data().kg || 0), 0);

    if (sellTotal > 400) {
      const emp22 = await admin.firestore().doc("employees/22").get();
      if (emp22.exists && emp22.data().fcmToken) {
        await messaging.send({
          token: emp22.data().fcmToken,
          notification: {
            title: "Copper Sell Ready",
            body: `Total sell copper: ${sellTotal}kg`,
          },
          data: {click_action: "FLUTTER_NOTIFICATION_CLICK"},
          android: {priority: "high"},
        });
      }
    }
  } catch (error) {
    console.error("❌ Copper notification error:", error);
  }
});

exports.migrateJobStatuses = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
  }

  try {
    const db = admin.firestore();
    const snapshot = await db.collection("job_cards").get();

    if (snapshot.empty) {
      return {message: "No job cards found.", updated: 0};
    }

    const batch = db.batch();
    let updatedCount = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const currentStatus = data.status;
      let newStatus = currentStatus;

      if (currentStatus === "completed") newStatus = "closed";
      else if (currentStatus === "monitoring") newStatus = "monitor";

      if (newStatus !== currentStatus) {
        batch.update(doc.ref, {status: newStatus});
        updatedCount++;
      }
    }

    if (updatedCount > 0) {
      await batch.commit();
      return { message: `Migration completed! Updated ${updatedCount} job cards.`, updated: updatedCount };
    } else {
      return {message: "No job cards needed status updates.", updated: 0};
    }
  } catch (error) {
    console.error("Migration failed:", error);
    throw new functions.https.HttpsError("internal", "Migration failed: " + error.message);
  }
});

// ==================== BUSY NOTIFICATION ====================
exports.sendBusyNotification = functions.https.onCall(async (data, context) => {
  const innerData = data.data || data;
  const { jobCardNumber, originalOperator, busyUserName, busyUserId } = innerData;

  if (!jobCardNumber || !originalOperator) {
    throw new functions.https.HttpsError("invalid-argument", "Missing jobCardNumber or originalOperator");
  }

  try {
    // Find the original operator by clockNo
    const operatorSnap = await admin.firestore()
      .collection("employees")
      .where("clockNo", "==", originalOperator)
      .limit(1)
      .get();

    if (operatorSnap.empty) {
      console.log(`No employee found with clockNo: ${originalOperator}`);
      return { success: false, message: "Operator not found" };
    }

    const operatorDoc = operatorSnap.docs[0];
    const fcmToken = operatorDoc.data().fcmToken;

    if (!fcmToken) {
      console.log(`No FCM token for operator: ${originalOperator}`);
      return { success: false, message: "No FCM token" };
    }

    const title = "User is Busy";
    const body = `${busyUserName || "Someone"} is busy elsewhere and cannot take Job #${jobCardNumber}`;

    const messagePayload = {
      token: fcmToken,
      data: {
        click_action: "FLUTTER_NOTIFICATION_CLICK",
        jobCardNumber: jobCardNumber.toString(),
        notificationLevel: "medium-high",
        type: "busy_response",
        title,
        body,
      },
      android: { priority: "high" },
      notification: { title, body }   // Always show visible banner
    };

    await messaging.send(messagePayload);

    // Log the busy event for audit
    await admin.firestore().collection("busyLogs").add({
      jobCardNumber,
      busyUserId: busyUserId || "unknown",
      busyUserName: busyUserName || "Unknown",
      originalOperator,
      timestamp: admin.firestore.FieldValue.serverTimestamp()
    });

    console.log(`✅ Busy notification sent to ${originalOperator} for job ${jobCardNumber}`);
    return { success: true };

  } catch (error) {
    console.error("sendBusyNotification error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});