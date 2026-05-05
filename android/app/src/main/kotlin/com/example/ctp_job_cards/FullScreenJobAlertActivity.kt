package com.example.ctp_job_cards

import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.app.ActivityManager
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.media.MediaPlayer
import android.media.AudioAttributes
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.os.PowerManager
import android.util.Log
import android.view.View
import android.view.WindowManager
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import com.google.android.material.button.MaterialButton
import com.google.firebase.firestore.FirebaseFirestore
import com.google.android.gms.tasks.Tasks
import java.util.concurrent.TimeUnit
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngineCache

class FullScreenJobAlertActivity : ComponentActivity() {

    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var pulseAnimator: ValueAnimator? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

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
        setupUI()
        startAlarmSoundAndVibration()
        startHeaderPulseAnimation()

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {}
        })
    }

    private fun setupUI() {
        val tvJobNumber = findViewById<TextView>(R.id.tvJobNumber)
        val tvPriorityBadge = findViewById<TextView>(R.id.tvPriorityBadge)
        val tvLevel = findViewById<TextView>(R.id.tvLevel)
        val tvLocation = findViewById<TextView>(R.id.tvLocation)
        val tvCreatedBy = findViewById<TextView>(R.id.tvCreatedBy)
        val tvDescription = findViewById<TextView>(R.id.tvDescription)
        val btnAssignSelf = findViewById<MaterialButton>(R.id.btnAssignSelf)
        val btnImBusy = findViewById<MaterialButton>(R.id.btnImBusy)
        val btnDismiss = findViewById<MaterialButton>(R.id.btnDismiss)

        val jobCardNumber = intent.getStringExtra("jobCardNumber") ?: "Unknown"
        val priority = intent.getStringExtra("priority") ?: "5"
        val createdBy = intent.getStringExtra("createdBy") ?: "Unknown"
        val location = intent.getStringExtra("location") ?: "Location not specified"
        val description = intent.getStringExtra("description") ?: "No description"
        val level = intent.getStringExtra("level") ?: "normal"

        tvJobNumber.text = "#$jobCardNumber"
        tvPriorityBadge.text = "P$priority"
        tvLevel.text = when (priority) {
            "5" -> "🔥 CRITICAL - PRIORITY 5"
            "4" -> "⚠️ HIGH - PRIORITY 4"
            else -> "MEDIUM PRIORITY"
        }
        tvLevel.setBackgroundColor(if (priority == "5") 0xFFD32F2F.toInt() else 0xFFFF9800.toInt())
        tvLocation.text = location
        tvCreatedBy.text = "👤 Created by: $createdBy"
        tvDescription.text = description

        // ==================== BUTTONS (Option B - calls Dart) ====================

        btnAssignSelf.setOnClickListener {
            stopAlarm()
            callDartAction("assign_self", jobCardNumber)
        }

        if (shouldShowImBusyButton()) {
            btnImBusy.visibility = View.VISIBLE
            btnImBusy.setOnClickListener {
                stopAlarm()
                callDartAction("busy", jobCardNumber)
            }
        } else {
            btnImBusy.visibility = View.GONE
        }

        btnDismiss.setOnClickListener {
            stopAlarm()
            callDartAction("dismiss", jobCardNumber)
        }
    }

    private fun callDartAction(action: String, jobCardNumber: String) {
        try {
            val engine = FlutterEngineCache.getInstance().get("main_engine")
            if (engine != null) {
                MethodChannel(engine.dartExecutor.binaryMessenger, "com.example.ctp_job_cards/notification_actions")
                    .invokeMethod("handleAction", mapOf("action" to action, "jobCardNumber" to jobCardNumber))
            }
        } catch (e: Exception) {
            Log.e("FullScreenJobAlert", "Failed to call Dart: ${e.message}")
        }
        finish()
    }

    private fun shouldShowImBusyButton(): Boolean {
        val cal = java.util.Calendar.getInstance()
        val day = cal.get(java.util.Calendar.DAY_OF_WEEK)
        val hour = cal.get(java.util.Calendar.HOUR_OF_DAY)
        return when (day) {
            java.util.Calendar.MONDAY, java.util.Calendar.TUESDAY,
            java.util.Calendar.WEDNESDAY, java.util.Calendar.THURSDAY -> hour >= 18 || hour < 6
            java.util.Calendar.FRIDAY -> hour >= 17
            java.util.Calendar.SATURDAY, java.util.Calendar.SUNDAY -> true
            else -> false
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

    private fun startAlarmSoundAndVibration() {
        try {
            mediaPlayer = MediaPlayer.create(this, R.raw.escalation_alert)?.apply {
                isLooping = true
                start()
            }
            vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            val pattern = longArrayOf(0, 600, 200, 600, 200, 600, 200, 1200)
            val vibrationEffect = VibrationEffect.createWaveform(pattern, 0)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val audioAttributes = android.media.AudioAttributes.Builder()
                    .setUsage(android.media.AudioAttributes.USAGE_ALARM)
                    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                vibrator?.vibrate(vibrationEffect, audioAttributes)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(vibrationEffect)
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
            }
        } catch (e: Exception) {
            Log.e("FullScreenJobAlert", "Alarm error: ${e.message}")
        }
    }

    private fun stopAlarm() {
        pulseAnimator?.cancel()
        mediaPlayer?.apply { if (isPlaying) stop(); release() }
        mediaPlayer = null
        vibrator?.cancel()
        vibrator = null
    }

    override fun onDestroy() {
        super.onDestroy()
        stopAlarm()
    }
}