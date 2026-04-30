package com.example.ctp_job_cards

import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.media.MediaPlayer
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import android.view.View
import android.view.WindowManager
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.cardview.widget.CardView
import com.google.android.material.button.MaterialButton
import com.google.firebase.firestore.FirebaseFirestore
import java.text.SimpleDateFormat
import java.util.*

class FullScreenJobAlertActivity : ComponentActivity() {

    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var pulseAnimator: ValueAnimator? = null

    private var jobCardNumber: String = "Unknown"
    private var description: String = ""
    private var level: String = "normal"
    private var createdBy: String = ""
    private var location: String = ""
    private var dueDate: String = ""
    private var priority: String = "5"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // === LOCK SCREEN + FULL SCREEN HANDLING (Android 8.1+) ===
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        setContentView(R.layout.activity_full_screen_job_alert)

        // Extract ALL extras (enhanced)
        jobCardNumber = intent.getStringExtra("jobCardNumber") ?: "Unknown"
        description = intent.getStringExtra("description") ?: "Urgent job - no details provided"
        level = intent.getStringExtra("level") ?: "normal"
        createdBy = intent.getStringExtra("createdBy") ?: "Unknown"
        location = intent.getStringExtra("location") ?: "Not specified"
        dueDate = intent.getStringExtra("dueDate") ?: "ASAP"
        priority = intent.getStringExtra("priority") ?: "5"

        Log.d("FullScreenJobAlert", "🚨 Full screen alert shown for JOB #$jobCardNumber (P$priority)")

        setupUI()
        startAlarmSoundAndVibration()
        startHeaderPulseAnimation()

