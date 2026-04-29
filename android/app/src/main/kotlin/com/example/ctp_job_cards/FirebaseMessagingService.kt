package com.example.ctp_job_cards

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class FirebaseMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        Log.d("FirebaseMessagingService", "📩 FCM received - Data: ${remoteMessage.data}")

        val level = remoteMessage.data["notificationLevel"] ?: "normal"
        val jobCardNumber = remoteMessage.data["jobCardNumber"] ?: "Unknown"
        val priority = remoteMessage.data["priority"] ?: "1"
        val createdBy = remoteMessage.data["createdBy"] ?: "Unknown"
        val description = remoteMessage.data["description"]
            ?: remoteMessage.data["body"]
            ?: remoteMessage.data["message"]
            ?: "New job alert"

        val title = "Job #$jobCardNumber - Priority $priority - $createdBy"

        // Always show a notification (fallback)
        showNotification(level, title, jobCardNumber, description)

        // For full-loud ONLY: start the foreground service (this is what triggers the real alarm)
        if (level == "full-loud") {
            Log.d("FirebaseMessagingService", "🚨 Starting AlertForegroundService for P5 job #$jobCardNumber")
            val serviceIntent = Intent(this, AlertForegroundService::class.java).apply {
                putExtra("jobCardNumber", jobCardNumber)
                putExtra("description", description)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
        }
    }

    private fun showNotification(level: String, title: String, jobCardNumber: String, description: String) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "urgent_alert_channel"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Urgent Job Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Channel for urgent job notifications"
                enableLights(true)
                lightColor = if (level == "full-loud") Color.RED else Color.YELLOW
                enableVibration(true)
                vibrationPattern = if (level == "full-loud")
                    longArrayOf(0, 1000, 500, 1000, 500, 1000)
                else
                    longArrayOf(0, 500, 300, 500)
            }
            notificationManager.createNotificationChannel(channel)
        }

        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
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
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)

        if (level == "full-loud") {
            builder.setColor(Color.RED)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
        }

        notificationManager.notify(jobCardNumber.hashCode(), builder.build())
    }
}