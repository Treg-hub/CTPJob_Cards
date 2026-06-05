/* eslint-disable max-len */
const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const messaging = admin.messaging();
const db = admin.firestore();

functions.setGlobalOptions({ region: "africa-south1" });

// ==================== IN-MEMORY CACHES (module-level, server-side only) ====================
// Config cache: notification_configs/global is almost never changed; cache for 10 min.
let _configCache = null;
let _configCachedAt = 0;
const CONFIG_TTL_MS = 10 * 60 * 1000; // 10 minutes

// Employee cache: employee records change rarely; isOnSite changes when clocking in/out.
// 5-minute TTL ensures onsite/offsite split stays accurate within one escalation cycle.
let _employeeCache = null;
let _employeeCachedAt = 0;
const EMPLOYEE_TTL_MS = 5 * 60 * 1000; // 5 minutes — bounded by isOnSite change frequency

async function getAllEmployeesCached() {
  if (_employeeCache && (Date.now() - _employeeCachedAt) < EMPLOYEE_TTL_MS) {
    return _employeeCache;
  }
  const snap = await db.collection("employees").get();
  // Normalise to plain objects; clockNo = document ID (employees collection uses clockNo as doc ID)
  _employeeCache = snap.docs.map((d) => ({ clockNo: d.id, token: d.data().fcmToken, ...d.data() }));
  _employeeCachedAt = Date.now();
  console.log(`getAllEmployeesCached: refreshed (${_employeeCache.length} employees)`);
  return _employeeCache;
}

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

// ==================== HELPER: Notification levels ====================
// Used for job creation and escalation — the priority determines how
// aggressively the recipient is alerted.
//   full-loud    → P5 background = full-screen alarm, foreground = persistent banner (70% vol)
//   medium-high  → P4 = persistent banner, custom sound, DND bypass (foreground 50% vol)
//   banner       → P3 = persistent banner with buttons, default sound
//   normal       → P1, P2 = basic notification, no buttons, default sound
function getCreationLevel(priority) {
  if (priority >= 5) return "full-loud";
  if (priority >= 4) return "medium-high";
  if (priority >= 3) return "banner";
  return "normal";
}

// All post-creation events (self-assigned, completed, updated, busy response,
// operator follow-up) are informational — they should never blast a full-screen
// alarm at the recipient.
function getUpdateLevel() {
  return "normal";
}


// ==================== DYNAMIC CONFIG LOADER ====================
function defaultNotificationConfig() {
  return {
    stages: {
      stage1: {
        enabled: true,
        enabled_at: null,
        minutes: 5,
        recipients_by_type: {
          "mechanical": ["onsite_managers", "foremen"],
          "electrical": ["onsite_managers", "foremen"],
          "mech/elec":  ["onsite_managers", "foremen"],
        },
      },
      stage2: {
        enabled: true,
        enabled_at: null,
        minutes: 10,
        recipients_by_type: {
          "mechanical": ["onsite_dept_managers", "onsite_workshop_manager"],
          "electrical": ["onsite_dept_managers", "onsite_workshop_manager"],
          "mech/elec":  ["onsite_dept_managers", "onsite_workshop_manager"],
        },
      },
      stage3: {
        enabled: false,
        enabled_at: null,
        minutes: 30,
        recipients_by_type: { "mechanical": [], "electrical": [], "mech/elec": [] },
      },
      stage4: {
        enabled: false,
        enabled_at: null,
        minutes: 60,
        recipients_by_type: { "mechanical": [], "electrical": [], "mech/elec": [] },
      },
    },
    creation_recipients_by_type: {
      "mechanical":  ["onsite_mechanics"],
      "electrical":  ["onsite_electricians"],
      "mech/elec":   ["onsite_mechanics", "onsite_electricians"],
      "building":    ["onsite_building_maintenance", "onsite_workshop_manager"],
      "specialist":  ["onsite_prepress_specialist", "onsite_workshop_manager"],
    },
    excluded_job_types: ["maintenance", "building", "specialist"],
  };
}

