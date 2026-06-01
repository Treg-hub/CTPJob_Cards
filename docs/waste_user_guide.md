# CTP WasteTrack — User Guide

*For Security Managers and Security Guards*

---

## What Is WasteTrack?

WasteTrack is the module in the CTP Job Cards app used to manage all outgoing waste loads from the factory. It tracks what waste leaves the site, who collected it, how much it weighed, and whether the recorded weight matched the actual weighbridge weight.

This guide is for the two roles that operate WasteTrack day-to-day:

| Role | Responsibilities |
|------|-----------------|
| **Security Manager** | Schedule waste loads; approve or reject loads; review reports and deviation alerts; manage contractors and waste types |
| **Security Guard** | Receive scheduled loads; begin the collection with the contractor; record waste items and photographs; sign off at the weighbridge |

> **Admin** users have full access to all WasteTrack screens plus the admin configuration panel.

---

## Section 1: Accessing WasteTrack

WasteTrack is reached from the bottom navigation bar in the main app. You will see a **Waste** tab. If you do not see it, your account has not been granted a WasteTrack role — contact an admin.

From the WasteTrack home screen you can see:
- Loads that have been scheduled and are waiting for collection
- Loads currently in progress (collection started)
- Loads pending weighbridge sign-off
- A summary of completed and queued loads

---

## Section 2: For Security Managers — Scheduling a Load

### Creating a New Schedule

1. Tap **Schedule Load** from the WasteTrack home screen.
2. Select the **contractor** who will collect the load.
3. Select the **main waste type** (e.g. general, hazardous, recyclables).
4. Set a **scheduled date and time** for the collection.
5. Add a **note** if any special instructions apply.
6. Tap **Schedule** to save.

The load will appear in the home screen under "Scheduled" and will be visible to security guards on duty.

### Managing Existing Loads

From the **Loads** screen you can:
- View the full details of any load
- Edit a scheduled load before collection begins
- Cancel a load that is no longer needed (enter a reason)
- See the status of in-progress and completed loads

### Reviewing Reports

Open **Reports & Export** from the WasteTrack home screen.

1. Set a **date range** and optionally filter by contractor or waste type.
2. Tap **Run Report** to load results.
3. Tap **Export CSV** or **Export PDF** to download the report.

The report shows: load number, date, contractor, waste type, recorded weight, actual weighbridge weight, and any deviation flags.

---

## Section 3: For Security Guards — Processing a Collected Load

### Step 1: Begin Collection

When a contractor arrives to collect waste:

1. On the WasteTrack home screen, find the scheduled load for this contractor. Tap **Begin Collection**.
2. Confirm the contractor and load details are correct.
3. Tap **Begin** to start the collection. The load status changes to **In Progress**.

### Step 2: Add Waste Items

During collection, add each type of waste being loaded:

1. Tap **Add Item**.
2. Select the **waste category** (e.g. cardboard, scrap metal, e-waste).
3. Enter the **recorded weight** in kg (the weight as measured on site before the truck leaves).
4. Take a **photo** of the waste. At least one item must have a photo.
5. Tap **Save Item**.

Repeat for each waste type in the load.

> **Why photos are required:** Photographs provide a record that waste left the site and confirm what was collected. They are part of the legal audit trail.

### Step 3: Capture Contractor Signature

Once all items are added:

1. Tap **Capture Signature**.
2. Pass the phone to the contractor driver.
3. The driver signs in the signature box.
4. Tap **Accept Signature**.

### Step 4: Weighbridge Sign-Off

After the truck returns from the weighbridge:

1. On the load detail screen, tap **Enter Weighbridge Weight**.
2. Enter the **actual weighbridge weight** in kg (the certified weight from the external weighbridge).
3. Tap **Confirm**.

The system automatically compares the recorded weight to the actual weight. If the difference exceeds **5% or 50 kg**, a **deviation flag** is set. The security manager will see this highlighted in reports.

> A deviation is not automatically an error — it can result from differences in how waste was measured. The flag exists so management can review it and decide if investigation is needed.

### Step 5: Complete the Load

Once the weighbridge weight is confirmed, tap **Complete Load**. The load status changes to **Completed** and the record is locked.

---

## Section 4: Load Statuses

| Status | Meaning |
|--------|---------|
| **Scheduled** | A manager has created the load and it is waiting for the contractor to arrive |
| **In Progress** | A guard has started the collection — items are being added |
| **Pending Weighbridge** | Collection is done; waiting for the actual weighbridge weight to be entered |
| **Completed** | Weighbridge weight confirmed; load record is finalised |
| **Cancelled** | Load was cancelled before or during collection |

---

## Section 5: Deviation Alerts

A deviation is flagged when the difference between the **recorded weight** (measured on site) and the **actual weighbridge weight** (certified by external scale) exceeds the threshold.

**Thresholds:**
- More than **5%** difference relative to the recorded weight, OR
- More than **50 kg** difference in absolute terms

Either condition alone is enough to trigger the flag.

If a load has a deviation, it appears with an amber warning in the load detail and in reports. Managers should review flagged loads and note any explanation in the load record.

---

## Section 6: Notification Inbox

If you are **off site** when a notification is generated (for example, a manager schedules a load while you are not yet on shift), the notification is held in your **Notification Inbox** rather than sent as a push alert.

When you arrive on site and open the app, a banner will appear at the bottom of the screen if notifications are waiting. Tap **Open** to see them.

You can also reach your inbox at any time from the bell icon in the top bar.

---

## Section 7: Troubleshooting

**I cannot see the Waste tab in the app.**
Your account has not been assigned a WasteTrack role. Contact your admin — they can set this in Admin Settings → Employees.

**A scheduled load is not appearing on my home screen.**
Check the scheduled date on the load. Loads only appear as "ready for collection" on or after the scheduled date. Also confirm the load has not been cancelled.

**I cannot begin a collection.**
The load may already be in progress from another guard, or it may have been cancelled. Check the load status in the Loads screen.

**The signature screen is not working / accepting input.**
Ensure the device screen is clean and dry. The driver must sign with a single finger or stylus. If the signature is not accepted, try again on a clean area of the glass.

**The photo requirement is blocking me from proceeding.**
At least one waste item must have a photo before the collection can be completed. Tap **Add Item**, take the photo, and add the item to proceed.

**A deviation flag was set but the weights look correct.**
Check that both weights were entered in **kilograms**. If one was entered in tonnes accidentally, correct the weighbridge weight entry. If the weights are genuinely correct, add an explanatory note to the load record and escalate to the manager for review.

---

*CTP WasteTrack · Security Staff Guide*
