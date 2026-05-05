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
import androidx.core.content.ContextCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.functions.FirebaseFunctions
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
        Log.d("MainActivity", "🚀 MainActivity started")
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
        val jobCardNumber = intent?.getStringExtra("jobCardNumber") ?: return
        val action = intent.getStringExtra("action")
        
        // Read the real values passed from Flutter
        val operator = intent.getStringExtra("operator") 
            ?: intent.getStringExtra("createdBy") 
            ?: "Unknown Operator"
        
        val clockNo = intent.getStringExtra("clockNo") ?: "unknown"
        val userName = intent.getStringExtra("userName") ?: "Unknown User"

        Log.d("MainActivity", "🔗 Deep link - Job: $jobCardNumber, Action: $action, Operator: $operator, clockNo: $clockNo, userName: $userName")

        when (action) {
            "assign_self" -> assignJobToCurrentUser(jobCardNumber)
            "busy" -> sendBusyNotificationToOperator(jobCardNumber, operator, clockNo, userName)
            "dismiss" -> logDismissedAlert(jobCardNumber, operator, clockNo, userName)
            else -> {}
        }
    }

    // ==================== NOTIFICATION ACTION HANDLERS ====================

    // ==================== ASSIGN SELF ====================
    private fun assignJobToCurrentUser(jobCardNumber: String) {
        val currentUser = FirebaseAuth.getInstance().currentUser
        if (currentUser == null) {
            Toast.makeText(this, "Please log in first", Toast.LENGTH_SHORT).show()
            return
        }

        val firebaseUid = currentUser.uid
        val realClockNo = if (firebaseUid.startsWith("employee_")) firebaseUid.substring(9) else firebaseUid

        // Get real clockNo and name from employees collection
        FirebaseFirestore.getInstance()
            .collection("employees")
            .document(realClockNo)
            .get()
            .addOnSuccessListener { employeeDoc ->
                val clockNo = employeeDoc.getString("clockNo") ?: realClockNo
                val userName = employeeDoc.getString("name") ?: currentUser.displayName ?: currentUser.email ?: "Unknown User"

                // Assign the job
                FirebaseFirestore.getInstance()
                    .collection("job_cards")
                    .whereEqualTo("jobCardNumber", jobCardNumber)
                    .limit(1)
                    .get()
                    .addOnSuccessListener { querySnapshot ->
                        if (querySnapshot.isEmpty) {
                            Toast.makeText(this, "Job not found", Toast.LENGTH_SHORT).show()
                            return@addOnSuccessListener
                        }

                        val jobDoc = querySnapshot.documents[0]
                        jobDoc.reference.update(
                            mapOf(
                                "assignedTo" to clockNo,
                                "assignedToName" to userName,
                                "status" to "assigned",
                                "assignedAt" to FieldValue.serverTimestamp(),
                                "lastUpdatedBy" to clockNo,
                                "lastUpdatedByName" to userName
                            )
                        )
                        .addOnSuccessListener {
                            Toast.makeText(this, "✅ Job assigned to you!", Toast.LENGTH_LONG).show()
                        }
                        .addOnFailureListener { e ->
                            Toast.makeText(this, "Failed to assign: ${e.message}", Toast.LENGTH_SHORT).show()
                        }
                    }
            }
    }

    // ==================== BUSY RESPONSE ====================
    private fun sendBusyNotificationToOperator(
        jobCardNumber: String,
        originalOperator: String,
        clockNoFromIntent: String,
        userNameFromIntent: String
    ) {
        val currentUser = FirebaseAuth.getInstance().currentUser ?: return
        val firebaseUid = currentUser.uid
        val realClockNo = if (firebaseUid.startsWith("employee_")) firebaseUid.substring(9) else firebaseUid

        FirebaseFirestore.getInstance()
            .collection("employees")
            .document(realClockNo)
            .get()
            .addOnSuccessListener { employeeDoc ->
                val clockNo = employeeDoc.getString("clockNo") ?: realClockNo
                val userName = employeeDoc.getString("name") ?: currentUser.displayName ?: currentUser.email ?: "Unknown User"

                val busyData = hashMapOf(
                    "action" to "busy",
                    "jobCardNumber" to jobCardNumber,
                    "clockNo" to clockNo,
                    "userName" to userName,
                    "originalOperator" to originalOperator,
                    "timestamp" to FieldValue.serverTimestamp()
                )

                FirebaseFirestore.getInstance()
                    .collection("alertResponses")
                    .add(busyData)
                    .addOnSuccessListener {
                        Toast.makeText(this, "✅ Busy response sent", Toast.LENGTH_LONG).show()
                    }
            }
    }

    // ==================== DISMISSED ALERT ====================
    private fun logDismissedAlert(
        jobCardNumber: String,
        operator: String,
        clockNoFromIntent: String,
        userNameFromIntent: String
    ) {
        val currentUser = FirebaseAuth.getInstance().currentUser ?: return
        val firebaseUid = currentUser.uid
        val realClockNo = if (firebaseUid.startsWith("employee_")) firebaseUid.substring(9) else firebaseUid

        FirebaseFirestore.getInstance()
            .collection("employees")
            .document(realClockNo)
            .get()
            .addOnSuccessListener { employeeDoc ->
                val clockNo = employeeDoc.getString("clockNo") ?: realClockNo
                val userName = employeeDoc.getString("name") ?: currentUser.displayName ?: currentUser.email ?: "Unknown User"

                val dismissData = hashMapOf(
                    "action" to "dismissed",
                    "jobCardNumber" to jobCardNumber,
                    "clockNo" to clockNo,
                    "userName" to userName,
                    "originalOperator" to operator,
                    "timestamp" to FieldValue.serverTimestamp()
                )

                FirebaseFirestore.getInstance()
                    .collection("alertResponses")
                    .add(dismissData)
                    .addOnSuccessListener {
                        Toast.makeText(this, "Alert dismissed", Toast.LENGTH_SHORT).show()
                    }
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
                "stopGeofence" -> stopGeofence(result)
                else -> result.notImplemented()
            }
        }

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
                Log.d("MainActivity", "Geofence added successfully")
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
}