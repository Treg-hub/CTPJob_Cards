package com.example.ctp_job_cards

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class AlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val jobCardNumber = intent.getStringExtra("jobCardNumber") ?: "Unknown"
        val description = intent.getStringExtra("description") ?: "Urgent job"
        val level = intent.getStringExtra("level") ?: "normal"
        val priority = intent.getStringExtra("priority") ?: "5"
        val createdBy = intent.getStringExtra("createdBy") ?: intent.getStringExtra("operator") ?: "Unknown"
        val location = intent.getStringExtra("location") ?: "Not specified"

        Log.d("AlarmReceiver", "🚨 AlarmReceiver triggered for job: $jobCardNumber (P$priority)")

        // Always launch full-screen (this receiver only fires when app is not visible)
        val fullScreenIntent = Intent(context, FullScreenJobAlertActivity::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("description", description)
            putExtra("level", level)
            putExtra("priority", priority)
            putExtra("createdBy", createdBy)
            putExtra("location", location)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }

        context.startActivity(fullScreenIntent)
    }
}