package com.example.ctp_job_cards

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * AlarmReceiver - Receives the alarm from AlarmManager and launches the full-screen alert activity.
 * 
 * This is the key piece that makes urgent P5 notifications reliable in background/killed state
 * on Android 14+ and Huawei devices.
 */
class AlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val jobCardNumber = intent.getStringExtra("jobCardNumber") ?: "Unknown"
        val description = intent.getStringExtra("description") ?: "Urgent job alert"

        Log.d("AlarmReceiver", "🚨 AlarmReceiver triggered for job #$jobCardNumber")

        // Launch the full-screen alert activity
        val fullScreenIntent = Intent(context, FullScreenJobAlertActivity::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("description", description)
            // These flags are critical for launching from background/killed state
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
        }

        try {
            context.startActivity(fullScreenIntent)
            Log.d("AlarmReceiver", "✅ FullScreenJobAlertActivity launched for job #$jobCardNumber")
        } catch (e: Exception) {
            Log.e("AlarmReceiver", "❌ Failed to start FullScreenJobAlertActivity: ${e.message}")
        }
    }
}