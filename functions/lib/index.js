"use strict";
const __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
  if (k2 === undefined) k2 = k;
  let desc = Object.getOwnPropertyDescriptor(m, k);
  if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
    desc = {enumerable: true, get: function() {
      return m[k];
    }};
  }
  Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
  if (k2 === undefined) k2 = k;
  o[k2] = m[k];
}));
const __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
  Object.defineProperty(o, "default", {enumerable: true, value: v});
}) : function(o, v) {
  o["default"] = v;
});
const __importStar = (this && this.__importStar) || (function() {
  let ownKeys = function(o) {
    ownKeys = Object.getOwnPropertyNames || function(o) {
      const ar = [];
      for (const k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
      return ar;
    };
    return ownKeys(o);
  };
  return function(mod) {
    if (mod && mod.__esModule) return mod;
    const result = {};
    if (mod != null) for (let k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
    __setModuleDefault(result, mod);
    return result;
  };
})();
Object.defineProperty(exports, "__esModule", {value: true});
exports.createCustomToken = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
admin.initializeApp();
exports.createCustomToken = (0, https_1.onCall)({region: "africa-south1"}, async (data, context) => {
  const clockNo = data.clockNo;
  console.log("🔄 createCustomToken called with clockNo:", clockNo);
  if (!clockNo) {
    console.error("❌ Missing clockNo");
    throw new https_1.HttpsError("invalid-argument", "clockNo is required");
  }
  try {
    console.log("🔍 Looking up employee doc:", clockNo);
    const employeeDoc = await admin.firestore().collection("employees").doc(clockNo).get();
    if (!employeeDoc.exists) {
      console.error("❌ Employee not found for clockNo:", clockNo);
      throw new https_1.HttpsError("not-found", "Employee not found");
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
    throw new https_1.HttpsError("internal", "Failed to create custom token", error);
  }
});
