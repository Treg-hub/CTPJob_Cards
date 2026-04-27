package com.example.ctp_job_cards

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class FullScreenJobAlertActivity : AppCompatActivity() {

    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Set full screen flags
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON
        )

        setContentView(R.layout.activity_full_screen_alert)

        // Get data from intent
        val jobCardNumber = intent?.getStringExtra("jobCardNumber") ?: "Unknown"
        val description = intent?.getStringExtra("description") ?: "No description available"

        // Update UI elements
        val jobNumberText = findViewById<TextView>(R.id.jobNumberText)
        val descriptionText = findViewById<TextView>(R.id.descriptionText)

        jobNumberText.text = "Job #$jobCardNumber"
        descriptionText.text = description

        // Auto dismiss after 10 seconds
        handler.postDelayed({
            finish()
        }, 10000)
    }

    override fun onDestroy() {
        super.onDestroy()
        handler.removeCallbacksAndMessages(null)
    }
}