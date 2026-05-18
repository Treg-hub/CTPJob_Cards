package com.ctp.jobcards

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
                // P5: full-screen alarm. If exact alarms are unavailable, fall back to
                // a loud persistent banner so the technician still sees something.
                if (canScheduleExactAlarms()) {
                    Log.d(TAG, "🚨 P5 — scheduling full-screen alarm for job #$jobCardNumber")
                    scheduleFullScreenAlarm(jobCardNumber, description, level, priority, operator, location)
                } else {
                    Log.w(TAG, "⚠️ P5 — exact alarms unavailable, falling back to loud banner")
                    showLoudBanner(jobCardNumber, "🚨 Urgent Job #$jobCardNumber", description, operator)
                }
            }
            "medium-high" -> {
                // P4: persistent banner with custom sound, DND bypass, alarm volume.
                Log.d(TAG, "🔔 P4 — showing loud banner for job #$jobCardNumber")
                showLoudBanner(jobCardNumber, "Job #$jobCardNumber", description, operator)
            }
            "banner" -> {
                // P3: persistent banner with default sound (no custom sound, no DND bypass).
                Log.d(TAG, "🔔 P3 — showing standard banner for job #$jobCardNumber")
                showStandardBanner(jobCardNumber, "Job #$jobCardNumber", description, operator)
            }
            else -> {
                // P1-P2 ("normal" level): basic notification, no buttons, default sound,
                // tap to open job detail.
                Log.d(TAG, "🔔 Normal — showing basic notification for job #$jobCardNumber")
                showBasicNotification(jobCardNumber, "Job #$jobCardNumber", description)
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
        operator: String = "Unknown",
        location: String = "Not specified"
    ) {
        val triggerTime = System.currentTimeMillis() + 3_000

        val alarmIntent = Intent(this, AlarmReceiver::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("description", description)
            putExtra("level", level)
            putExtra("priority", priority)
            putExtra("operator", operator)
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

    // P4 + P5-fallback: persistent banner with custom alarm sound, DND bypass, alarm volume.
    private fun showLoudBanner(
        jobCardNumber: String,
        title: String,
        description: String,
        operator: String = "Unknown"
    ) {
        ensureLoudBannerChannel()
        showBannerInternal(
            channelId = LOUD_BANNER_CHANNEL,
            jobCardNumber = jobCardNumber,
            title = title,
            description = description,
            operator = operator,
            withButtons = true,
            accentColor = Color.RED
        )
    }

    // P3: persistent banner with default Android sound, DND respected, normal volume.
    private fun showStandardBanner(
        jobCardNumber: String,
        title: String,
        description: String,
        operator: String = "Unknown"
    ) {
        ensureStandardBannerChannel()
        showBannerInternal(
            channelId = STANDARD_BANNER_CHANNEL,
            jobCardNumber = jobCardNumber,
            title = title,
            description = description,
            operator = operator,
            withButtons = true,
            accentColor = Color.parseColor("#FF9800")
        )
    }

    // P1-P2: basic notification — no buttons, default sound, tap to open detail.
    private fun showBasicNotification(
        jobCardNumber: String,
        title: String,
        description: String
    ) {
        ensureBasicChannel()
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val viewPendingIntent = makeViewPendingIntent(jobCardNumber)

        val notification = NotificationCompat.Builder(this, BASIC_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(description)
            .setStyle(NotificationCompat.BigTextStyle().bigText(description))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(viewPendingIntent)
            .setAutoCancel(true)  // tap or swipe removes it — no action buttons to keep it alive
            .setColor(Color.parseColor("#2563A0"))
            .build()

        notificationManager.notify(jobCardNumber.toIntOrNull() ?: 9999, notification)
        Log.d(TAG, "✅ Basic notification shown for job #$jobCardNumber")
    }

    // ==================== Shared banner builder ====================
    private fun showBannerInternal(
        channelId: String,
        jobCardNumber: String,
        title: String,
        description: String,
        operator: String,
        withButtons: Boolean,
        accentColor: Int
    ) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val viewPendingIntent = makeViewPendingIntent(jobCardNumber)

        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(description)
            .setStyle(NotificationCompat.BigTextStyle().bigText(description))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setContentIntent(viewPendingIntent)
            .setOngoing(true)
            .setAutoCancel(false)
            .setColor(accentColor)

        if (withButtons) {
            builder.addAction(0, "Assign Self", makeActionPendingIntent(jobCardNumber, "assign_self", operator, 1))
            builder.addAction(0, "Busy", makeActionPendingIntent(jobCardNumber, "busy", operator, 2))
            builder.addAction(0, "Dismiss", makeActionPendingIntent(jobCardNumber, "dismiss", operator, 3))
        }

        notificationManager.notify(jobCardNumber.toIntOrNull() ?: 9999, builder.build())
        Log.d(TAG, "✅ Banner ($channelId) shown for job #$jobCardNumber")
    }

    private fun makeViewPendingIntent(jobCardNumber: String): PendingIntent {
        val viewIntent = Intent(this, MainActivity::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("action", "view_job")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            this, jobCardNumber.hashCode(), viewIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun makeActionPendingIntent(
        jobCardNumber: String,
        action: String,
        operator: String,
        requestCodeOffset: Int
    ): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("action", action)
            putExtra("operator", operator)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            this, jobCardNumber.hashCode() + requestCodeOffset, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    // ==================== Channel creators ====================
    private fun ensureBasicChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(BASIC_CHANNEL) != null) return
        val channel = NotificationChannel(
            BASIC_CHANNEL,
            "Standard Job Notifications",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "P1-P2 — basic notifications, default sound"
            enableLights(false)
            enableVibration(true)
            setBypassDnd(false)
        }
        nm.createNotificationChannel(channel)
    }

    private fun ensureStandardBannerChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(STANDARD_BANNER_CHANNEL) != null) return
        val channel = NotificationChannel(
            STANDARD_BANNER_CHANNEL,
            "Persistent Job Alerts (Standard)",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "P3 — persistent banner with default sound"
            enableLights(true)
            lightColor = Color.parseColor("#FF9800")
            enableVibration(true)
            setBypassDnd(false)
        }
        nm.createNotificationChannel(channel)
    }

    private fun ensureLoudBannerChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(LOUD_BANNER_CHANNEL) != null) return
        val soundUri = android.net.Uri.parse("android.resource://$packageName/${R.raw.escalation_alert}")
        val audioAttributes = android.media.AudioAttributes.Builder()
            .setUsage(android.media.AudioAttributes.USAGE_ALARM)
            .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val channel = NotificationChannel(
            LOUD_BANNER_CHANNEL,
            "Persistent Job Alerts (Urgent)",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "P4 — persistent banner with alarm sound, DND bypass"
            enableLights(true)
            lightColor = Color.RED
            enableVibration(true)
            setBypassDnd(true)
            setSound(soundUri, audioAttributes)
        }
        nm.createNotificationChannel(channel)
    }

    companion object {
        private const val TAG = "FCM_DEBUG"
        const val BASIC_CHANNEL = "basic_notification_channel"
        const val STANDARD_BANNER_CHANNEL = "banner_standard_channel"
        const val LOUD_BANNER_CHANNEL = "banner_loud_channel"
    }
}
