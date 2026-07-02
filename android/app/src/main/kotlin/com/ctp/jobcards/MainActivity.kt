package com.ctp.jobcards

import android.Manifest
import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import androidx.core.app.ActivityCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.LocationServices
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val GEOFENCE_CHANNEL = "ctp/geofence"
    private val JOB_ALERT_CHANNEL = "job_alert_channel"
    private val KIOSK_CHANNEL = "ctp/kiosk"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleDeepLink(intent)
        createUrgentNotificationChannel()

        // NOTE: USE_FULL_SCREEN_INTENT (Android 14+) is intentionally NOT requested
        // here. Redirecting to the system settings page from onCreate launched the
        // "full-screen takeover" settings screen before the app UI appeared on every
        // cold start that lacked the grant. It is now requested user-initiated from
        // the in-app permissions flow via flutter_local_notifications'
        // requestFullScreenIntentPermission() — see NotificationService.requestAllCriticalPermissions().
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Cache the engine so GeofenceReceiver can call back into Dart when the app is
        // in the foreground (notifyDart inside GeofenceReceiver uses this cache).
        FlutterEngineCache.getInstance().put(GeofenceReceiver.FLUTTER_ENGINE_ID, flutterEngine)

        // ==================== GEOFENCE CHANNEL ====================
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GEOFENCE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "registerGeofence" -> {
                        if (!isGooglePlayServicesAvailable()) {
                            Log.w(TAG, "⚠️ Google Play Services unavailable — skipping geofence registration")
                            result.error("PLAY_SERVICES_UNAVAILABLE", "Google Play Services unavailable", null)
                            return@setMethodCallHandler
                        }

                        val clockNo = call.argument<String>("clockNo")
                        val lat = call.argument<Double>("lat")
                        val lng = call.argument<Double>("lng")
                        val radius = call.argument<Double>("radius")?.toFloat()

                        if (clockNo != null && lat != null && lng != null && radius != null) {
                            try {
                                GeofenceHelper.registerGeofence(
                                    context = this,
                                    clockNo = clockNo,
                                    latitude = lat,
                                    longitude = lng,
                                    radius = radius
                                )
                                result.success(null)
                            } catch (e: Exception) {
                                Log.e(TAG, "❌ Geofence registration failed: ${e.message}")
                                result.error("GEOFENCE_ERROR", e.message, null)
                            }
                        } else {
                            result.error("INVALID_ARGS", "Missing parameters", null)
                        }
                    }

                    "stopGeofence" -> {
                        try {
                            GeofenceHelper.stopGeofence(this)
                            result.success(null)
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ stopGeofence failed: ${e.message}")
                            result.error("STOP_ERROR", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        // ==================== JOB ALERT CHANNEL ====================
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, JOB_ALERT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "triggerUrgentAlert" -> {
                        val jobCardNumber = call.argument<String>("jobCardNumber")
                        val description = call.argument<String>("description")
                        val location = call.argument<String>("location") ?: "Location not specified"
                        val createdBy = call.argument<String>("createdBy") ?: "Unknown"
                        val priority = call.argument<String>("priority") ?: "5"
                        if (jobCardNumber != null && description != null) {
                            triggerUrgentAlert(jobCardNumber, description, location, createdBy, priority, result)
                        } else {
                            result.error("INVALID_ARGUMENTS", "Missing jobCardNumber or description", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ==================== KIOSK MODE CHANNEL ====================
        // Locks the main-gate tablet to this app (Android Lock Task Mode).
        // Full protection (system "unpin" gesture fully blocked) requires
        // this app to be Device Owner (see KioskDeviceAdminReceiver);
        // otherwise this falls back to best-effort screen pinning.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, KIOSK_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isDeviceOwner" -> result.success(isDeviceOwnerApp())
                    "isLockTaskActive" -> result.success(isLockTaskActive())
                    "startKioskMode" -> {
                        try {
                            enterLockTask()
                            result.success(isDeviceOwnerApp())
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ startKioskMode failed: ${e.message}")
                            result.error("KIOSK_START_ERROR", e.message, null)
                        }
                    }
                    "stopKioskMode" -> {
                        try {
                            stopLockTask()
                            result.success(null)
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ stopKioskMode failed: ${e.message}")
                            result.error("KIOSK_STOP_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun kioskDeviceAdminComponent(): ComponentName =
        ComponentName(this, KioskDeviceAdminReceiver::class.java)

    private fun isDeviceOwnerApp(): Boolean {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        return dpm.isDeviceOwnerApp(packageName)
    }

    private fun enterLockTask() {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        if (dpm.isDeviceOwnerApp(packageName)) {
            val admin = kioskDeviceAdminComponent()
            // Only this app may run while locked; no back/recents/home/
            // notifications/power-menu escape hatch — the only way out is
            // this Activity calling stopLockTask() (gated behind the exit
            // code / admin login in Flutter's KioskModeScreen).
            dpm.setLockTaskPackages(admin, arrayOf(packageName))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                dpm.setLockTaskFeatures(admin, DevicePolicyManager.LOCK_TASK_FEATURE_NONE)
            }
        }
        // Without Device Owner this is plain screen pinning: still pins the
        // app, but the user can exit via the standard long-press back+
        // recents system gesture. Device Owner is what removes that gap.
        startLockTask()
    }

    private fun isLockTaskActive(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            return am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
        }
        @Suppress("DEPRECATION")
        return (getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).isInLockTaskMode
    }

    override fun onDestroy() {
        FlutterEngineCache.getInstance().remove(GeofenceReceiver.FLUTTER_ENGINE_ID)
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleDeepLink(intent)
    }

    private fun handleDeepLink(intent: Intent?) {
        intent?.let {
            val jobCardNumber = it.getStringExtra("jobCardNumber") ?: return
            val action = it.getStringExtra("action")
            val operator = it.getStringExtra("operator") ?: "Unknown"
            val clockNo = it.getStringExtra("clockNo") ?: ""
            val userName = it.getStringExtra("userName") ?: "Unknown User"

            Log.d(TAG, "🔗 Deep link — Job: $jobCardNumber, Action: $action, clockNo: $clockNo")

            // Save the pending job number to SharedPreferences so Flutter can pick it
            // up after the engine is ready (handles cold-start case where the Flutter
            // navigator isn't mounted yet when this code runs).
            getSharedPreferences("notification_prefs", MODE_PRIVATE)
                .edit()
                .putString("pendingJobCardNumber", jobCardNumber)
                .apply()

            // Cancel the notification from the shade now that the user has acted on it.
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancel(jobCardNumber.toIntOrNull() ?: 9999)

            when (action) {
                "view_job" -> navigateToJobDetail(jobCardNumber)
                "assign_self" -> assignJobToCurrentUser(jobCardNumber, clockNo, userName)
                "busy" -> sendBusyNotificationToOperator(jobCardNumber, operator, clockNo, userName)
                "dismiss" -> logDismissedAlert(jobCardNumber, operator, clockNo, userName)
                else -> navigateToJobDetail(jobCardNumber)  // no action = tap on body = view
            }
        }
    }

    // Tell Flutter to push the job detail screen. Safe to call even before the
    // engine is ready — the Flutter side also reads the pending number from
    // SharedPreferences on app start as a fallback.
    private fun navigateToJobDetail(jobCardNumber: String) {
        try {
            val messenger = flutterEngine?.dartExecutor?.binaryMessenger
                ?: FlutterEngineCache.getInstance().get("main_engine")?.dartExecutor?.binaryMessenger
            if (messenger != null) {
                MethodChannel(messenger, JOB_ALERT_CHANNEL)
                    .invokeMethod("navigateToJobDetail", mapOf("jobCardNumber" to jobCardNumber))
                Log.d(TAG, "✅ Requested navigation to job detail #$jobCardNumber")
            } else {
                Log.d(TAG, "ℹ️ Flutter engine not ready — Flutter will read pendingJobCardNumber on start")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to invoke navigateToJobDetail: ${e.message}")
        }
    }

    private fun getCurrentUserInfo(): Pair<String, String> {
        val prefs = getSharedPreferences("employee_prefs", MODE_PRIVATE)
        val clockNo = prefs.getString("clockNo", "") ?: ""
        val name = prefs.getString("employeeName", "Unknown User") ?: "Unknown User"
        return Pair(clockNo, name)
    }

    private fun assignJobToCurrentUser(jobCardNumber: String, clockNoFromIntent: String, userNameFromIntent: String) {
        var clockNo = clockNoFromIntent
        var userName = userNameFromIntent

        if (clockNo.isEmpty() || clockNo == "unknown") {
            val (prefsClockNo, prefsName) = getCurrentUserInfo()
            clockNo = prefsClockNo
            userName = prefsName
        }

        if (clockNo.isEmpty()) {
            Log.e(TAG, "Cannot assign — no logged-in user")
            Toast.makeText(this, "Please log in first", Toast.LENGTH_SHORT).show()
            finish()
            return
        }

        val db = FirebaseFirestore.getInstance()
        db.collection("job_cards")
            .whereEqualTo("jobCardNumber", jobCardNumber.toIntOrNull())
            .limit(1)
            .get()
            .addOnSuccessListener { documents ->
                if (documents.isEmpty) {
                    Log.e(TAG, "Job not found: $jobCardNumber")
                    Toast.makeText(this, "Job not found", Toast.LENGTH_SHORT).show()
                    finish()
                    return@addOnSuccessListener
                }

                val jobRef = documents.documents[0].reference

                // Race-safe assignment via transaction: only the first tapper wins.
                db.runTransaction { txn ->
                    val snapshot = txn.get(jobRef)
                    val existingAssignees = snapshot.get("assignedClockNos")
                    val alreadyAssigned = when (existingAssignees) {
                        is List<*> -> existingAssignees.isNotEmpty()
                        is String -> existingAssignees.isNotEmpty()
                        else -> false
                    }
                    if (alreadyAssigned) {
                        throw Exception("ALREADY_ASSIGNED")
                    }
                    txn.update(jobRef, mapOf(
                        "assignedTo" to clockNo,
                        "assignedNames" to userName,
                        "assignedClockNos" to listOf(clockNo),
                        "status" to "open",
                        "escalationStopped" to true,
                        "lastUpdatedAt" to FieldValue.serverTimestamp()
                    ))
                    null
                }.addOnSuccessListener {
                    Log.d(TAG, "✅ Job $jobCardNumber assigned to $userName ($clockNo)")
                    Toast.makeText(this, "✅ Job assigned to you!", Toast.LENGTH_LONG).show()
                    navigateToJobDetail(jobCardNumber)
                    finish()
                }.addOnFailureListener { e ->
                    if (e.message == "ALREADY_ASSIGNED") {
                        Log.w(TAG, "Job $jobCardNumber already assigned to someone else")
                        Toast.makeText(this, "Job already assigned to another technician", Toast.LENGTH_LONG).show()
                    } else {
                        Log.e(TAG, "Failed to assign job: ${e.message}")
                        Toast.makeText(this, "Failed to assign job", Toast.LENGTH_SHORT).show()
                    }
                    finish()
                }
            }
    }

    private fun sendBusyNotificationToOperator(
        jobCardNumber: String,
        originalOperator: String,
        clockNoFromIntent: String,
        userNameFromIntent: String
    ) {
        var clockNo = clockNoFromIntent
        var userName = userNameFromIntent

        if (clockNo.isEmpty() || clockNo == "unknown") {
            val (prefsClockNo, prefsName) = getCurrentUserInfo()
            clockNo = prefsClockNo
            userName = prefsName
        }

        FirebaseFirestore.getInstance().collection("notifications").add(
            mapOf(
                "jobCardNumber" to jobCardNumber.toIntOrNull(),
                "triggeredBy" to "busy",
                "initiatedByClockNo" to clockNo,
                "initiatedByName" to userName,
                "timestamp" to FieldValue.serverTimestamp(),
                "level" to "normal"
            )
        ).addOnSuccessListener {
            Log.d(TAG, "✅ Busy response logged for job $jobCardNumber by $userName")
            Toast.makeText(this, "✅ Busy response sent", Toast.LENGTH_LONG).show()
            finish()
        }
    }

    private fun logDismissedAlert(
        jobCardNumber: String,
        operator: String,
        clockNoFromIntent: String,
        userNameFromIntent: String
    ) {
        var clockNo = clockNoFromIntent
        var userName = userNameFromIntent

        if (clockNo.isEmpty() || clockNo == "unknown") {
            val (prefsClockNo, prefsName) = getCurrentUserInfo()
            clockNo = prefsClockNo
            userName = prefsName
        }

        FirebaseFirestore.getInstance().collection("notifications").add(
            mapOf(
                "jobCardNumber" to jobCardNumber.toIntOrNull(),
                "triggeredBy" to "dismiss",
                "initiatedByClockNo" to clockNo,
                "initiatedByName" to userName,
                "timestamp" to FieldValue.serverTimestamp(),
                "level" to "normal"
            )
        ).addOnSuccessListener {
            Log.d(TAG, "✅ Dismiss logged for job $jobCardNumber by $userName")
            Toast.makeText(this, "Alert dismissed", Toast.LENGTH_SHORT).show()
            finish()
        }
    }

    private fun triggerUrgentAlert(
        jobCardNumber: String,
        description: String,
        location: String,
        createdBy: String,
        priority: String,
        result: MethodChannel.Result
    ) {
        try {
            val serviceIntent = Intent(this, AlertForegroundService::class.java).apply {
                putExtra("jobCardNumber", jobCardNumber)
                putExtra("description", description)
                putExtra("location", location)
                putExtra("createdBy", createdBy)
                putExtra("priority", priority)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            result.success("Urgent alert triggered")
        } catch (e: Exception) {
            result.error("ALERT_ERROR", e.message, null)
        }
    }

    private fun createUrgentNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "urgent_alert_channel",
                "Urgent Job Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "High priority alerts for Priority 5 jobs"
                enableLights(true)
                lightColor = android.graphics.Color.RED
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500)
            }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    private fun isGooglePlayServicesAvailable(): Boolean {
        return try {
            val googleApiAvailability = com.google.android.gms.common.GoogleApiAvailability.getInstance()
            val resultCode = googleApiAvailability.isGooglePlayServicesAvailable(this)
            if (resultCode != com.google.android.gms.common.ConnectionResult.SUCCESS) {
                Log.e(TAG, "Google Play Services not available. Code: $resultCode")
                if (googleApiAvailability.isUserResolvableError(resultCode)) {
                    googleApiAvailability.getErrorDialog(this, resultCode, 9000)?.show()
                }
                return false
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "Exception checking Google Play Services: ${e.message}")
            false
        }
    }

    companion object {
        private const val TAG = "MainActivity"
    }
}
