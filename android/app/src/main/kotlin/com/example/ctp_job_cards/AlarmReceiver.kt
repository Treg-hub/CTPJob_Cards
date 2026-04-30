package com.example.ctp_job_cards

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class AlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        Log.d("AlarmReceiver", "🚨 AlarmReceiver triggered for job: ${intent.getStringExtra("jobCardNumber")}")

        val jobCardNumber = intent.getStringExtra("jobCardNumber") ?: "Unknown"
        val description = intent.getStringExtra("description") ?: "Urgent job"
        val level = intent.getStringExtra("level") ?: "normal"

        // Launch FullScreenJobAlertActivity
        val fullScreenIntent = Intent(context, FullScreenJobAlertActivity::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("description", description)
            putExtra("level", level)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        context.startActivity(fullScreenIntent)
    }
}