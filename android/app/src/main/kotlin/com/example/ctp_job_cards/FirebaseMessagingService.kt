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
        Log.d(TAG, "═══════════════════════════════════════════════")
        Log.d(TAG, "📩 FCM MESSAGE RECEIVED")
        Log.d(TAG, "Level: ${remoteMessage.data["notificationLevel"]}")
        Log.d(TAG, "Job #: ${remoteMessage.data["jobCardNumber"]}")
        Log.d(TAG, "═══════════════════════════════════════════════")

        val level = remoteMessage.data["notificationLevel"] ?: "normal"
        val jobCardNumber = remoteMessage.data["jobCardNumber"] ?: "Unknown"
        val description = remoteMessage.data["description"] ?: remoteMessage.data["body"] ?: "Job update"
        val priority = remoteMessage.data["priority"] ?: "5"
        val operator = remoteMessage.data["operator"] ?: remoteMessage.data["createdBy"] ?: "Unknown"

        val department = remoteMessage.data["department"] ?: ""
        val area = remoteMessage.data["area"] ?: ""
        val machine = remoteMessage.data["machine"] ?: ""
        val part = remoteMessage.data["part"] ?: ""
        val location = listOf(department, area, machine, part)
            .filter { it.isNotEmpty() }
            .joinToString(" > ")
            .ifEmpty { "Not specified" }

        when (level) {
            "full-loud" -> {
                // P5: full-screen alarm is primary. If exact alarms are unavailable
                // (permission not granted), fall back to a persistent banner so the
                // technician still sees something.
                if (canScheduleExactAlarms()) {
                    Log.d(TAG, "🚨 P5 — scheduling full-screen alarm for job #$jobCardNumber")
                    scheduleFullScreenAlarm(jobCardNumber, description, level, priority, operator, location)
                } else {
                    Log.w(TAG, "⚠️ P5 — exact alarms unavailable, falling back to persistent banner")
                    showPersistentBanner(level, "🚨 Urgent Job #$jobCardNumber", jobCardNumber, description, operator)
                }
            }
            "medium-high" -> {
                // P4: persistent banner only — no full-screen alarm.
                Log.d(TAG, "🔔 P4 — showing persistent banner for job #$jobCardNumber")
                showPersistentBanner(level, "Job #$jobCardNumber", jobCardNumber, description, operator)
            }
            else -> {
                // P1–P3: standard banner.
                Log.d(TAG, "🔔 Normal — showing banner for job #$jobCardNumber")
                showPersistentBanner(level, "Job #$jobCardNumber", jobCardNumber, description, operator)
            }
        }
    }

    private fun canScheduleExactAlarms(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            return alarmManager.canScheduleExactAlarms()
        }
        return true // Always allowed below Android 12
    }

    private fun scheduleFullScreenAlarm(
        jobCardNumber: String,
        description: String,
        level: String,
        priority: String = "5",
        createdBy: String = "Unknown",
        location: String = "Not specified"
    ) {
        val triggerTime = System.currentTimeMillis() + 3_000

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

        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        try {
            val showIntent = PendingIntent.getBroadcast(
                this,
                jobCardNumber.hashCode() + 1,
                alarmIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.setAlarmClock(
                AlarmManager.AlarmClockInfo(triggerTime, showIntent),
                pendingIntent
            )
            Log.d(TAG, "✅ Full-screen alarm scheduled for job #$jobCardNumber")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to schedule alarm: ${e.message}")
        }
    }

    private fun showPersistentBanner(
        level: String,
        title: String,
        jobCardNumber: String,
        description: String,
        operator: String = "Unknown"
    ) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "persistent_banner_channel"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Persistent Job Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                this.description = "Job notifications that stay until dismissed"
                enableLights(true)
                lightColor = if (level == "full-loud") Color.RED else Color.parseColor("#FF9800")
                enableVibration(true)
                setBypassDnd(true)
            }
            notificationManager.createNotificationChannel(channel)
        }

        val viewIntent = Intent(this, MainActivity::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("action", "view_job")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val viewPendingIntent = PendingIntent.getActivity(
            this, 0, viewIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val assignIntent = Intent(this, MainActivity::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("action", "assign_self")
            putExtra("operator", operator)
        }
        val assignPendingIntent = PendingIntent.getActivity(
            this, 1, assignIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val busyIntent = Intent(this, MainActivity::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("action", "busy")
            putExtra("operator", operator)
        }
        val busyPendingIntent = PendingIntent.getActivity(
            this, 2, busyIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val dismissIntent = Intent(this, MainActivity::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("action", "dismiss")
            putExtra("operator", operator)
        }
        val dismissPendingIntent = PendingIntent.getActivity(
            this, 3, dismissIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(description)
            .setStyle(NotificationCompat.BigTextStyle().bigText(description))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setContentIntent(viewPendingIntent)
            .setOngoing(true)
            .setAutoCancel(false)
            .setColor(if (level == "full-loud") Color.RED else Color.parseColor("#FF9800"))
            .addAction(0, "Assign Self", assignPendingIntent)
            .addAction(0, "Busy", busyPendingIntent)
            .addAction(0, "Dismiss", dismissPendingIntent)
            .build()

        notificationManager.notify(jobCardNumber.toIntOrNull() ?: 9999, notification)
        Log.d(TAG, "✅ Persistent banner shown for job #$jobCardNumber")
    }

    companion object {
        private const val TAG = "FCM_DEBUG"
    }
}
