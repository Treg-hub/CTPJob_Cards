package com.example.ctp_job_cards

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
import android.widget.Button
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import com.google.firebase.firestore.FirebaseFirestore
import java.util.*

class FullScreenJobAlertActivity : ComponentActivity() {

    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var jobCardNumber: String = "Unknown"
    private var description: String = ""
    private var level: String = "normal"
    private var createdBy: String = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Show on lock screen + turn screen on
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        setContentView(R.layout.activity_full_screen_job_alert)

        jobCardNumber = intent.getStringExtra("jobCardNumber") ?: "Unknown"
        description = intent.getStringExtra("description") ?: "Urgent job"
        level = intent.getStringExtra("level") ?: "normal"
        createdBy = intent.getStringExtra("createdBy") ?: ""

        Log.d("FullScreenJobAlert", "🚨 Full screen alert shown for job #$jobCardNumber (Level: $level)")

        setupUI()
        startAlarmSoundAndVibration()

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {}
        })
    }

    private fun setupUI() {
        val tvJobNumber = findViewById<TextView>(R.id.tvJobNumber)
        val tvDescription = findViewById<TextView>(R.id.tvDescription)

        val btnAssignSelf = findViewById<Button>(R.id.btnAssignSelf)
        val btnViewJob = findViewById<Button>(R.id.btnViewJob)
        val btnImBusy = findViewById<Button>(R.id.btnImBusy)
        val btnDismiss = findViewById<Button>(R.id.btnDismiss)

        tvJobNumber.text = "JOB #$jobCardNumber"
        tvDescription.text = description

        // === ASSIGN SELF ===
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

        // === VIEW JOB ===
        btnViewJob.setOnClickListener {
            stopAlarm()
            val intent = Intent(this, MainActivity::class.java).apply {
                putExtra("jobCardNumber", jobCardNumber)
                putExtra("action", "view_job")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            startActivity(intent)
            finish()
        }

        // === I'M BUSY (Only show during night/weekend hours) ===
        if (shouldShowImBusyButton()) {
            btnImBusy.visibility = View.VISIBLE
            btnImBusy.setOnClickListener {
                stopAlarm()
                sendBusyNotificationToCreator()
                finish()
            }
        } else {
            btnImBusy.visibility = View.GONE
        }

        // === DISMISS (Only if no one is assigned yet) ===
        checkIfJobIsAssigned { isAssigned ->
            if (isAssigned) {
                btnDismiss.visibility = View.GONE
            } else {
                btnDismiss.visibility = View.VISIBLE
                btnDismiss.setOnClickListener {
                    stopAlarm()
                    logDismissal()
                    finish()
                }
            }
        }
    }

    private fun shouldShowImBusyButton(): Boolean {
        val calendar = Calendar.getInstance()
        val day = calendar.get(Calendar.DAY_OF_WEEK)
        val hour = calendar.get(Calendar.HOUR_OF_DAY)

        return when (day) {
            Calendar.MONDAY,
            Calendar.TUESDAY,
            Calendar.WEDNESDAY,
            Calendar.THURSDAY -> hour >= 18 || hour < 6
            Calendar.FRIDAY -> hour >= 18
            Calendar.SATURDAY,
            Calendar.SUNDAY -> true
            else -> false
        }
    }

    private fun sendBusyNotificationToCreator() {
        if (createdBy.isEmpty()) return
        Log.d("FullScreenJobAlert", "📨 Sending 'I'm busy' notification to creator: $createdBy")
        // TODO: Call your Cloud Function here to send push notification
    }

    private fun checkIfJobIsAssigned(callback: (Boolean) -> Unit) {
        val db = FirebaseFirestore.getInstance()
        db.collection("job_cards")
            .whereEqualTo("jobCardNumber", jobCardNumber.toIntOrNull() ?: 0)
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
            .addOnFailureListener {
                callback(false)
            }
    }

    private fun logDismissal() {
        val db = FirebaseFirestore.getInstance()
        val dismissal = hashMapOf(
            "jobCardNumber" to jobCardNumber,
            "dismissedAt" to com.google.firebase.Timestamp.now(),
            "level" to level,
            "dismissedBy" to "unknown" // TODO: Replace with actual user clock number
        )
        db.collection("dismissedAlerts").add(dismissal)
        Log.d("FullScreenJobAlert", "📝 Dismissal logged for job #$jobCardNumber")
    }

    private fun startAlarmSoundAndVibration() {
        try {
            mediaPlayer = MediaPlayer.create(this, R.raw.escalation_alert)
            mediaPlayer?.isLooping = true
            mediaPlayer?.start()

            vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vibratorManager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }

            val pattern = longArrayOf(0, 800, 400, 800, 400, 800, 400, 800)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
            }
            Log.d("FullScreenJobAlert", "🔊 Using escalation_alert sound + vibration")
        } catch (e: Exception) {
            Log.e("FullScreenJobAlert", "Failed to play escalation_alert: ${e.message}")
        }
    }

    private fun stopAlarm() {
        try {
            mediaPlayer?.stop()
            mediaPlayer?.release()
            mediaPlayer = null
            vibrator?.cancel()
            vibrator = null
            Log.d("FullScreenJobAlert", "🔇 Alarm stopped")
        } catch (e: Exception) {}
    }

    override fun onDestroy() {
        super.onDestroy()
        stopAlarm()
    }
}