async function getNotificationConfig() {
  if (_configCache && (Date.now() - _configCachedAt) < CONFIG_TTL_MS) {
    return _configCache;
  }

  const defaults = defaultNotificationConfig();

  let data = null;
  try {
    const doc = await db.collection("notification_configs").doc("global").get();
    if (doc.exists) data = doc.data();
  } catch (e) {
    console.error("Failed to load notification config, using defaults:", e);
  }

  if (!data) {
    _configCache = defaults;
    _configCachedAt = Date.now();
    return _configCache;
  }

  // Merge with defaults so partially-migrated docs (missing top-level keys) still work.
  const merged = {
    ...data,
    stages: data.stages || defaults.stages,
    creation_recipients_by_type: data.creation_recipients_by_type || defaults.creation_recipients_by_type,
    excluded_job_types: data.excluded_job_types || defaults.excluded_job_types,
  };

  if (!data.stages) {
    console.warn("notification_configs/global has no 'stages' field — using default stage config. Update the doc to silence this.");
  }

  _configCache = merged;
  _configCachedAt = Date.now();
  return _configCache;
}

// Maps Dart enum job type to the key used in recipients_by_type
function jobTypeKey(jobType) {
  if (jobType === "mechanicalElectrical") return "mech/elec";
  return jobType;
}

function getStage(config, stageNum) {
  return config.stages && config.stages[`stage${stageNum}`];
}

// Accepts a Firestore Timestamp, ISO string, or null and returns a Date (or null)
function parseEnabledAt(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value === "string") {
    const d = new Date(value);
    return isNaN(d.getTime()) ? null : d;
  }
  return null;
}

function getStageRecipients(config, stageNum, jobType) {
  const stage = getStage(config, stageNum);
  if (!stage || !stage.recipients_by_type) return [];
  return stage.recipients_by_type[jobTypeKey(jobType)] || [];
}

function isJobTypeExcluded(config, jobType) {
  return (config.excluded_job_types || []).includes(jobType);
}

function getCreationRecipientRules(config, jobType) {
  const map = config.creation_recipients_by_type;
  if (!map) return [];
  return map[jobTypeKey(jobType)] || [];
}

// ==================== NEW HELPER: Resolve recipients from rules ====================
async function resolveRecipientsFromRules(ruleNames, jobType, department, operatorClockNo = null, allEmps = null) {
  const allRecipients = [];

  for (const rule of ruleNames) {
    if (rule === "onsite_mechanics") {
      allRecipients.push(...(await getOnsiteMechanics(allEmps)));
    } else if (rule === "onsite_electricians") {
      allRecipients.push(...(await getOnsiteElectricians(allEmps)));
    } else if (rule === "onsite_managers") {
      allRecipients.push(...(await getOnsiteRelevantManagers(jobType, allEmps)));
    } else if (rule === "foremen") {
      allRecipients.push(...(await getOnsiteDeptForemenShiftLeaders(department, allEmps)));
    } else if (rule === "onsite_dept_managers") {
      allRecipients.push(...(await getOnsiteDeptManagers(department, allEmps)));
    } else if (rule === "onsite_workshop_manager") {
      const wm = await getOnsiteWorkshopManager(allEmps);
      if (wm) allRecipients.push(wm);
    } else if (rule === "onsite_building_maintenance") {
      allRecipients.push(...(await getOnsiteBuildingMaintenance(allEmps)));
    } else if (rule === "onsite_prepress_specialist") {
      allRecipients.push(...(await getOnsitePrepressSpecialist(allEmps)));
    } else if (rule === "offsite_managers") {
      allRecipients.push(...(await getOffsiteRelevantManagers(jobType, allEmps)));
    } else if (rule === "offsite_dept_managers") {
      allRecipients.push(...(await getOffsiteDeptManagers(department, allEmps)));
    } else if (rule === "offsite_workshop_manager") {
      const wm = await getOffsiteWorkshopManager(allEmps);
      if (wm) allRecipients.push(wm);
    } else if (rule === "operator") {
      // Special rule: the job's creator. Ignores isOnSite — operator should be
      // notified regardless of location since they raised the job.
      if (operatorClockNo) {
        // Use cache when available; fall back to individual doc read
        const cachedOp = allEmps ? allEmps.find((e) => e.clockNo === operatorClockNo) : null;
        if (cachedOp) {
          allRecipients.push({ ...cachedOp, isOperator: true });
        } else {
          const opDoc = await db.collection("employees").doc(operatorClockNo).get();
          if (opDoc.exists) {
            allRecipients.push({ token: opDoc.data().fcmToken, clockNo: opDoc.id, isOperator: true, ...opDoc.data() });
          } else {
            console.log(`operator rule: employee ${operatorClockNo} not found, skipping`);
          }
        }
      } else {
        console.log("operator rule: no operatorClockNo on job, skipping");
      }
    }
  }

  const unique = {};
  allRecipients.forEach(emp => { unique[emp.clockNo] = emp; });
  return Object.values(unique);
}

