/* eslint-disable max-len */
const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const messaging = admin.messaging();

functions.setGlobalOptions({region: "africa-south1"});

// ==================== NEW: Custom Token Auth (Option B) ====================
exports.createCustomToken = functions
    .region("africa-south1")
    .https.onCall(async (data, context) => {
    // Robust handling for both Flutter and web callable payload formats
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
        return {customToken};
      } catch (error) {
        console.error("💥 Error in createCustomToken:", error);
        throw new functions.https.HttpsError("internal", "Failed to create custom token", error);
      }
    });
// ==========================================================================

/**
 * Gets notification level based on priority.
 * @param {number} priority - Job priority (1-5).
 * @return {string} Notification level.
 */
function getNotificationLevel(priority) {
  if (priority >= 5) return "full-loud";
  if (priority >= 4) return "medium-high";
  return "normal";
}

/**
 * Sends job assignment notification to assignee.
 * @param {Object} data - Notification data.
 * @return {Promise<Object>} Success response.
 */
exports.sendJobAssignmentNotification = functions.https.onCall(async (data) => {
  console.log("📥 data keys:", Object.keys(data));
  console.log("📥 data.data keys:",
    data.data ? Object.keys(data.data) : "no data.data");
  const innerData = data.data || data;
  const recipientToken = innerData.recipientToken;
  const jobCardId = innerData.jobCardId;
  const jobCardNumber = innerData.jobCardNumber;
  const operator = innerData.operator;
  const creator = innerData.creator;
  const area = innerData.area;
  const description = innerData.description;
  const priority = innerData.priority || 1;
  const level = getNotificationLevel(priority);

  console.log("🔍 Extracted recipientToken:", recipientToken, "type:", typeof recipientToken, "len:", recipientToken ? recipientToken.length : "n/a");

  if (!recipientToken || !recipientToken.trim()) {
    console.log("❌ recipientToken missing or empty - throwing");
    throw new functions.https.HttpsError("invalid-argument", "Missing or invalid recipientToken");
  }

  // Build notification title and body
  const title = `Job Assigned by ${operator} Job#${jobCardNumber || "N/A"}`;
  const body = `Created by ${creator}\nLocation: ${area}\nDescription: ${description}`;

  try {
    const response = await messaging.send({
      token: recipientToken,
      notification: {
        title: title,
        body: body,
      },
      data: {click_action: "FLUTTER_NOTIFICATION_CLICK", jobId: jobCardId, notificationType: "assigned", notificationLevel: level},
      android: {priority: "high"},
    });

    console.log("✅ Notification sent successfully");
    return {success: true, messageId: response};
  } catch (error) {
    console.error("FCM Error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * Sends notification to job creator for self-assign or close.
 * @param {Object} data - Notification data.
 * @return {Promise<Object>} Success response.
 */
exports.sendCreatorNotification = functions.https.onCall(async (data) => {
  console.log("📥 Creator notification data keys:", Object.keys(data));
  console.log("📥 Creator notification data.data keys:", data.data ? Object.keys(data.data) : "no data.data");
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

  console.log("🔍 Creator notification extracted recipientToken:", recipientToken, "len:", recipientToken ? recipientToken.length : "n/a");

  if (!recipientToken || !recipientToken.trim()) {
    console.log("❌ Creator notification recipientToken missing or empty - throwing");
    throw new functions.https.HttpsError("invalid-argument", "Missing or invalid recipientToken");
  }

  // Build notification title and body based on type
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

  try {
    const response = await messaging.send({
      token: recipientToken,
      notification: {
        title: title,
        body: body,
      },
      data: {click_action: "FLUTTER_NOTIFICATION_CLICK", jobId: jobCardId, notificationType: notificationType, notificationLevel: level},
      android: {priority: "high"},
    });

    console.log("✅ Creator notification sent successfully");
    return {success: true, messageId: response};
  } catch (error) {
    console.error("Creator FCM Error:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * Gets onsite mechanics for notifications.
 * @return {Promise<Array>} Array of mechanic employees.
 */
async function getOnsiteMechanics() {
  const snaps = await admin.firestore().collection("employees").where("isOnSite", "==", true).get();
  return snaps.docs.filter((doc) => {
    const pos = doc.data().position;
    if (!pos || typeof pos !== "string") return false;
    const lowerPos = pos.toLowerCase();
    return /mechanical|mechanic/i.test(lowerPos) && !/manager/i.test(lowerPos);
  }).map((doc) => ({token: doc.data().fcmToken, ...doc.data()}));
}

/**
 * Gets onsite electricians for notifications.
 * @return {Promise<Array>} Array of electrician employees.
 */
async function getOnsiteElectricians() {
  const snaps = await admin.firestore().collection("employees").where("isOnSite", "==", true).get();
  return snaps.docs.filter((doc) => {
    const pos = doc.data().position;
    if (!pos || typeof pos !== "string") return false;
    const lowerPos = pos.toLowerCase();
    return /electrician|electrical/i.test(lowerPos) && !/manager/i.test(lowerPos);
  }).map((doc) => ({token: doc.data().fcmToken, ...doc.data()}));
}

/**
 * Gets initial recipients for job notifications.
 * @param {string} jobType - Type of job.
 * @return {Promise<Array>} Array of employees.
 */
async function getInitialRecipients(jobType) {
  if (jobType === "mechanical") return getOnsiteMechanics();
  if (jobType === "electrical") return getOnsiteElectricians();
  return [...await getOnsiteMechanics(), ...await getOnsiteElectricians()];
}

/**
 * Gets relevant managers for job type.
 * @param {string} jobType - Type of job.
 * @return {Promise<Array>} Array of managers.
 */
async function getRelevantManagers(jobType) {
  const mechMgr = await admin.firestore().doc("employees/23194").get();
  const elecMgr = await admin.firestore().doc("employees/23162").get();
  const mgrs = [];
  if (jobType === "mechanical" || jobType === "mechanicalElectrical") {
    if (mechMgr.exists) mgrs.push(mechMgr.data());
  }
  if (jobType === "electrical" || jobType === "mechanicalElectrical") {
    if (elecMgr.exists) mgrs.push(elecMgr.data());
  }
  return mgrs.filter(Boolean);
}

/**
 * Gets onsite foremen and shift leaders for department.
 * @param {string} dept - Department name.
 * @return {Promise<Array>} Array of foremen/shift leaders.
 */
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

/**
 * Gets managers for department.
 * @param {string} dept - Department name.
 * @return {Promise<Array>} Array of managers.
 */
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

/**
 * Gets workshop manager.
 * @return {Promise<Object>} Workshop manager employee.
 */
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

/**
 * Sends FCM notification to employee.
 * @param {string} token - FCM token.
 * @param {string} title - Notification title.
 * @param {string} body - Notification body.
 * @param {string} jobId - Job card ID.
 * @param {string} level - Notification level.
 */
async function sendNotification(token, title, body, jobId, level) {
  if (!token) return;
  try {
    await messaging.send({
      token,
      notification: {title, body},
      data: {click_action: "FLUTTER_NOTIFICATION_CLICK", jobId, notificationType: "broadcast", notificationLevel: level},
      android: {priority: "high"},
    });
  } catch (e) {
    console.error("FCM send error:", e);
  }
}

// Triggers
exports.onJobCardCreated = functions.firestore.onDocumentCreated({document: "job_cards/{jobId}"}, async (event) => {
  const job = event.data.data();
  const priority = job.priority || 1;
  const level = getNotificationLevel(priority);
  const recipients = await getInitialRecipients(job.type);
  if (priority >= 5) {
    // Add creator for pri5
    const creator = await admin.firestore().doc(`employees/${job.operatorClockNo}`).get();
    if (creator.exists) recipients.push(creator.data());
  }
  for (const emp of recipients) {
    await sendNotification(emp.token, "New Job Available", `${job.department} - ${job.machine}\n${job.area} - ${job.part}\n${job.description}`, event.data.id, level);
  }
});

exports.onJobCardAssigned = functions.firestore.onDocumentUpdated({document: "job_cards/{jobId}"}, async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!before.assignedTo && after.assignedTo) {
    const priority = after.priority || 1;
    const level = getNotificationLevel(priority);
    const assignee = await admin.firestore().doc(`employees/${after.assignedTo}`).get();
    if (assignee.exists) {
      await sendNotification(assignee.data().fcmToken, "New Job Assigned", `${after.department} - ${after.machine}\n${after.area} - ${after.part}\n${after.description}`, event.data.after.id, level);
    }
  }
});

// Escalation timer - UPDATED with priority-based levels and 60s for pri5
// NOTE: Queries need composite Firestore indexes.
// The 1min, 2min, 7min queries each need indexes.
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

    console.log("⏰ oneMinAgo:", oneMinAgo.toISOString(), "twoMinAgo:", twoMinAgo.toISOString(), "sevenMinAgo:", sevenMinAgo.toISOString());

    // ==================== 1-MINUTE ESCALATION (pri5 only) ====================
    console.log("🔍 Running 1min query: status=open, assignedClockNos=null, priority>=5, createdAt<=1minAgo, notifiedAt1min=null");
    const jobs1min = await admin.firestore().collection("job_cards")
        .where("status", "==", "open")
        .where("assignedClockNos", "==", null)
        .where("priority", ">=", 5)
        .where("createdAt", "<=", oneMinAgo)
        .where("notifiedAt1min", "==", null)
        .get();

    console.log(`📊 Found ${jobs1min.size} jobs for 1min escalation`);

    for (const doc of jobs1min.docs) {
      const job = doc.data();
      console.log(`📌 Processing 1min job ${doc.id} | type:${job.type} | operator:${job.operatorClockNo} | pri:${job.priority}`);

      const creator = await admin.firestore().doc(`employees/${job.operatorClockNo}`).get();
      const mgrs = await getRelevantManagers(job.type);
      const foremen = await getOnsiteDeptForemenShiftLeaders(job.department);
      const creatorData = creator.exists ? creator.data() : null;
      const recipients = [creatorData, ...mgrs, ...foremen].filter(Boolean);

      console.log(`👥 1min recipients: ${recipients.length}`);

      for (const emp of recipients) {
        await sendNotification(emp.fcmToken, "Escalation: Unassigned Job (1min)", `${job.department} - ${job.machine}\n${job.area} - ${job.part}\n${job.description}`, doc.id, "medium-high");
      }

      await doc.ref.update({notifiedAt1min: now});
      console.log(`✅ Updated notifiedAt1min for job ${doc.id}`);
    }

    // ==================== 2-MINUTE ESCALATION ====================
    console.log("🔍 Running 2min query: status=open, assignedClockNos=null, createdAt<=2minAgo, notifiedAt2min=null");
    const jobs2min = await admin.firestore().collection("job_cards")
        .where("status", "==", "open")
        .where("assignedClockNos", "==", null)
        .where("createdAt", "<=", twoMinAgo)
        .where("notifiedAt2min", "==", null)
        .get();

    console.log(`📊 Found ${jobs2min.size} jobs for 2min escalation`);

    for (const doc of jobs2min.docs) {
      const job = doc.data();
      const priority = job.priority || 1;
      const level = priority <= 3 ? "normal" : "medium-high";
      console.log(`📌 Processing 2min job ${doc.id} | type:${job.type} | operator:${job.operatorClockNo} | pri:${priority} | level:${level}`);

      const creator = await admin.firestore().doc(`employees/${job.operatorClockNo}`).get();
      const mgrs = await getRelevantManagers(job.type);
      const foremen = await getOnsiteDeptForemenShiftLeaders(job.department);
      const creatorData = creator.exists ? creator.data() : null;
      const recipients = [creatorData, ...mgrs, ...foremen].filter(Boolean);

      console.log(`👥 2min recipients: ${recipients.length}`);

      for (const emp of recipients) {
        await sendNotification(emp.fcmToken, "Escalation: Unassigned Job (2min)", `${job.department} - ${job.machine}\n${job.area} - ${job.part}\n${job.description}`, doc.id, level);
      }

      await doc.ref.update({notifiedAt2min: now});
      console.log(`✅ Updated notifiedAt2min for job ${doc.id}`);
    }

    // ==================== 7-MINUTE ESCALATION ====================
    console.log("🔍 Running 7min query: status=open, assignedClockNos=null, createdAt<=7minAgo, notifiedAt7min=null");
    const jobs7min = await admin.firestore().collection("job_cards")
        .where("status", "==", "open")
        .where("assignedClockNos", "==", null)
        .where("createdAt", "<=", sevenMinAgo)
        .where("notifiedAt7min", "==", null)
        .get();

    console.log(`📊 Found ${jobs7min.size} jobs for 7min escalation`);

    for (const doc of jobs7min.docs) {
      const job = doc.data();
      const priority = job.priority || 1;
      const level = priority <= 3 ? "normal" : "full-loud";
      console.log(`📌 Processing 7min job ${doc.id} | type:${job.type} | operator:${job.operatorClockNo} | pri:${priority} | level:${level}`);

      const creator = await admin.firestore().doc(`employees/${job.operatorClockNo}`).get();
      const mgrs = await getRelevantManagers(job.type);
      const foremen = await getOnsiteDeptForemenShiftLeaders(job.department);
      const deptMgrs = await getDeptManagers(job.department);
      const workshopMgr = await getWorkshopManager();
      const creatorData = creator.exists ? creator.data() : null;
      const recipients = [creatorData, ...mgrs, ...foremen, ...deptMgrs, workshopMgr].filter(Boolean);

      console.log(`👥 7min recipients: ${recipients.length}`);

      for (const emp of recipients) {
        await sendNotification(emp.fcmToken, "Urgent Escalation: Unassigned Job (7min)", `${job.department} - ${job.machine}\n${job.area} - ${job.part}\n${job.description}`, doc.id, level);
      }

      await doc.ref.update({notifiedAt7min: now});
      console.log(`✅ Updated notifiedAt7min for job ${doc.id}`);
    }

    console.log("🎉 escalateNotifications completed successfully");
  } catch (error) {
    console.error("❌ escalateNotifications error:", error);
    throw error; // Re-throw so Cloud Scheduler sees the 500 (for retry logic)
  }
});

// Migration function to fix employee doc IDs to match clockNo
exports.migrateEmployeeIds = functions.https.onCall(async (data, context) => {
  const employeesRef = admin.firestore().collection("employees");
  const snapshot = await employeesRef.get();
  const migrated = [];
  const batch = admin.firestore().batch();

  for (const doc of snapshot.docs) {
    const docData = doc.data();
    const clockNo = docData.clockNo;
    if (doc.id !== clockNo) {
      // Create new doc with clockNo as ID
      const newRef = employeesRef.doc(clockNo);
      batch.set(newRef, docData);
      // Delete old
      batch.delete(doc.ref);
      migrated.push({oldId: doc.id, newId: clockNo, name: docData.name});
    }
  }

  await batch.commit();
  console.log(`Migrated ${migrated.length} employee docs`);
  return {migrated, count: migrated.length};
});

// Auto-close monitoring jobs after 7 days with no adjustments
exports.autoCloseMonitoringJobs = functions.scheduler.onSchedule({
  schedule: "0 8 * * *", // Daily at 8am Johannesburg
  region: "europe-west1",
  timeZone: "Africa/Johannesburg",
}, async (event) => {
  console.log("🚀 autoCloseMonitoringJobs started at", new Date().toISOString());

  try {
    const now = admin.firestore.Timestamp.now();
    const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);

    console.log("⏰ sevenDaysAgo:", sevenDaysAgo.toISOString());

    // Query monitoring jobs started 7+ days ago
    const monitoringJobs = await admin.firestore().collection("job_cards")
        .where("status", "==", "monitor")
        .where("monitoringStartedAt", "<=", admin.firestore.Timestamp.fromDate(sevenDaysAgo))
        .get();

    console.log(`📊 Found ${monitoringJobs.size} monitoring jobs`);

    const batch = admin.firestore().batch();
    let closedCount = 0;

    for (const doc of monitoringJobs.docs) {
      const job = doc.data();
      const monitoringStartedAt = job.monitoringStartedAt ? job.monitoringStartedAt.toDate() : null;
      const lastUpdatedAt = job.lastUpdatedAt ? job.lastUpdatedAt.toDate() : null;

      if (monitoringStartedAt && lastUpdatedAt) {
        const sevenDaysAfterStart = new Date(monitoringStartedAt.getTime() + 7 * 24 * 60 * 60 * 1000);
        // Close if no updates during the 7-day period
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
          console.log(`✅ Auto-closed job ${doc.id}`);
        }
      }
    }

    if (closedCount > 0) {
      await batch.commit();
      console.log(`🎉 Auto-closed ${closedCount} jobs`);
    } else {
      console.log("ℹ️ No jobs to auto-close");
    }

    console.log("🎉 autoCloseMonitoringJobs completed successfully");
  } catch (error) {
    console.error("❌ autoCloseMonitoringJobs error:", error);
    throw error;
  }
});

// Copper Storage Notification Trigger
exports.onCopperTransactionWrite = functions.firestore.onDocumentWritten({document: "copperTransactions/{docId}"}, async (event) => {
  try {
    const after = event.data.after.data();
    if (!after) return;

    // Compute total sell kg (nuggets + rods)
    const sellTypes = ["sellNuggets", "sellRods"];
    const snapshot = await admin.firestore().collection("copperTransactions")
        .where("type", "in", sellTypes)
        .get();

    const sellTotal = snapshot.docs.reduce((sum, doc) => sum + (doc.data().kg || 0), 0);

    if (sellTotal > 400) {
      // Send notification to employee 22
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
        console.log("✅ Copper sell notification sent to employee 22");
      }
    }
  } catch (error) {
    console.error("❌ Copper notification error:", error);
  }
});

