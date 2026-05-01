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
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val GEOFENCE_CHANNEL = "ctp/geofence"
    private val JOB_ALERT_CHANNEL = "job_alert_channel"
    private lateinit var geofencingClient: GeofencingClient
    private val geofencePendingIntent: PendingIntent by lazy {
        val intent = Intent(this, GeofenceReceiver::class.java)
        PendingIntent.getBroadcast(this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        Log.d("FullScreenJobAlertActivity", "🚀 FULL SCREEN ACTIVITY STARTED!")
        Log.d("FullScreenJobAlertActivity", "Job: ${intent.getStringExtra("jobCardNumber")}")
        super.onCreate(savedInstanceState)

        handleDeepLink(intent)
        
        // ✅ Create urgent notification channel early (IMPORTANT!)
        createUrgentNotificationChannel()
        
        geofencingClient = LocationServices.getGeofencingClient(this)

        // Check Full-Screen Intent permission (Android 14+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (!notificationManager.canUseFullScreenIntent()) {
                Log.w("MainActivity", "Full-Screen Intent permission not granted - opening settings")
                val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
                intent.data = Uri.fromParts("package", packageName, null)
                startActivity(intent)
            }
        }

        // Request USE_FULL_SCREEN_INTENT permission for full-screen notifications (API 34+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.USE_FULL_SCREEN_INTENT) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.USE_FULL_SCREEN_INTENT), 1001)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleDeepLink(intent)
    }

    private fun handleDeepLink(intent: Intent?) {
        val jobCardNumber = intent?.getStringExtra("jobCardNumber")
        val action = intent?.getStringExtra("action")

        if (jobCardNumber != null) {
            Log.d("MainActivity", "🔗 Deep link received - Job: $jobCardNumber, Action: $action")
            
            // The LoginScreen will pick this up via ModalRoute arguments
            // If you want to send it to Flutter, you can use a MethodChannel here
        }
    }

    // ✅ NEW METHOD - Creates the urgent channel early
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
        Log.d("MainActivity", "🚀 configureFlutterEngine called - Registering channels")
        super.configureFlutterEngine(flutterEngine)

        // Geofence channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GEOFENCE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startGeofence" -> {
                    val clockNo = call.argument<String>("clockNo")
                    val lat = call.argument<Double>("lat")
                    val lng = call.argument<Double>("lng")
                    val radius = call.argument<Double>("radius")
                    if (clockNo != null && lat != null && lng != null && radius != null) {
                        startGeofence(clockNo, lat, lng, radius, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "Missing arguments", null)
                    }
                }
                "stopGeofence" -> {
                    stopGeofence(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Job alert channel
        Log.d("MainActivity", "🚨 Registering job_alert_channel")
        Log.d("MainActivity", "🚀 MethodChannel job_alert_channel registered")
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, JOB_ALERT_CHANNEL).setMethodCallHandler { call, result ->
            Log.d("MainActivity", "🚨 Job alert channel received method: ${call.method}")
            when (call.method) {
                "triggerUrgentAlert" -> {
                val jobCardNumber = call.argument<String>("jobCardNumber")
                val description = call.argument<String>("description")
                val location = call.argument<String>("location") ?: "Location not specified"
                val createdBy = call.argument<String>("createdBy") ?: "Unknown"
                val priority = call.argument<String>("priority") ?: "5"

                Log.d("MainActivity", "🚨 triggerUrgentAlert called with jobCardNumber=$jobCardNumber, priority=$priority")

                if (jobCardNumber != null && description != null) {
                    triggerUrgentAlert(jobCardNumber, description, location, createdBy, priority, result)
                } else {
                    Log.e("MainActivity", "🚨 INVALID_ARGUMENTS: jobCardNumber=$jobCardNumber, description=$description")
                    result.error("INVALID_ARGUMENTS", "Missing jobCardNumber or description", null)
                }
            }
        }
    }

    private fun startGeofence(clockNo: String, lat: Double, lng: Double, radius: Double, result: MethodChannel.Result) {
        val geofence = Geofence.Builder()
            .setRequestId("company_geofence_$clockNo")
            .setCircularRegion(lat, lng, radius.toFloat())
            .setExpirationDuration(Geofence.NEVER_EXPIRE)
            .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT)
            .build()

        val geofencingRequest = GeofencingRequest.Builder()
            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
            .addGeofence(geofence)
            .build()

        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            result.error("PERMISSION_DENIED", "Location permission not granted", null)
            return
        }

        geofencingClient.addGeofences(geofencingRequest, geofencePendingIntent).run {
            addOnSuccessListener {
                Log.d("MainActivity", "Geofence added successfully for clockNo=$clockNo")
                result.success("Geofence started")
            }
            addOnFailureListener { e ->
                Log.e("MainActivity", "Geofence add failed: $e")
                result.error("GEOFENCE_ERROR", "Failed to add geofence: ${e.message}", null)
            }
        }
    }

    private fun stopGeofence(result: MethodChannel.Result) {
        geofencingClient.removeGeofences(geofencePendingIntent).run {
            addOnSuccessListener {
                Log.d("MainActivity", "Geofence removed successfully")
                result.success("Geofence stopped")
            }
            addOnFailureListener { e ->
                Log.e("MainActivity", "Geofence remove failed: $e")
                result.error("GEOFENCE_ERROR", "Failed to remove geofence: ${e.message}", null)
            }
        }
    }

    private fun triggerUrgentAlert(call: MethodCall, result: MethodChannel.Result) {
    try {
        val jobCardNumber = call.argument<String>("jobCardNumber") ?: "Unknown"
        val description = call.argument<String>("description") ?: "Urgent job"
        val location = call.argument<String>("location") ?: "Location not specified"
        val createdBy = call.argument<String>("createdBy") ?: "Unknown"
        val priority = call.argument<String>("priority") ?: "5"

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

        Log.d("MainActivity", "🚨 Urgent alert triggered for job #$jobCardNumber (P$priority)")
        result.success("Urgent alert triggered")
    } catch (e: Exception) {
        Log.e("MainActivity", "Failed to trigger urgent alert: $e")
        result.error("ALERT_ERROR", e.message, null)
    }
}