// ==================== CUSTOM TOKEN AUTH ====================
exports.createCustomToken = functions.https.onCall(async (data, _context) => {
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
  
  if (recipientClockNo) {
    const empDoc = await db.collection("employees").doc(recipientClockNo).get();
    if (empDoc.exists && empDoc.data().isOnSite !== true) {
      console.log(`Assignment blocked - ${recipientClockNo} is off-site, parking in inbox`);
      await db.collection("notification_inbox")
        .doc(recipientClockNo).collection("items").add({
          type: "job_assigned",
          jobCardId: jobCardId || null,
          jobCardNumber: jobCardNumber || null,
          title: `Job Assigned by ${operator || "Unknown"} #${jobCardNumber || "N/A"}`,
          body: `Created by ${creator || operator || "Unknown"}\nLocation: ${area}\n${description}`,
          department: department || null,
          area: area || null,
          machine: machine || null,
          part: part || null,
          priority,
          triggeredBy: "assignment_callable",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          read: false,
          readAt: null,
          initiatedByClockNo: initiatedByClockNo || null,
          initiatedByName: initiatedByName || null,
        });
      return { success: false, reason: "Recipient is off-site", parked: true };
    }
  }

  // Manual assignment is a creation-flow alert: the assignee needs to act on it,
  // so it's priority-based (P5 = full-screen, P4 = loud banner, etc.).
  const level = getCreationLevel(priority);
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

  // Creator notifications are post-creation updates (self-assigned, completed,
  // updated) — informational only, always normal level regardless of priority.
  const level = getUpdateLevel();
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

  // Check if the creator is currently onsite before sending the push notification.
  // If offsite, park the notification in the inbox for review on their return.
  let creatorClockNo = null;
  if (jobCardId) {
    try {
      const jobDoc = await db.collection("job_cards").doc(jobCardId).get();
      if (jobDoc.exists) creatorClockNo = jobDoc.data().operatorClockNo || null;
    } catch (e) {
      console.warn(`sendCreatorNotification: could not look up job ${jobCardId}:`, e.message);
    }
  }
  if (creatorClockNo) {
    const creatorEmp = await db.collection("employees").doc(creatorClockNo).get();
    if (creatorEmp.exists && creatorEmp.data().isOnSite !== true) {
      console.log(`sendCreatorNotification: creator ${creatorClockNo} is offsite — parking in inbox (${triggeredByValue})`);
      await db.collection("notification_inbox")
        .doc(creatorClockNo).collection("items").add({
          type: triggeredByValue,
          jobCardId: jobCardId || null,
          jobCardNumber: jobCardNumber || null,
          title,
          body,
          department: department || null,
          area: area || null,
          machine: machine || null,
          part: part || null,
          priority,
          triggeredBy: triggeredByValue,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          read: false,
          readAt: null,
          initiatedByClockNo: initiatedByClockNo || null,
          initiatedByName: assigneeName || initiatedByName || null,
        });
      return { success: true, parked: true };
    }
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
    sentTo: [creatorClockNo || innerData.recipientClockNo || "unknown"],
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
async function getOnsiteMechanics(allEmps = null) {
  if (allEmps) {
    return allEmps.filter((e) => {
      const pos = (e.position || "").toLowerCase();
      return e.isOnSite === true && /mechanical|mechanic/i.test(pos) && !/manager/i.test(pos);
    });
  }
  const snaps = await db.collection("employees").where("isOnSite", "==", true).get();
  return snaps.docs
    .filter((doc) => {
      const pos = doc.data().position || "";
      const lower = pos.toLowerCase();
      return /mechanical|mechanic/i.test(lower) && !/manager/i.test(lower);
    })
    .map((doc) => ({ token: doc.data().fcmToken, clockNo: doc.id, ...doc.data() }));
}

async function getOnsiteElectricians(allEmps = null) {
  if (allEmps) {
    return allEmps.filter((e) => {
      const pos = (e.position || "").toLowerCase();
      return e.isOnSite === true && /electrician|electrical/i.test(pos) && !/manager/i.test(pos);
    });
  }
  const snaps = await db.collection("employees").where("isOnSite", "==", true).get();
  return snaps.docs
    .filter((doc) => {
      const pos = doc.data().position || "";
      const lower = pos.toLowerCase();
      return /electrician|electrical/i.test(lower) && !/manager/i.test(lower);
    })
    .map((doc) => ({ token: doc.data().fcmToken, clockNo: doc.id, ...doc.data() }));
}

async function getOnsiteBuildingMaintenance(allEmps = null) {
  if (allEmps) {
    return allEmps.filter((e) =>
      e.isOnSite === true && (e.position || "").toLowerCase().includes("building maintenance")
    );
  }
  const snaps = await db.collection("employees").where("isOnSite", "==", true).get();
  return snaps.docs
    .filter((doc) => (doc.data().position || "").toLowerCase().includes("building maintenance"))
    .map((doc) => ({ token: doc.data().fcmToken, clockNo: doc.id, ...doc.data() }));
}

async function getOnsitePrepressSpecialist(allEmps = null) {
  if (allEmps) {
    return allEmps.filter((e) =>
      e.isOnSite === true && e.department === "Pre Press" &&
      (e.position || "").toLowerCase().includes("specialist")
    );
  }
  const snaps = await db.collection("employees")
    .where("department", "==", "Pre Press")
    .where("isOnSite", "==", true)
    .get();
  return snaps.docs
    .filter((doc) => (doc.data().position || "").toLowerCase().includes("specialist"))
    .map((doc) => ({ token: doc.data().fcmToken, clockNo: doc.id, ...doc.data() }));
}

async function getOnsiteDeptForemenShiftLeaders(dept, allEmps = null) {
  if (allEmps) {
    return allEmps.filter((e) => {
      const pos = (e.position || "").toLowerCase();
      return e.isOnSite === true && e.department === dept && /foreman|shift leader/i.test(pos);
    });
  }
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

// ==================== CORE SEND NOTIFICATION ====================
async function sendNotification({
  token,
  recipientClockNo = null,  // clockNo of who receives this notification (for audit log)
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
      sentTo: [recipientClockNo || "unknown"],
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
    const staleTokenCodes = [
      "messaging/registration-token-not-registered",
      "messaging/invalid-registration-token",
    ];
    if (staleTokenCodes.includes(e.errorInfo?.code) && recipientClockNo && recipientClockNo !== "unknown") {
      try {
        await db.collection("employees").doc(recipientClockNo).update({ fcmToken: null });
        console.log(`Cleared stale FCM token for employee ${recipientClockNo}`);
      } catch (clearErr) {
        console.error(`Failed to clear stale token for ${recipientClockNo}:`, clearErr);
      }
    }
    console.error("FCM send error:", e);
  }
}

// ==================== HELPER: Notify creation recipients ====================
// Shared between onJobCardCreated and onJobCardTypeChanged so the routing logic
// stays in one place. When a type is changed mid-flight, the new audience needs
// the same fan-out the original creation would have done — minus the P5
// creator-CC (the creator already knows about their own job).
async function notifyCreationRecipients(jobId, job, { triggeredBy = "job_created", titleOverride = null, includeCreatorOnP5 = true } = {}) {
  const priority = job.priority || 1;
  const level = getCreationLevel(priority);

  const config = await getNotificationConfig();
  if (isJobTypeExcluded(config, job.type)) {
    console.log(`notifyCreationRecipients: job #${job.jobCardNumber || jobId} type ${job.type} is excluded`);
    return;
  }

  const creationRules = getCreationRecipientRules(config, job.type);
  const recipients = await resolveRecipientsFromRules(creationRules, job.type, job.department);

  if (includeCreatorOnP5 && priority >= 5 && job.operatorClockNo) {
    const creatorDoc = await db.collection("employees").doc(job.operatorClockNo).get();
    if (creatorDoc.exists) recipients.push({ token: creatorDoc.data().fcmToken, clockNo: job.operatorClockNo, ...creatorDoc.data() });
  }

  const createdBy = job.operator || "Unknown";
  const title = titleOverride || `Job #${job.jobCardNumber || jobId} - Priority ${priority} - ${createdBy}`;
  const body = job.description;

  for (const emp of recipients) {
    await sendNotification({
      token: emp.token,
      recipientClockNo: emp.clockNo,
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
      triggeredBy,
      initiatedByClockNo: job.operatorClockNo || null,
      initiatedByName: createdBy,
    });
  }
}

// ==================== FIRESTORE TRIGGER: JOB CREATED ====================
exports.onJobCardCreated = functions.firestore.onDocumentCreated({ document: "job_cards/{jobId}" }, async (event) => {
  const jobId = event.params.jobId;
  const job = event.data.data();
  await notifyCreationRecipients(jobId, job, { triggeredBy: "job_created" });

  // Auto-assign Pre Press Specialist jobs to the on-site specialist.
  // If the specialist is off-site the job remains open — the Workshop Manager
  // was still notified via creation notification and can assign manually.
  if (job.type === "specialist") {
    try {
      const allEmps = await getAllEmployeesCached();
      const specialists = await getOnsitePrepressSpecialist(allEmps);
      if (specialists.length === 0) {
        console.log(`onJobCardCreated: specialist job ${jobId} — no on-site specialist found, skipping auto-assign`);
      } else {
        const specialist = specialists[0];
        const now = admin.firestore.Timestamp.now();
        await event.data.ref.update({
          assignedClockNos:  [specialist.clockNo],
          assignedNames:     [specialist.name || specialist.clockNo],
          assignedAt:        now,
          escalationStopped: true,
          assignmentHistory: admin.firestore.FieldValue.arrayUnion({
            clockNo:        specialist.clockNo,
            name:           specialist.name || specialist.clockNo,
            assignedAt:     now,
            assignedBy:     "system",
            assignedByName: "Auto-assigned (Pre Press Specialist)",
          }),
        });
        console.log(`onJobCardCreated: specialist job ${jobId} auto-assigned to ${specialist.clockNo}`);
      }
    } catch (e) {
      // Non-fatal — specialist was still notified via creation notification
      console.error(`onJobCardCreated: auto-assign failed for specialist job ${jobId}:`, e);
    }
  }
});

// ==================== FIRESTORE TRIGGER: JOB TYPE CHANGED ====================
// Fires when a job's `type` field changes (manager/technician re-classified the
// job). Re-runs the creation-recipient fan-out so the new audience
// (e.g. electricians instead of mechanics) gets notified. Excluded types
// (currently maintenance) stay silent — flipping TO maintenance sends nothing.
exports.onJobCardTypeChanged = functions.firestore.onDocumentUpdated({ document: "job_cards/{jobId}" }, async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!before || !after) return;
  if (before.type === after.type) return;
  if (after.status === "closed") return;
  const jobId = event.params.jobId;
  console.log(`onJobCardTypeChanged: job #${after.jobCardNumber || jobId} type ${before.type} → ${after.type}`);
  const title = `Type changed → ${after.type} - Job #${after.jobCardNumber || jobId}`;
  await notifyCreationRecipients(jobId, after, {
    triggeredBy: "type_changed",
    titleOverride: title,
    includeCreatorOnP5: false,
  });
});

// ==================== FIRESTORE TRIGGER: JOB ASSIGNED ====================
exports.onJobCardAssigned = functions.firestore.onDocumentUpdated({ document: "job_cards/{jobId}" }, async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();

  if (!before.assignedTo && after.assignedTo) {
    const priority = after.priority || 1;
    const level = getCreationLevel(priority);

    const assigneeDoc = await db.collection("employees").doc(after.assignedTo).get();
    if (assigneeDoc.exists) {
      if (assigneeDoc.data().isOnSite !== true) {
        // Employee is offsite — park notification in inbox for review on return
        console.log(`onJobCardAssigned: ${after.assignedTo} is offsite — parking in inbox`);
        await db.collection("notification_inbox")
          .doc(after.assignedTo).collection("items").add({
            type: "job_assigned",
            jobCardId: event.params.jobId,
            jobCardNumber: after.jobCardNumber || event.params.jobId,
            title: "New Job Assigned",
            body: `${after.department} - ${after.machine}\n${after.area} - ${after.part || ""}\n${after.description}`,
            department: after.department || null,
            area: after.area || null,
            machine: after.machine || null,
            part: after.part || null,
            priority,
            triggeredBy: "job_assigned",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            read: false,
            readAt: null,
            initiatedByClockNo: after.lastUpdatedBy || null,
            initiatedByName: after.lastUpdatedByName || null,
          });
        // Still stop escalation — job is assigned regardless of notification delivery
        await event.data.after.ref.update({ escalationStopped: true });
        return;
      }

      await sendNotification({
        token: assigneeDoc.data().fcmToken,
        recipientClockNo: after.assignedTo,
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
      // Stop all future escalation for this job now that it's been assigned.
      await event.data.after.ref.update({ escalationStopped: true });
    }
  }
});

// ==================== SCHEDULED: ESCALATION (4 stages, config-driven) ====================
exports.escalateNotifications = functions.scheduler.onSchedule({
  schedule: "every 5 minutes",
  region: "europe-west1",
  timeZone: "Africa/Johannesburg",
}, async () => {
  console.log("escalateNotifications: started");
  const config = await getNotificationConfig();
  const allEmps = await getAllEmployeesCached();
  const now = admin.firestore.FieldValue.serverTimestamp();

  for (let stageNum = 1; stageNum <= 4; stageNum++) {
    const stage = getStage(config, stageNum);
    if (!stage) {
      console.log(`Stage ${stageNum}: missing from config, skipping`);
      continue;
    }
    if (stage.enabled !== true) {
      console.log(`Stage ${stageNum}: disabled, skipping`);
      continue;
    }
    const minutes = stage.minutes;
    if (!Number.isFinite(minutes) || minutes <= 0) {
      console.log(`Stage ${stageNum}: invalid minutes (${minutes}), skipping`);
      continue;
    }

    const stageField = `notifiedAtStage${stageNum}`;
    const cutoff = new Date(Date.now() - minutes * 60 * 1000);
    const enabledAt = parseEnabledAt(stage.enabled_at);

    // Filter at the Firestore level — only fetch jobs that haven't been stamped
    // for this stage yet. Massive read savings when many long-open jobs exist.
    const jobs = await db.collection("job_cards")
      .where("status", "==", "open")
      .where(stageField, "==", null)
      .where("createdAt", "<=", cutoff)
      .get();

    console.log(`Stage ${stageNum} (${minutes}min): found ${jobs.size} unstamped open jobs older than ${minutes}min, enabled_at=${enabledAt ? enabledAt.toISOString() : "none"}`);

    let skippedPreEnable = 0;
    for (const doc of jobs.docs) {
      const job = doc.data();

      if (isJobTypeExcluded(config, job.type)) continue;
      if (job[stageField]) continue; // defensive — shouldn't happen given the query filter

      // Skip jobs that existed before this stage was enabled — protects against
      // bombarding new recipients with notifications for old open jobs.
      if (enabledAt && job.createdAt) {
        const createdAtMs = typeof job.createdAt.toMillis === "function"
          ? job.createdAt.toMillis()
          : new Date(job.createdAt).getTime();
        if (createdAtMs <= enabledAt.getTime()) { skippedPreEnable++; continue; }
      }
      if (job.escalationStopped === true || (job.assignedClockNos && job.assignedClockNos.length > 0)) {
        // Job is assigned or stopped — stamp ALL remaining stages at once so it
        // disappears from every escalation query in one go (not stage-by-stage
        // over the next hour).
        const stampAll = {};
        for (let s = 1; s <= 4; s++) {
          const f = `notifiedAtStage${s}`;
          if (!job[f]) stampAll[f] = now;
        }
        if (Object.keys(stampAll).length > 0) {
          await doc.ref.update(stampAll);
        }
        continue;
      }

      const rules = getStageRecipients(config, stageNum, job.type);
      if (rules.length === 0) continue;

      const resolvedRecipients = await resolveRecipientsFromRules(rules, job.type, job.department, job.operatorClockNo, allEmps);
      console.log(`Stage ${stageNum} job #${job.jobCardNumber || doc.id}: type=${job.type}, dept=${job.department}, recipients=${resolvedRecipients.length}`);

      if (resolvedRecipients.length === 0) continue;

      const priority = job.priority || 1;
      const stageLevel = getCreationLevel(priority);   // P1/P2 normal, P3 banner, P4 medium-high, P5 full-loud

      const creatorEmp = allEmps.find((e) => e.clockNo === job.operatorClockNo);
      const createdBy = creatorEmp ? (creatorEmp.name || job.operator || "Unknown") : (job.operator || "Unknown");

      const jobNumber = job.jobCardNumber || doc.id;
      // Count of non-operator recipients (people we've notified other than the operator themselves)
      const otherCount = resolvedRecipients.filter(e => e.clockNo !== job.operatorClockNo).length;

      for (const emp of resolvedRecipients) {
        const isOperator = emp.clockNo === job.operatorClockNo;

        // Operator always gets a normal-level "no response" notification — they
        // can't claim the job themselves and don't need a full-screen alarm.
        // Other recipients get the priority-based stage level.
        const empLevel = isOperator ? getUpdateLevel() : stageLevel;

        const title = isOperator
          ? `No response yet — Job #${jobNumber}`
          : `Stage ${stageNum} Escalation (${minutes}min) - Job #${jobNumber}`;

        const body = isOperator
          ? `${minutes} minutes passed with no assignment. We've notified ${otherCount} ${otherCount === 1 ? "person" : "people"}. Follow up directly.`
          : `${job.department} - ${job.machine}\n${job.area} - ${job.part}\n${job.description}`;

        await sendNotification({
          token: emp.token,
          recipientClockNo: emp.clockNo,
          title,
          body,
          jobCardNumber: jobNumber,
          level: empLevel,
          priority,
          createdBy,
          department: job.department,
          area: job.area,
          machine: job.machine,
          part: job.part,
          triggeredBy: isOperator ? `stage${stageNum}_operator_followup` : `stage${stageNum}_escalation`,
        });
      }
      await doc.ref.update({ [stageField]: now });
    }
    if (skippedPreEnable > 0) {
      console.log(`Stage ${stageNum}: skipped ${skippedPreEnable} jobs created before enabled_at`);
    }
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
      const title = "Copper Sell Ready";
      const body = `Total sell copper: ${sellTotal}kg`;

      if (emp22.data().isOnSite !== true) {
        console.log(`onCopperTransactionWrite: employee 22 is offsite — parking in inbox`);
        await db.collection("notification_inbox")
          .doc("22").collection("items").add({
            type: "copper_sell",
            title,
            body,
            triggeredBy: "copper_sell",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            read: false,
            readAt: null,
          });
        return;
      }

      await messaging.send({
        token: emp22.data().fcmToken,
        notification: { title, body },
        data: { click_action: "FLUTTER_NOTIFICATION_CLICK", triggeredBy: "copper_sell" },
        android: { priority: "high" },
      });

      await logNotification({
        triggeredBy: "copper_sell",
        sentTo: ["22"],
        level: "normal",
        title,
        body,
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

    if (response.action === "busy") {
      if (!creatorClockNo) {
        console.error("Job has no operatorClockNo");
        return null;
      }

      const creatorDoc = await db.collection("employees").doc(creatorClockNo).get();
      if (!creatorDoc.exists) {
        console.error(`Creator ${creatorClockNo} not found`);
        return null;
      }

      const title = `Busy Response - Job #${jobCardNumber}`;
      const body = `${userName} (${clockNo}) is busy and cannot take this job right now.`;

      if (creatorDoc.data().isOnSite !== true) {
        console.log(`onAlertResponseCreated: creator ${creatorClockNo} is offsite — parking in inbox`);
        await db.collection("notification_inbox")
          .doc(creatorClockNo).collection("items").add({
            type: "busy_response",
            jobCardId: jobSnap.docs[0].id,
            jobCardNumber: parseInt(jobCardNumber),
            title,
            body,
            department: job.department || null,
            area: job.area || null,
            machine: job.machine || null,
            part: job.part || null,
            triggeredBy: "busy_response",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            read: false,
            readAt: null,
            initiatedByClockNo: clockNo,
            initiatedByName: userName,
          });
        await jobSnap.docs[0].ref.update({ escalationStopped: true });
        return null;
      }

      if (!creatorDoc.data().fcmToken) {
        console.error(`Creator ${creatorClockNo} has no FCM token`);
        return null;
      }

      const creatorToken = creatorDoc.data().fcmToken;

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

      // Stop all future escalation — a technician has acknowledged the job.
      await jobSnap.docs[0].ref.update({ escalationStopped: true });

      console.log(`Busy notification sent to creator ${creatorClockNo} for Job #${jobCardNumber}`);
      return null;
    }

    if (response.action === "dismissed") {
      console.log(`Alert dismissed for Job #${jobCardNumber} by ${userName} (${clockNo})`);
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

// ==================== NEW: On-site only manager helpers ====================
async function getOnsiteRelevantManagers(jobType, allEmps = null) {
  if (allEmps) {
    return allEmps.filter((e) => {
      const pos = (e.position || "").toLowerCase();
      if (!e.isOnSite || !/manager/i.test(pos)) return false;
      const dept = (e.department || "").toLowerCase();
      if (jobType === "mechanical" || jobType === "mechanicalElectrical") {
        return dept.includes("mechanical") || dept.includes("workshop");
      }
      if (jobType === "electrical" || jobType === "mechanicalElectrical") {
        return dept.includes("electrical") || dept.includes("workshop");
      }
      return false;
    });
  }
  const snaps = await db.collection("employees")
    .where("isOnSite", "==", true)
    .get();

  return snaps.docs
    .filter((doc) => {
      const pos = (doc.data().position || "").toLowerCase();
      if (!/manager/i.test(pos)) return false;

      const dept = (doc.data().department || "").toLowerCase();
      if (jobType === "mechanical" || jobType === "mechanicalElectrical") {
        return dept.includes("mechanical") || dept.includes("workshop");
      }
      if (jobType === "electrical" || jobType === "mechanicalElectrical") {
        return dept.includes("electrical") || dept.includes("workshop");
      }
      return false;
    })
    .map((doc) => ({ token: doc.data().fcmToken, clockNo: doc.id, ...doc.data() }));
}

async function getOnsiteDeptManagers(dept, allEmps = null) {
  if (allEmps) {
    return allEmps.filter((e) => {
      const pos = (e.position || "").toLowerCase();
      return e.isOnSite === true && e.department === dept && /manager/i.test(pos);
    });
  }
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

async function getOnsiteWorkshopManager(allEmps = null) {
  if (allEmps) {
    return allEmps.filter((e) => {
      const pos = (e.position || "").toLowerCase();
      return e.isOnSite === true && e.department === "Workshop" &&
             /manager/i.test(pos) && !/mechanical|electrical/i.test(pos);
    })[0] || null;
  }
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

// ==================== Off-site manager helpers ====================
async function getOffsiteRelevantManagers(jobType, allEmps = null) {
  if (allEmps) {
    return allEmps.filter((e) => {
      const pos = (e.position || "").toLowerCase();
      if (e.isOnSite !== false || !/manager/i.test(pos)) return false;
      const dept = (e.department || "").toLowerCase();
      if (jobType === "mechanical" || jobType === "mechanicalElectrical") {
        return dept.includes("mechanical") || dept.includes("workshop");
      }
      if (jobType === "electrical" || jobType === "mechanicalElectrical") {
        return dept.includes("electrical") || dept.includes("workshop");
      }
      return false;
    });
  }
  const snaps = await db.collection("employees")
    .where("isOnSite", "==", false)
    .get();

  return snaps.docs
    .filter((doc) => {
      const pos = (doc.data().position || "").toLowerCase();
      if (!/manager/i.test(pos)) return false;

      const dept = (doc.data().department || "").toLowerCase();
      if (jobType === "mechanical" || jobType === "mechanicalElectrical") {
        return dept.includes("mechanical") || dept.includes("workshop");
      }
      if (jobType === "electrical" || jobType === "mechanicalElectrical") {
        return dept.includes("electrical") || dept.includes("workshop");
      }
      return false;
    })
    .map((doc) => ({ token: doc.data().fcmToken, clockNo: doc.id, ...doc.data() }));
}

async function getOffsiteDeptManagers(dept, allEmps = null) {
  if (allEmps) {
    return allEmps.filter((e) => {
      const pos = (e.position || "").toLowerCase();
      return e.isOnSite === false && e.department === dept && /manager/i.test(pos);
    });
  }
  const snaps = await db.collection("employees")
    .where("department", "==", dept)
    .where("isOnSite", "==", false)
    .get();

  return snaps.docs
    .filter((doc) => {
      const pos = (doc.data().position || "").toLowerCase();
      return /manager/i.test(pos);
    })
    .map((doc) => ({ token: doc.data().fcmToken, clockNo: doc.id, ...doc.data() }));
}

async function getOffsiteWorkshopManager(allEmps = null) {
  if (allEmps) {
    return allEmps.filter((e) => {
      const pos = (e.position || "").toLowerCase();
      return e.isOnSite === false && e.department === "Workshop" &&
             /manager/i.test(pos) && !/mechanical|electrical/i.test(pos);
    })[0] || null;
  }
  const snaps = await db.collection("employees")
    .where("department", "==", "Workshop")
    .where("isOnSite", "==", false)
    .get();

  return snaps.docs
    .filter((doc) => {
      const pos = (doc.data().position || "").toLowerCase();
      return /manager/i.test(pos) && !/mechanical|electrical/i.test(pos);
    })
    .map((doc) => ({ token: doc.data().fcmToken, clockNo: doc.id, ...doc.data() }))[0] || null;
}

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

// ==================== CLEAR STALE ESCALATION STAMPS (one-time reset) ====================
exports.clearEscalationStamps = functions.https.onCall(async () => {
  const config = await getNotificationConfig();
  const snapshot = await db.collection("job_cards")
    .where("status", "==", "open")
    .get();

  const batch = db.batch();
  let count = 0;

  for (const doc of snapshot.docs) {
    const job = doc.data();
    if (isJobTypeExcluded(config, job.type)) continue;
    if (job.notifiedAtStage1 || job.notifiedAtStage2 || job.notifiedAtStage3 || job.notifiedAtStage4) {
      batch.update(doc.ref, {
        notifiedAtStage1: null,
        notifiedAtStage2: null,
        notifiedAtStage3: null,
        notifiedAtStage4: null,
      });
      count++;
    }
  }

  if (count > 0) await batch.commit();
  console.log(`Cleared escalation stamps from ${count} open job cards`);
  return { cleared: count };
});