// Migration function to update job card statuses
exports.migrateJobStatuses = functions.https.onCall(async (data, context) => {
  // Check if user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
  }

  try {
    console.log("Starting status migration...");

    const db = admin.firestore();
    const snapshot = await db.collection("job_cards").get();

    if (snapshot.empty) {
      return {message: "No job cards found.", updated: 0};
    }

    console.log(`Found ${snapshot.size} job cards to check for status migration.`);

    const batch = db.batch();
    let updatedCount = 0;
    const updates = [];

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const currentStatus = data.status;

      let newStatus = currentStatus;

      if (currentStatus === "completed") {
        newStatus = "closed";
        updates.push({id: doc.id, from: "completed", to: "closed"});
      } else if (currentStatus === "monitoring") {
        newStatus = "monitor";
        updates.push({id: doc.id, from: "monitoring", to: "monitor"});
      }

      if (newStatus !== currentStatus) {
        batch.update(doc.ref, {status: newStatus});
        updatedCount++;
      }
    }

    if (updatedCount > 0) {
      await batch.commit();
      console.log(`Migration completed! Updated ${updatedCount} job cards.`);
      return {
        message: `Migration completed! Updated ${updatedCount} job cards.`,
        updated: updatedCount,
        updates: updates,
      };
    } else {
      return {message: "No job cards needed status updates.", updated: 0, updates: []};
    }
  } catch (error) {
    console.error("Migration failed:", error);
    throw new functions.https.HttpsError("internal", "Migration failed: " + error.message);
  }
});