        // Prevent accidental back press
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                // Do nothing - user must choose an action
                Log.d("FullScreenJobAlert", "Back press blocked on alert screen")
            }
        })
    }

    private fun setupUI() {
        val tvJobNumber = findViewById<TextView>(R.id.tvJobNumber)
        val tvPriorityBadge = findViewById<TextView>(R.id.tvPriorityBadge)
        val tvLevel = findViewById<TextView>(R.id.tvLevel)
        val tvLocation = findViewById<TextView>(R.id.tvLocation)
        val tvCreatedBy = findViewById<TextView>(R.id.tvCreatedBy)
        val tvDueInfo = findViewById<TextView>(R.id.tvDueInfo)
        val tvDescription = findViewById<TextView>(R.id.tvDescription)

        val btnAssignSelf = findViewById<MaterialButton>(R.id.btnAssignSelf)
        val btnImBusy = findViewById<MaterialButton>(R.id.btnImBusy)
        val btnDismiss = findViewById<MaterialButton>(R.id.btnDismiss)

        // === POPULATE DATA ===
        tvJobNumber.text = "#$jobCardNumber"
        tvPriorityBadge.text = "P$priority"
        tvLevel.text = when (priority) {
            "5" -> "🔥 CRITICAL - PRIORITY 5"
            "4" -> "⚠️ HIGH - PRIORITY 4"
            else -> "MEDIUM PRIORITY"
        }
        tvLevel.setBackgroundColor(when (priority) {
            "5" -> 0xFFD32F2F.toInt()
            "4" -> 0xFFFF6F00.toInt()
            else -> 0xFF1976D2.toInt()
        })

        tvLocation.text = "📍 $location"
        tvCreatedBy.text = "👤 Created by: $createdBy"
        tvDueInfo.text = "⏰ Due: $dueDate"
        tvDescription.text = description

        // Color code priority badge
        tvPriorityBadge.setBackgroundColor(
            if (priority == "5") 0xFFFF5722.toInt() else 0xFFFF9800.toInt()
        )

        // === BUTTON LISTENERS ===
        btnAssignSelf.setOnClickListener {
            stopAlarm()
            val intent = Intent(this, MainActivity::class.java).apply {
                putExtra("jobCardNumber", jobCardNumber)
                putExtra("action", "assign_self")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            startActivity(intent)
            finish()
        }

        // I'm Busy - only for after hours
        if (shouldShowImBusyButton()) {
            btnImBusy.visibility = View.VISIBLE
            btnImBusy.setOnClickListener {
                stopAlarm()
                sendBusyNotificationToCreator()
                // Optional: Log busy response
                logUserResponse("busy")
                finish()
            }
        } else {
            btnImBusy.visibility = View.GONE
        }

        // Dismiss - check assignment status first
        checkIfJobIsAssigned { isAssigned ->
            if (isAssigned) {
                btnDismiss.visibility = View.GONE
                // If already assigned, maybe show "View Job" instead
            } else {
                btnDismiss.visibility = View.VISIBLE
                btnDismiss.setOnClickListener {
                    stopAlarm()
                    logDismissal()
                    logUserResponse("dismissed")
                    finish()
                }
            }
        }
    }

    private fun startHeaderPulseAnimation() {
        val header = findViewById<View>(R.id.headerContainer)
        pulseAnimator = ObjectAnimator.ofFloat(header, "alpha", 1f, 0.7f, 1f).apply {
            duration = 800
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.REVERSE
            interpolator = AccelerateDecelerateInterpolator()
            start()
        }
    }

    private fun shouldShowImBusyButton(): Boolean {
        val calendar = Calendar.getInstance()
        val day = calendar.get(Calendar.DAY_OF_WEEK)
        val hour = calendar.get(Calendar.HOUR_OF_DAY)

        // After hours logic (customize per company policy)
        return when (day) {
            Calendar.MONDAY, Calendar.TUESDAY, Calendar.WEDNESDAY, Calendar.THURSDAY -> hour >= 18 || hour < 6
            Calendar.FRIDAY -> hour >= 17
            Calendar.SATURDAY, Calendar.SUNDAY -> true
            else -> false
        }
    }

    private fun sendBusyNotificationToCreator() {
        if (createdBy.isEmpty()) return
        Log.d("FullScreenJobAlert", "📤 Sending 'I'm busy' response to creator: $createdBy")
        // TODO: Implement Cloud Function call or Firestore write to notify creator
        // Example: Call Firebase Function "notifyCreatorBusy"
    }

    private fun checkIfJobIsAssigned(callback: (Boolean) -> Unit) {
        val db = FirebaseFirestore.getInstance()
        db.collection("job_cards")
            .whereEqualTo("jobCardNumber", jobCardNumber)
            .limit(1)
            .get()
            .addOnSuccessListener { documents ->
                if (!documents.isEmpty) {
                    val job = documents.documents[0]
                    val assignedTo = job.get("assignedTo") as? String
                    val assignedClockNos = job.get("assignedClockNos") as? List<*>
                    val isAssigned = !assignedTo.isNullOrEmpty() || (assignedClockNos?.isNotEmpty() == true)
                    callback(isAssigned)
                } else {
                    callback(false)
                }
            }
            .addOnFailureListener { e ->
                Log.e("FullScreenJobAlert", "Firestore check failed: ${e.message}")
                callback(false)
            }
    }

    private fun logDismissal() {
        val db = FirebaseFirestore.getInstance()
        val dismissal = hashMapOf(
            "jobCardNumber" to jobCardNumber,
            "dismissedAt" to com.google.firebase.Timestamp.now(),
            "level" to level,
            "priority" to priority,
            "dismissedBy" to "unknown" // TODO: Get from SharedPrefs / current user
        )
        db.collection("dismissedAlerts").add(dismissal)
            .addOnSuccessListener { Log.d("FullScreenJobAlert", "✅ Dismissal logged") }
    }

    private fun logUserResponse(action: String) {
        val db = FirebaseFirestore.getInstance()
        val response = hashMapOf(
            "jobCardNumber" to jobCardNumber,
            "action" to action,
            "timestamp" to com.google.firebase.Timestamp.now(),
            "user" to "unknown"
        )
        db.collection("alertResponses").add(response)
    }

    private fun startAlarmSoundAndVibration() {
        try {
            // Use your custom sound in res/raw/escalation_alert.mp3 or .ogg
            mediaPlayer = MediaPlayer.create(this, R.raw.escalation_alert)
            mediaPlayer?.isLooping = true
            mediaPlayer?.start()

            vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vm.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }

            // Strong, repeating pattern for urgency
            val pattern = longArrayOf(0, 600, 200, 600, 200, 600, 200, 1200)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
            }
            Log.d("FullScreenJobAlert", "🔊 Alarm + vibration started (escalation_alert)")
        } catch (e: Exception) {
            Log.e("FullScreenJobAlert", "Sound/vibration error: ${e.message}")
            // Fallback: system default alarm sound
        }
    }

    private fun stopAlarm() {
        try {
            pulseAnimator?.cancel()
            mediaPlayer?.apply {
                stop()
                release()
            }
            mediaPlayer = null
            vibrator?.cancel()
            vibrator = null
            Log.d("FullScreenJobAlert", "🔇 Alarm stopped by user action")
        } catch (e: Exception) {
            Log.e("FullScreenJobAlert", "Stop alarm error: ${e.message}")
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopAlarm()
    }
}