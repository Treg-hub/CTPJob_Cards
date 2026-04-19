import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

export const createCustomToken = functions.https.onCall(async (data: any, context) => {
  const clockNo = data.clockNo as string;

  if (!clockNo) {
    throw new functions.https.HttpsError("invalid-argument", "clockNo is required");
  }

  try {
    // Look up the employee document
    const employeeDoc = await admin.firestore().collection("employees").doc(clockNo).get();

    if (!employeeDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Employee not found");
    }

    // Generate a custom token tied to this clockNo
    const uid = `employee_${clockNo}`;
    const customToken = await admin.auth().createCustomToken(uid, {
      clockNo: clockNo,
      name: employeeDoc.data()?.name || "",
    });

    return { customToken };
  } catch (error) {
    console.error("Error creating custom token:", error);
    throw new functions.https.HttpsError("internal", "Failed to create custom token");
  }
});