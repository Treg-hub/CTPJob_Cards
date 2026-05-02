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

class FullScreenJobAlertActivity : ComponentActivity() {
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var pulseAnimator: ValueAnimator? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Always show full-screen when this activity is launched
        // (AlarmReceiver only calls this when app is not visible)

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

    private fun isAppInForeground(context: Context): Boolean {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val appProcesses = activityManager.runningAppProcesses ?: return false
        val packageName = context.packageName

        val processInfo = appProcesses.find { it.processName == packageName }
            ?: return false

        if (processInfo.importance != ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND) {
            return false
        }

        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val keyguardManager = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager

        val isScreenOn = powerManager.isInteractive
        val isKeyguardLocked = keyguardManager.isKeyguardLocked

        return isScreenOn && !isKeyguardLocked
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

        // Buttons
        btnAssignSelf.setOnClickListener {
            stopAlarm()
            val i = Intent(this, MainActivity::class.java).apply {
                putExtra("jobCardNumber", jobCardNumber)
                putExtra("action", "assign_self")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            startActivity(i)
            finish()
        }

        if (shouldShowImBusyButton()) {
            btnImBusy.visibility = View.VISIBLE
            btnImBusy.setOnClickListener {
                stopAlarm()
                finish()
            }
        } else {
            btnImBusy.visibility = View.GONE
        }

        btnDismiss.setOnClickListener {
            stopAlarm()
            finish()
        }
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