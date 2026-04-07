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