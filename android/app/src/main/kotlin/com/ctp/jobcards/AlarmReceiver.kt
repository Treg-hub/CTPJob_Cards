package com.ctp.jobcards

import android.app.ActivityManager
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
        val createdBy = intent.getStringExtra("operator") ?: "Unknown"
        val location = intent.getStringExtra("location") ?: "Not specified"

        Log.d("AlarmReceiver", "🚨 AlarmReceiver triggered for job: $jobCardNumber (P$priority)")

        // ==================== SKIP IF APP IS OPEN ====================
        if (isAppInForeground(context)) {
            Log.d("AlarmReceiver", "App is OPEN → skipping full-screen for job #$jobCardNumber")
            return
        }

        // Launch full-screen only when app is NOT visible
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

    private fun isAppInForeground(context: Context): Boolean {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val appProcesses = activityManager.runningAppProcesses ?: return false
        val packageName = context.packageName

        val processInfo = appProcesses.find { it.processName == packageName }
            ?: return false

        return processInfo.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
    }
}
