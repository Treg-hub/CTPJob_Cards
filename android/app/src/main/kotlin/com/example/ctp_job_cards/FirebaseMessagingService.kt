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
        Log.d("FCM_DEBUG", "📩 FCM received - Level: ${remoteMessage.data["notificationLevel"]}")

        val level = remoteMessage.data["notificationLevel"] ?: "normal"
        val jobCardNumber = remoteMessage.data["jobCardNumber"] ?: "Unknown"
        val description = remoteMessage.data["description"] ?: remoteMessage.data["body"] ?: "Job update"

        // Always show a notification as fallback
        showNotification(level, "Job #$jobCardNumber", jobCardNumber, description)

        // P4 and P5 → Always try full-screen alarm
        if (level == "full-loud" || level == "medium-high") {
            Log.d("FCM_DEBUG", "🚨 P4/P5 job #$jobCardNumber - Scheduling full-screen alarm")
            scheduleFullScreenAlarm(jobCardNumber, description, level)
        }
    }

    private fun scheduleFullScreenAlarm(jobCardNumber: String, description: String, level: String) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
            Log.e("FCM_DEBUG", "❌ Cannot schedule exact alarms - permission missing")
            return
        }

        val triggerTime = System.currentTimeMillis() + 3000 // 3 second delay

        val alarmIntent = Intent(this, AlarmReceiver::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("description", description)
            putExtra("level", level)
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

            Log.d("FCM_DEBUG", "✅ Full-screen alarm scheduled for job #$jobCardNumber (Level: $level)")
        } catch (e: Exception) {
            Log.e("FCM_DEBUG", "❌ Failed to schedule alarm: ${e.message}")
        }
    }

    private fun showNotification(level: String, title: String, jobCardNumber: String, description: String) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = if (level == "full-loud" || level == "medium-high") "urgent_alert_channel" else "normal_channel"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                if (level == "full-loud" || level == "medium-high") "Urgent Job Alerts" else "Normal Job Notifications",
                if (level == "full-loud" || level == "medium-high") NotificationManager.IMPORTANCE_HIGH else NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                this.description = "Job notifications"
                enableLights(true)
                lightColor = if (level == "full-loud") Color.RED else Color.YELLOW
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(channel)
        }

        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("action", "view_job")
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(description)
            .setStyle(NotificationCompat.BigTextStyle().bigText(description))
            .setPriority(if (level == "full-loud" || level == "medium-high") NotificationCompat.PRIORITY_HIGH else NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)

        if (level == "full-loud") {
            builder.setColor(Color.RED)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
        } else if (level == "medium-high") {
            builder.setColor(Color.parseColor("#FF9800"))
        }

        notificationManager.notify(jobCardNumber.hashCode(), builder.build())
    }
}