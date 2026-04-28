package com.example.ctp_job_cards

import android.Manifest
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
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

        geofencingClient = LocationServices.getGeofencingClient(this)

        // Request USE_FULL_SCREEN_INTENT permission for full-screen notifications (API 34+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.USE_FULL_SCREEN_INTENT) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.USE_FULL_SCREEN_INTENT), 1001)
            }
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
                    Log.d("MainActivity", "🚨 triggerUrgentAlert called with jobCardNumber=$jobCardNumber, description=$description")
                    if (jobCardNumber != null && description != null) {
                        triggerUrgentAlert(jobCardNumber, description, result)
                    } else {
                        Log.e("MainActivity", "🚨 INVALID_ARGUMENTS: jobCardNumber=$jobCardNumber, description=$description")
                        result.error("INVALID_ARGUMENTS", "Missing jobCardNumber or description", null)
                    }
                }
                else -> {
                    Log.w("MainActivity", "🚨 Unknown method: ${call.method}")
                    result.notImplemented()
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

    private fun triggerUrgentAlert(jobCardNumber: String, description: String, result: MethodChannel.Result) {
        try {
            val intent = Intent(this, AlertForegroundService::class.java).apply {
                putExtra("jobCardNumber", jobCardNumber)
                putExtra("description", description)
            }
            startForegroundService(intent)
            Log.d("MainActivity", "Urgent alert triggered for job #$jobCardNumber")
            result.success("Urgent alert triggered")
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to trigger urgent alert: $e")
            result.error("ALERT_ERROR", "Failed to trigger urgent alert: ${e.message}", null)
        }
    }
}
