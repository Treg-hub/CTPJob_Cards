package com.example.ctp_job_cards

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.AudioAttributesCompat
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class FirebaseMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        Log.d("FirebaseMessagingService", "📩 BACKGROUND FCM received")
        Log.d("FirebaseMessagingService", "Data keys: ${remoteMessage.data.keys.joinToString()}")

        val level = remoteMessage.data["notificationLevel"] ?: ""

        val jobCardNumber = remoteMessage.data["jobCardNumber"]
            ?: remoteMessage.data["jobcardnumber"]
            ?: remoteMessage.data["job_card_number"]
            ?: "Unknown"

        val description = remoteMessage.data["body"]
            ?: remoteMessage.data["description"]
            ?: remoteMessage.data["message"]
            ?: "New job alert"

        val title = remoteMessage.data["title"] ?: "New Job Assigned"

        if (level in listOf("full-loud", "medium-high", "normal")) {
            Log.d("FirebaseMessagingService", "🚨 BACKGROUND $level detected! Job: $jobCardNumber")
            showNotification(level, title, jobCardNumber, description)
        }
    }

    private fun showNotification(level: String, title: String, jobCardNumber: String, description: String) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        lateinit var channelId: String
        var priority: Int = NotificationCompat.PRIORITY_DEFAULT
        lateinit var soundUri: android.net.Uri
        lateinit var vibration: LongArray
        var lights: Int = Color.WHITE
        var category: String? = null
        var color: Int = Color.WHITE
        var fullScreen: Boolean = false
        var notificationId: Int = 1000
        var autoCancel: Boolean = true
        var audioAttributes: AudioAttributesCompat? = null

        when (level) {
            "full-loud" -> {
                channelId = "full_channel"
                priority = NotificationCompat.PRIORITY_MAX
                soundUri = Uri.parse("android.resource://${packageName}/raw/escalation_alert")
                vibration = longArrayOf(0, 1000, 500, 1000, 500, 1000)
                lights = Color.RED
                category = NotificationCompat.CATEGORY_CALL
                color = Color.RED
                fullScreen = true
                notificationId = 1001
                autoCancel = false
                audioAttributes = AudioAttributesCompat.Builder()
                    .setUsage(AudioAttributesCompat.USAGE_ALARM)
                    .setContentType(AudioAttributesCompat.CONTENT_TYPE_SONIFICATION)
                    .build()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val channel = NotificationChannel(
                        channelId,
                        "Full-Loud Job Notifications",
                        NotificationManager.IMPORTANCE_MAX
                    )
                    channel.description = "Maximum priority notifications for priority 5 jobs"
                    channel.setBypassDnd(true)
                    channel.enableLights(true)
                    channel.lightColor = Color.RED
                    channel.enableVibration(true)
                    channel.vibrationPattern = longArrayOf(0, 1000, 500, 1000, 500, 1000)
                    notificationManager.createNotificationChannel(channel)
                }
            }
            "medium-high" -> {
                channelId = "medium_high_channel"
                priority = NotificationCompat.PRIORITY_HIGH
                soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                vibration = longArrayOf(0, 500, 200, 500)
                lights = Color.YELLOW
                color = Color.YELLOW
                notificationId = 1002
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val channel = NotificationChannel(
                        channelId,
                        "Medium-High Job Notifications",
                        NotificationManager.IMPORTANCE_HIGH
                    )
                    channel.description = "High priority notifications for priority 4 jobs"
                    channel.enableLights(true)
                    channel.lightColor = Color.YELLOW
                    channel.enableVibration(true)
                    channel.vibrationPattern = longArrayOf(0, 500, 200, 500)
                    notificationManager.createNotificationChannel(channel)
                }
            }
            "normal" -> {
                channelId = "normal_channel"
                priority = NotificationCompat.PRIORITY_HIGH
                soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                vibration = longArrayOf(0, 250, 100, 250)
                lights = Color.BLUE
                color = Color.BLUE
                notificationId = 1003
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val channel = NotificationChannel(
                        channelId,
                        "Normal Job Notifications",
                        NotificationManager.IMPORTANCE_HIGH
                    )
                    channel.description = "Standard notifications for priority 1-3 jobs"
                    channel.enableLights(true)
                    channel.lightColor = Color.BLUE
                    channel.enableVibration(true)
                    channel.vibrationPattern = longArrayOf(0, 250, 100, 250)
                    notificationManager.createNotificationChannel(channel)
                }
            }
            else -> return // Should not happen
        }

        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText("Job #$jobCardNumber")
            .setStyle(NotificationCompat.BigTextStyle().bigText("Job #$jobCardNumber\n$description"))
            .setPriority(priority)
            .setColor(color)
            .setLights(lights, 500, 500)
            .setVibrate(vibration)
            .setAutoCancel(autoCancel)

        if (audioAttributes != null) {
            builder.setSound(soundUri, audioAttributes)
        } else {
            builder.setSound(soundUri)
        }

        if (category != null) {
            builder.setCategory(category)
        }

        if (fullScreen) {
            builder.setFullScreenIntent(pendingIntent, true)
        } else {
            builder.setContentIntent(pendingIntent)
        }

        notificationManager.notify(notificationId, builder.build())

        if (level == "full-loud") {
            val serviceIntent = Intent(this, AlertForegroundService::class.java).apply {
                putExtra("jobCardNumber", jobCardNumber)
                putExtra("description", description)
            }
            startForegroundService(serviceIntent)
        }
    }
}
