const admin = require("firebase-admin");
const serviceAccount = require("../serviceAccountKey.json");
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: "ctp-job-cards",
});

const employees = [
  {clockNo: "7776", department: "Workshop", name: "TE Khoza", position: "Electrician Assistant"},
  {clockNo: "7027", department: "Workshop", name: "S Reddy", position: "Electrician"},
  {clockNo: "19017", department: "Workshop", name: "SJ Kweyama", position: "Electrician"},
  {clockNo: "4749", department: "Workshop", name: "W Singh", position: "Electrician"},
  {clockNo: "19045", department: "Workshop", name: "P Reddy", position: "Electrician"},
  {clockNo: "19060", department: "Workshop", name: "K Mfeka", position: "Electrician"},
  {clockNo: "7930", department: "Workshop", name: "P Moodley", position: "Electrician"},
  {clockNo: "9805", department: "Lurgi", name: "Pillay J", position: "Operator"},
  {clockNo: "19050", department: "Lurgi", name: "Thevar M", position: "Operator"},
  {clockNo: "8026", department: "Lurgi", name: "Khenisa MS", position: "Operator"},
  {clockNo: "8037", department: "Lurgi", name: "Mthembu SC", position: "Operator"},
  {clockNo: "9871", department: "Lurgi", name: "Chetty C", position: "Operator"},
  {clockNo: "19038", department: "Workshop", name: "J Biyela", position: "Mechanical Assistant"},
  {clockNo: "19049", department: "Workshop", name: "A Naicker", position: "Mechanical Assistant"},
  {clockNo: "7785", department: "Workshop", name: "S Bhugwandeen", position: "Mechanical"},
  {clockNo: "8033", department: "Workshop", name: "L Ruthnum", position: "Mechanical"},
  {clockNo: "8903", department: "Workshop", name: "A Ally", position: "Mechanical"},
  {clockNo: "19039", department: "Workshop", name: "A Maharaj", position: "Mechanical"},
  {clockNo: "19048", department: "Workshop", name: "C Cele", position: "Mechanical"},
  {clockNo: "19035", department: "Workshop", name: "S Wanda", position: "Mechanical"},
  {clockNo: "4416", department: "Workshop", name: "B Morton", position: "Mechanical"},
  {clockNo: "7485", department: "Workshop", name: "MRM Bhengu", position: "Mechanical"},
  {clockNo: "8856", department: "Workshop", name: "N Malan", position: "Mechanical"},
  {clockNo: "9373", department: "Workshop", name: "PN Khumalo", position: "Mechanical"},
  {clockNo: "5480", department: "Workshop", name: "SL Madondo", position: "Mechanical"},
  {clockNo: "8040", department: "Post Press", name: "Subramoney CM", position: "Co Ordinator"},
  {clockNo: "6739", department: "Post Press", name: "Govender D", position: "Co Ordinator"},
  {clockNo: "5911", department: "Post Press", name: "S Naicker", position: "Co Ordinator"},
  {clockNo: "7051", department: "Post Press", name: "Perumaul WM", position: "Crew"},
  {clockNo: "1116", department: "Post Press", name: "Govender S", position: "Despatch Assistant"},
  {clockNo: "2989", department: "Post Press", name: "Mncwabe D", position: "Despatch Assistant"},
  {clockNo: "9501", department: "Post Press", name: "Sheik Gudoo ME", position: "Despatch Shift Leader"},
  {clockNo: "4639", department: "Post Press", name: "Moodley DR", position: "Hyster Driver"},
  {clockNo: "7786", department: "Post Press", name: "Shozi ZR", position: "Hyster Driver"},
  {clockNo: "19043", department: "Post Press", name: "Ngcobo ZE", position: "Hyster Driver"},
  {clockNo: "19055", department: "Post Press", name: "V Moneypersadh", position: "Hyster Driver"},
  {clockNo: "19056", department: "Post Press", name: "S Dlamini", position: "Hyster Driver"},
  {clockNo: "19057", department: "Post Press", name: "Cele JS", position: "Operator"},
  {clockNo: "3164", department: "Post Press", name: "MP Dlomo ", position: "Operator"},
  {clockNo: "4630", department: "Post Press", name: "Mdlalose SM", position: "Operator"},
  {clockNo: "5013", department: "Post Press", name: "Ngobese MI", position: "Operator"},
  {clockNo: "5765", department: "Post Press", name: "Ntombela SP", position: "Operator"},
  {clockNo: "7160", department: "Post Press", name: "Ngwenya ET", position: "Operator"},
  {clockNo: "9771", department: "Post Press", name: "D Gounden ", position: "Shift Leader"},
  {clockNo: "19003", department: "Post Press", name: "Govender L", position: "Shift Leader"},
  {clockNo: "19018", department: "Post Press", name: "Naidoo N", position: "Shift Leader"},
  {clockNo: "19029", department: "Post Press", name: "Madurai S", position: "Shift Leader"},
  {clockNo: "19046", department: "Post Press", name: "Gopichund K", position: "Shift Leader"},
  {clockNo: "19052", department: "Post Press", name: "Govender D", position: "Shift Leader"},
  {clockNo: "1050", department: "Post Press", name: "Karanjewan K", position: "Shift Leader"},
  {clockNo: "4126", department: "Post Press", name: "R Ganasen ", position: "Shrinkwrap Operator"},
  {clockNo: "4129", department: "Post Press", name: "M Gounden ", position: "Shrinkwrap Operator"},
  {clockNo: "6923", department: "Post Press", name: "Pillay M", position: "Shrinkwrap Operator"},
  {clockNo: "23192", department: "Post Press", name: "Bux A", position: "Shrinkwrap Operator"},
  {clockNo: "5801", department: "Post Press", name: "G Naicker ", position: "Shrinkwrap Operator"},
  {clockNo: "9503", department: "Post Press", name: "Manqele ZW", position: "Shrinkwrap Operator"},
  {clockNo: "19033", department: "Post Press", name: "ZS Adam ", position: "Shrinkwrap Operator"},
  {clockNo: "19053", department: "Post Press", name: "IS Zulu ", position: "Shrinkwrap Operator"},
  {clockNo: "19058", department: "Pre Press", name: "T Naicker", position: "CU Plater Stripper"},
  {clockNo: "2992", department: "Pre Press", name: "MN Gumede", position: "CU Plater Stripper"},
  {clockNo: "3262", department: "Pre Press", name: "MS Ncube", position: "CU Plater Stripper"},
  {clockNo: "3669", department: "Pre Press", name: "MM Mbhele", position: "CU Plater Stripper"},
  {clockNo: "6195", department: "Pre Press", name: "S Mazubane", position: "DTG Operator"},
  {clockNo: "19042", department: "Pre Press", name: "A Buthelezi", position: "DTG Operator"},
  {clockNo: "3852", department: "Pre Press", name: "KJ Botha", position: "DTG Operator"},
  {clockNo: "5902", department: "Pre Press", name: "DB Walton", position: "DTG Operator "},
  {clockNo: "5900", department: "Pre Press", name: "J Sosibo", position: "DTG Operator "},
  {clockNo: "5913", department: "Pre Press", name: "FP Ngidi", position: "Operator"},
  {clockNo: "6585", department: "Pre Press", name: "M Ramsuth", position: "Operator"},
  {clockNo: "4513", department: "Pre Press", name: "Z Sayed", position: "Operator"},
  {clockNo: "5901", department: "Pre Press", name: "AJ Naidoo", position: "Operator"},
  {clockNo: "5915", department: "Pre Press", name: "C Dindikazi", position: "Operator"},
  {clockNo: "4636", department: "Pre Press", name: "T Cupusamy", position: "Revisionist"},
  {clockNo: "5914", department: "Pre Press", name: "NW Mthiyane", position: "Revisionist"},
  {clockNo: "4517", department: "Pre Press", name: "AW Azeez", position: "Shift Leader"},
  {clockNo: "19014", department: "Pre Press", name: "SJ Kweyama", position: "Shift Leader"},
  {clockNo: "7715", department: "Pre Press", name: "VS Mtsiki", position: "Shift Leader"},
  {clockNo: "8269", department: "Pre Press", name: "SS Zulu", position: "Shift Leader"},
  {clockNo: "19028", department: "Pre Press", name: "MO Mbambo", position: "Shift Leader"},
  {clockNo: "5908", department: "Pressroom", name: "MD Luthuli ", position: "Crew"},
  {clockNo: "5909", department: "Pressroom", name: "SA Xaba ", position: "Crew"},
  {clockNo: "5912", department: "Pressroom", name: "R Mpanza", position: "Crew"},
  {clockNo: "5916", department: "Pressroom", name: "SP Mala ", position: "Crew"},
  {clockNo: "5906", department: "Pressroom", name: "SL Mbambo ", position: "Crew"},
  {clockNo: "7142", department: "Pressroom", name: "DP Zama ", position: "Crew"},
  {clockNo: "7292", department: "Pressroom", name: "A Kalicharan ", position: "Crew"},
  {clockNo: "8087", department: "Pressroom", name: "LS Mthembu", position: "Crew"},
  {clockNo: "8861", department: "Pressroom", name: "Khomo HM", position: "Crew"},
  {clockNo: "8863", department: "Pressroom", name: "Maduma DK", position: "Crew"},
  {clockNo: "9372", department: "Pressroom", name: "Zuma N", position: "Crew"},
  {clockNo: "5216", department: "Pressroom", name: "Nontshe MV", position: "Crew"},
  {clockNo: "7490", department: "Pressroom", name: "MI Khathi", position: "Crew"},
  {clockNo: "7770", department: "Pressroom", name: "C Binneman ", position: "Foreman"},
  {clockNo: "9514", department: "Pressroom", name: "Mohammed S", position: "Foreman"},
  {clockNo: "6769", department: "Pressroom", name: "K Maharaj", position: "Foreman"},
  {clockNo: "6584", department: "Pressroom", name: "M Windvogel ", position: "Foreman"},
  {clockNo: "5905", department: "Pressroom", name: "DW Zietsman ", position: "No1"},
  {clockNo: "7967", department: "Pressroom", name: "MB Campbell ", position: "No1"},
  {clockNo: "5422", department: "Pressroom", name: "EG Hood ", position: "No1"},
  {clockNo: "5750", department: "Pressroom", name: "Naidoo J", position: "No1"},
  {clockNo: "6222", department: "Pressroom", name: "Gallant GT", position: "No1"},
  {clockNo: "5045", department: "Pressroom", name: "January MA", position: "No1"},
  {clockNo: "7743", department: "Pressroom", name: "Cressey ST", position: "No1"},
  {clockNo: "8106", department: "Pressroom", name: "S Ramjan ", position: "No2"},
  {clockNo: "9894", department: "Pressroom", name: "T Magwanyana", position: "No2"},
  {clockNo: "8181", department: "Pressroom", name: "N Ramdas ", position: "No2"},
  {clockNo: "4122", department: "Pressroom", name: "DA Pillay ", position: "No2"},
  {clockNo: "3027", department: "Pressroom", name: "O Govindasamy ", position: "No2"},
  {clockNo: "3586", department: "Pressroom", name: "A Sihlobo", position: "No2"},
  {clockNo: "3875", department: "Pressroom", name: "Rooplal VH", position: "No2"},
  {clockNo: "3026", department: "Pressroom", name: "M Mthuli", position: "No2"},
  {clockNo: "3593", department: "Pressroom", name: "A Desai  ", position: "Reelstand Operator"},
  {clockNo: "3920", department: "Pressroom", name: "TP Gumede ", position: "Reelstand Operator"},
  {clockNo: "5119", department: "Pressroom", name: "VM Khuzwayo ", position: "Reelstand Operator"},
  {clockNo: "6095", department: "Pressroom", name: "TG Sosibo ", position: "Reelstand Operator"},
  {clockNo: "8019", department: "Pressroom", name: "R Dunpath ", position: "Reelstand Operator"},
  {clockNo: "19040", department: "Pressroom", name: "Rajoo L", position: "Reelstand Operator"},
  {clockNo: "19041", department: "Stores", name: "S Radebe", position: "Hyster Driver"},
  {clockNo: "7293", department: "Stores", name: "SS Dlamini", position: "Storeperson"},
  {clockNo: "7787", department: "Stores", name: "NL Khanyile", position: "Storeperson"},
  {clockNo: "9689", department: "Stores", name: "B Tunzi", position: "Storeperson"},
  {clockNo: "9800", department: "Stores", name: "LJ Xaba", position: "Storeperson"},
  {clockNo: "9899", department: "Stores", name: "MA Zuma", position: "Storeperson"},
  {clockNo: "19036", department: "Stores", name: "ZB Ngcobo", position: "Storeperson"},
  {clockNo: "19054", department: "Stores", name: "L Khumalo", position: "Storeperson"},
  {clockNo: "10003", department: "Workshop", name: "V Govender", position: "Manager"},
  {clockNo: "20", department: "Pre Press", name: "R Davidson", position: "Manager"},
  {clockNo: "22", department: "Pressroom", name: "G Peens", position: "Manager"},
  {clockNo: "23158", department: "Post Press", name: "S Dhavaraj", position: "Manager"},
  {clockNo: "23165", department: "Pressroom", name: "T Simpkins", position: "Manager"},
  {clockNo: "5421", department: "Pre Press", name: "M Govender", position: "Manager"},
  {clockNo: "9999", department: "Stores", name: "Z Govender", position: "Manager"},
  {clockNo: "1", department: "General", name: "User", position: "Manager"},
];

/**
 * Clears all existing employees and updates with new data.
 * @return {Promise<void>}
 */
async function clearAndUpdate() {
  const db = admin.firestore();

  // Delete all existing employees
  const snapshot = await db.collection("employees").get();
  const deleteBatch = db.batch();
  snapshot.docs.forEach((doc) => deleteBatch.delete(doc.ref));
  await deleteBatch.commit();
  console.log(`Deleted ${snapshot.size} existing employees`);

  // Add new employees in batches (Firestore batch limit is 500)
  const batchSize = 500;
  for (let i = 0; i < employees.length; i += batchSize) {
    const batch = db.batch();
    const batchEmployees = employees.slice(i, i + batchSize);
    batchEmployees.forEach((emp) => {
      const docRef = db.collection("employees").doc(emp.clockNo);
      batch.set(docRef, {
        clockNo: emp.clockNo,
        name: emp.name,
        position: emp.position,
        department: emp.department,
        isOnSite: true,
      });
    });
    await batch.commit();
    console.log(`Added batch ${Math.floor(i / batchSize) + 1}: ${batchEmployees.length} employees`);
  }

  console.log(`Total added: ${employees.length} employees`);
}

clearAndUpdate().catch(console.error);
