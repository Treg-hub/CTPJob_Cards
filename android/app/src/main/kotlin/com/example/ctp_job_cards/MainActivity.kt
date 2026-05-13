package com.example.ctp_job_cards

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import android.widget.Toast
import androidx.core.app.ActivityCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val GEOFENCE_CHANNEL = "ctp/geofence"
    private val JOB_ALERT_CHANNEL = "job_alert_channel"
    private lateinit var geofencingClient: GeofencingClient

    private val geofencePendingIntent: PendingIntent by lazy {
        val intent = Intent(this, GeofenceReceiver::class.java)
        PendingIntent.getBroadcast(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleDeepLink(intent)
        createUrgentNotificationChannel()
        geofencingClient = LocationServices.getGeofencingClient(this)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (!notificationManager.canUseFullScreenIntent()) {
                val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
                intent.data = Uri.fromParts("package", packageName, null)
                startActivity(intent)
            }
        }
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

            Log.d("MainActivity", "🔗 Deep link - Job: $jobCardNumber, Action: $action, Operator: $operator, clockNo: $clockNo, userName: $userName")

            when (action) {
                "assign_self" -> assignJobToCurrentUser(jobCardNumber, clockNo, userName)
                "busy" -> sendBusyNotificationToOperator(jobCardNumber, operator, clockNo, userName)
                "dismiss" -> logDismissedAlert(jobCardNumber, operator, clockNo, userName)
            }
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
            Log.e("MainActivity", "Cannot assign - no logged in user")
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
                    Log.e("MainActivity", "Job not found: $jobCardNumber")
                    Toast.makeText(this, "Job not found", Toast.LENGTH_SHORT).show()
                    finish()
                    return@addOnSuccessListener
                }

                val doc = documents.documents[0]
                doc.reference.update(
                    mapOf(
                        "assignedTo" to clockNo,
                        "assignedNames" to userName,
                        "assignedClockNos" to clockNo,
                        "status" to "open",
                        "lastUpdatedAt" to FieldValue.serverTimestamp()
                    )
                ).addOnSuccessListener {
                    Log.d("MainActivity", "✅ Job $jobCardNumber assigned to $userName ($clockNo)")
                    Toast.makeText(this, "✅ Job assigned to you!", Toast.LENGTH_LONG).show()
                    finish()
                }.addOnFailureListener { e ->
                    Log.e("MainActivity", "Failed to assign job: ${e.message}")
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

        val db = FirebaseFirestore.getInstance()
        db.collection("notifications").add(
            mapOf(
                "jobCardNumber" to jobCardNumber.toIntOrNull(),
                "triggeredBy" to "busy",
                "initiatedByClockNo" to clockNo,
                "initiatedByName" to userName,
                "timestamp" to FieldValue.serverTimestamp(),
                "level" to "normal"
            )
        ).addOnSuccessListener {
            Log.d("MainActivity", "✅ Busy response logged for job $jobCardNumber by $userName")
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

        val db = FirebaseFirestore.getInstance()
        db.collection("notifications").add(
            mapOf(
                "jobCardNumber" to jobCardNumber.toIntOrNull(),
                "triggeredBy" to "dismiss",
                "initiatedByClockNo" to clockNo,
                "initiatedByName" to userName,
                "timestamp" to FieldValue.serverTimestamp(),
                "level" to "normal"
            )
        ).addOnSuccessListener {
            Log.d("MainActivity", "✅ Dismiss logged for job $jobCardNumber by $userName")
            Toast.makeText(this, "Alert dismissed", Toast.LENGTH_SHORT).show()
            finish()
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
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ==================== GEOFENCE CHANNEL ====================
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GEOFENCE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "registerGeofence" -> {
                        if (!isGooglePlayServicesAvailable()) {
                            Log.w("MainActivity", "⚠️ Google Play Services check failed - skipping geofence")
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
                                Log.e("MainActivity", "❌ Geofence registration failed: ${e.message}")
                                result.error("GEOFENCE_ERROR", e.message, null)
                            }
                        } else {
                            result.error("INVALID_ARGS", "Missing parameters", null)
                        }
                    }
                }
            }

        // ==================== JOB ALERT CHANNEL ====================
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, JOB_ALERT_CHANNEL).setMethodCallHandler { call, result ->
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

    private fun isGooglePlayServicesAvailable(): Boolean {
        return try {
            val googleApiAvailability = com.google.android.gms.common.GoogleApiAvailability.getInstance()
            val resultCode = googleApiAvailability.isGooglePlayServicesAvailable(this)
            
            if (resultCode != com.google.android.gms.common.ConnectionResult.SUCCESS) {
                Log.e("MainActivity", "Google Play Services not available. Error code: $resultCode")
                
                // Optional: Show user-friendly message
                if (googleApiAvailability.isUserResolvableError(resultCode)) {
                    googleApiAvailability.getErrorDialog(this, resultCode, 9000)?.show()
                }
                return false
            }
            true
        } catch (e: Exception) {
            Log.e("MainActivity", "Exception while checking Google Play Services: ${e.message}")
            false
        }
    }
}