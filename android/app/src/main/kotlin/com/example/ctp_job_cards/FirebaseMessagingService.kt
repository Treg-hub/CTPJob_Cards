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

        val priority = remoteMessage.data["priority"] ?: "1"
        val createdBy = remoteMessage.data["createdBy"] ?: "Unknown"
        val department = remoteMessage.data["department"] ?: ""
        val area = remoteMessage.data["area"] ?: ""
        val location = remoteMessage.data["location"] ?: ""
        val part = remoteMessage.data["part"] ?: ""

        val description = remoteMessage.data["body"]
            ?: remoteMessage.data["description"]
            ?: remoteMessage.data["message"]
            ?: "New job alert"

        val title = "Job #$jobCardNumber - Priority $priority - $createdBy"
        val subtext = "$department > $area > $location > $part"

        if (level in listOf("full-loud", "medium-high", "normal")) {
            Log.d("FirebaseMessagingService", "🚨 BACKGROUND $level detected! Job: $jobCardNumber")
            showNotification(level, title, jobCardNumber, description, subtext)
        }
    }

    private fun showNotification(level: String, title: String, jobCardNumber: String, description: String, subtext: String) {
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
        var ongoing: Boolean = false
        var visibility: Int = NotificationCompat.VISIBILITY_PRIVATE
        channelId = "full_channel"
        priority = NotificationCompat.PRIORITY_MAX
        soundUri = Uri.parse("android.resource://${packageName}/raw/escalation_alert")
        category = NotificationCompat.CATEGORY_ALARM
        fullScreen = true
        autoCancel = false
        ongoing = true
        visibility = NotificationCompat.VISIBILITY_PUBLIC

        when (level) {
            "full-loud" -> {
                vibration = longArrayOf(0, 1500, 500, 1500, 500, 1500, 500, 1500)
                lights = Color.RED
                color = Color.RED
                notificationId = 1001
            }
            "medium-high" -> {
                vibration = longArrayOf(0, 800, 300, 800, 300, 800)
                lights = Color.YELLOW
                color = Color.YELLOW
                notificationId = 1002
            }
            "normal" -> {
                vibration = longArrayOf(0, 250, 100, 250)
                lights = Color.BLUE
                color = Color.BLUE
                notificationId = 1003
            }
            else -> return // Should not happen
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Job Card Notifications",
                NotificationManager.IMPORTANCE_MAX
            )
            channel.description = "Persistent job card notifications"
            channel.setBypassDnd(true)
            channel.enableLights(true)
            channel.lightColor = Color.RED
            channel.enableVibration(true)
            channel.vibrationPattern = longArrayOf(0, 1000, 500, 1000)
            notificationManager.createNotificationChannel(channel)
        }

        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("action", "open_job_detail")
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val assignIntent = Intent(this, MainActivity::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("action", "assign_self")
        }
        val assignPendingIntent = PendingIntent.getActivity(
            this, 2, assignIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val fullScreenIntent = if (fullScreen) Intent(this, FullScreenJobAlertActivity::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("description", description)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        } else null
        val fullScreenPendingIntent = if (fullScreenIntent != null) PendingIntent.getActivity(
            this, 1, fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        ) else null

        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(description)
            .setStyle(NotificationCompat.BigTextStyle().bigText("$description\n$subtext"))
            .setPriority(priority)
            .setColor(color)
            .setLights(lights, 500, 500)
            .setVibrate(vibration)
            .setSound(soundUri)
            .setAutoCancel(autoCancel)
            .setOngoing(ongoing)
            .setVisibility(visibility)
            .setOnlyAlertOnce(false)

        if (ongoing) {
            builder.setDeleteIntent(null).setTimeoutAfter(0)
        }

        if (category != null) {
            builder.setCategory(category)
        }

        if (fullScreen && fullScreenPendingIntent != null) {
            builder.setFullScreenIntent(fullScreenPendingIntent, true)
        } else {
            builder.setContentIntent(pendingIntent)
        }

        builder.addAction(NotificationCompat.Action.Builder(0, "Assign Self", assignPendingIntent).build())

        notificationManager.notify(notificationId, builder.build())

        if (level in listOf("full-loud", "medium-high", "normal")) {
            val serviceIntent = Intent(this, AlertForegroundService::class.java).apply {
                putExtra("jobCardNumber", jobCardNumber)
                putExtra("description", description)
            }
            startForegroundService(serviceIntent)
        }
    }
}
