# Firebase Notification Setup Guide

## What Was Fixed

Your app had **critical notification setup issues** preventing notifications from being delivered:

1. ❌ **No message handlers** → ✅ Added listeners for foreground & tap events
2. ❌ **Hardcoded server key** → ⚠️ Still needs to be replaced
3. ❌ **No token error logging** → ✅ Added detailed debug logging
4. ❌ **No notification validation** → ✅ Added token validation

## Remaining Action Required: Replace Server Key

### Option 1: Use Firebase Admin SDK (RECOMMENDED)
Create a backend service/Cloud Function instead of hardcoding credentials.

### Option 2: Quick Local Fix
Get your real server key from Firebase Console:

```
1. Go to Firebase Console → Your Project
2. Click ⚙️ (Project Settings)
3. Go to "Service Accounts" tab
4. Click "Generate New Private Key"
5. Open the downloaded JSON file
6. Find the "private_key" field
7. Replace the hardcoded key in main.dart (_sendPushNotification method)
```

## Testing Notifications

1. **Run the app** on Android/iOS device
2. **Tap "Refresh FCM Token"** button in the home screen
3. Go to **View Open Job Cards** → **Assign** someone
4. Check if:
   - ✅ Notification appears on assigned employee's device
   - ✅ Tapping notification opens "My Assigned Jobs"
   - ✅ Debug console shows "✅ Push notification sent successfully"

## Debug Logs to Watch For

When assigning a job, you should see:
```
✅ FCM Token saved successfully for [clock-no]: ...
✅ Push notification sent successfully
📨 Foreground message received: New Job Assigned
```

If you see errors, it's likely the server key issue.

## Files Modified
- `lib/main.dart` - Added message handlers and improved token management
