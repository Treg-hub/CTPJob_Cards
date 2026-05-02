package com.example.ctp_job_cards

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class FirebaseMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        Log.d("FCM_DEBUG", "═══════════════════════════════════════════════")
        Log.d("FCM_DEBUG", "📩 FCM MESSAGE RECEIVED IN NATIVE SERVICE")
        Log.d("FCM_DEBUG", "Level: ${remoteMessage.data["notificationLevel"]}")
        Log.d("FCM_DEBUG", "Job #: ${remoteMessage.data["jobCardNumber"]}")
        Log.d("FCM_DEBUG", "═══════════════════════════════════════════════")

        val level = remoteMessage.data["notificationLevel"] ?: "normal"
        val jobCardNumber = remoteMessage.data["jobCardNumber"] ?: "Unknown"
        val description = remoteMessage.data["description"] ?: remoteMessage.data["body"] ?: "Job update"
        val priority = remoteMessage.data["priority"] ?: "5"
        val operator = remoteMessage.data["operator"] ?: remoteMessage.data["createdBy"] ?: "Unknown"

        // Build location string from individual fields (same as Dart side)
        val department = remoteMessage.data["department"] ?: ""
        val area = remoteMessage.data["area"] ?: ""
        val machine = remoteMessage.data["machine"] ?: ""
        val part = remoteMessage.data["part"] ?: ""
        val location = listOf(department, area, machine, part)
            .filter { it.isNotEmpty() }
            .joinToString(" > ")
            .ifEmpty { "Not specified" }

        if (level == "full-loud") {
            // P5 → Full-screen only (no banner)
            Log.d("FCM_DEBUG", "🚨 P5 job #$jobCardNumber - Full-screen only mode")
            scheduleFullScreenAlarm(jobCardNumber, description, level, priority, operator, location)
        } else {
            // P4 and lower → Show banner with buttons
            showNotificationWithButtons(level, "Job #$jobCardNumber", jobCardNumber, description)

            if (level == "medium-high") {
                Log.d("FCM_DEBUG", "🚨 P4 job #$jobCardNumber - Trying full-screen alarm")
                scheduleFullScreenAlarm(jobCardNumber, description, level, priority, operator, location)
            }
        }
    }

    private fun scheduleFullScreenAlarm(
        jobCardNumber: String,
        description: String,
        level: String,
        priority: String = "5",
        createdBy: String = "Unknown",
        location: String = "Not specified"
    ) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
            Log.e("FCM_DEBUG", "❌ Cannot schedule exact alarms - permission missing")
            return
        }

        val triggerTime = System.currentTimeMillis() + 3000

        val alarmIntent = Intent(this, AlarmReceiver::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("description", description)
            putExtra("level", level)
            putExtra("priority", priority)
            putExtra("createdBy", createdBy)
            putExtra("location", location)
        }

        val pendingIntent = PendingIntent.getBroadcast(
            this,
            jobCardNumber.hashCode(),
            alarmIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        try {
            val showIntent = PendingIntent.getBroadcast(
                this,
                jobCardNumber.hashCode() + 1,
                alarmIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val alarmInfo = AlarmManager.AlarmClockInfo(triggerTime, showIntent)
            alarmManager.setAlarmClock(alarmInfo, pendingIntent)
            Log.d("FCM_DEBUG", "✅ Full-screen alarm scheduled for job #$jobCardNumber")
        } catch (e: Exception) {
            Log.e("FCM_DEBUG", "❌ Failed to schedule alarm: ${e.message}")
        }
    }

    private fun showNotificationWithButtons(level: String, title: String, jobCardNumber: String, description: String) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = if (level == "full-loud" || level == "medium-high") "urgent_alert_channel" else "normal_channel"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                if (level == "full-loud" || level == "medium-high") "Urgent Job Alerts" else "Normal Job Notifications",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                this.description = "Job notifications with action buttons"
                enableLights(true)
                lightColor = if (level == "full-loud") Color.RED else Color.YELLOW
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(channel)
        }

        // Intent for "View Job" button
        val viewIntent = Intent(this, MainActivity::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("action", "view_job")
        }
        val viewPendingIntent = PendingIntent.getActivity(
            this, 0, viewIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Intent for "Assign Self" button
        val assignIntent = Intent(this, MainActivity::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("action", "assign_self")
        }
        val assignPendingIntent = PendingIntent.getActivity(
            this, 1, assignIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(description)
            .setStyle(NotificationCompat.BigTextStyle().bigText(description))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(viewPendingIntent)
            .setAutoCancel(true)
            .addAction(0, "Assign Self", assignPendingIntent)
            .addAction(0, "View Job", viewPendingIntent)

        if (level == "full-loud") {
            builder.setColor(Color.RED)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
        } else if (level == "medium-high") {
            builder.setColor(Color.parseColor("#FF9800"))
        }

        notificationManager.notify(jobCardNumber.hashCode(), builder.build())
    }
}