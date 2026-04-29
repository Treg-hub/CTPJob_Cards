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
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback

/**
 * FullScreenJobAlertActivity - Final version
 * Uses custom escalation_alert sound from res/raw/
 */
class FullScreenJobAlertActivity : ComponentActivity() {

    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var jobCardNumber: String = "Unknown"
    private var description: String = ""

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

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) {
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            @Suppress("DEPRECATION")
            keyguardManager.requestDismissKeyguard(this, null)
        }

        setContentView(R.layout.activity_full_screen_job_alert)

        jobCardNumber = intent.getStringExtra("jobCardNumber") ?: "Unknown"
        description = intent.getStringExtra("description") ?: "Urgent job"

        Log.d("FullScreenJobAlert", "🚨 Full screen alert shown for job #$jobCardNumber")

        setupUI()
        startAlarmSoundAndVibration()

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                // Prevent back button
            }
        })
    }

    private fun setupUI() {
        val tvJobNumber = findViewById<TextView>(R.id.tvJobNumber)
        val tvDescription = findViewById<TextView>(R.id.tvDescription)
        val btnAcknowledge = findViewById<Button>(R.id.btnAcknowledge)
        val btnDismiss = findViewById<Button>(R.id.btnDismiss)

        tvJobNumber.text = "JOB #$jobCardNumber"
        tvDescription.text = description

        btnAcknowledge.setOnClickListener {
            stopAlarm()
            val intent = Intent(this, MainActivity::class.java).apply {
                putExtra("jobCardNumber", jobCardNumber)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            startActivity(intent)
            finish()
        }

        btnDismiss.setOnClickListener {
            stopAlarm()
            finish()
        }

        // Auto-dismiss after 90 seconds
        android.os.Handler(mainLooper).postDelayed({
            if (!isFinishing) {
                stopAlarm()
                finish()
            }
        }, 90000)
    }

    private fun startAlarmSoundAndVibration() {
        try {
            // Use custom escalation_alert sound from res/raw/
            mediaPlayer = MediaPlayer.create(this, R.raw.escalation_alert)
            mediaPlayer?.isLooping = true
            mediaPlayer?.start()

            // Vibration
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
            // Fallback to system alarm if custom sound fails
            try {
                mediaPlayer = MediaPlayer.create(this, android.provider.Settings.System.DEFAULT_ALARM_ALERT_URI)
                mediaPlayer?.isLooping = true
                mediaPlayer?.start()
            } catch (ex: Exception) {
                Log.e("FullScreenJobAlert", "Fallback also failed: ${ex.message}")
            }
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
        } catch (e: Exception) {
            Log.e("FullScreenJobAlert", "Error stopping alarm: ${e.message}")
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopAlarm()
    }
}