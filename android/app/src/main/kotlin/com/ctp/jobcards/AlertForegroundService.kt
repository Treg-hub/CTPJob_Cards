package com.ctp.jobcards

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * AlertForegroundService v3 - With action buttons + persistent notification
 */
class AlertForegroundService : Service() {
    private val CHANNEL_ID = "urgent_alert_channel"
    private val NOTIFICATION_ID = 1001
    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate() {
        super.onCreate()
        Log.d("AlertForegroundService", "🚀 Service onCreate called (v3)")
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d("AlertForegroundService", "Service started (v3)")
        val jobCardNumber = intent?.getStringExtra("jobCardNumber") ?: "Unknown"
        val description = intent?.getStringExtra("description") ?: "No description"
        val priority = intent?.getStringExtra("priority") ?: "5"

        // Start foreground service with notification (persistent + with action buttons)
        val notification = createNotification(jobCardNumber, description, priority)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        // Schedule the real full-screen alarm via AlarmReceiver (more reliable)
        scheduleFullScreenAlarm(jobCardNumber, description, intent)

        return START_NOT_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Urgent Job Alerts"
            val descriptionText = "Channel for urgent job card notifications (P5)"
            val importance = NotificationManager.IMPORTANCE_MAX
            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = descriptionText
                setSound(null, null)
                enableVibration(false)
            }
            val notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
            Log.d("AlertForegroundService", "✅ Notification channel created with IMPORTANCE_MAX")
        }
    }

    private fun createNotification(jobCardNumber: String, description: String, priority: String): Notification {
        val intent = Intent(this, FullScreenJobAlertActivity::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("description", description)
            putExtra("priority", priority)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // === ACTION: Assign Self ===
        val assignIntent = Intent(this, FullScreenJobAlertActivity::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("action", "assign_self")
        }
        val assignPendingIntent = PendingIntent.getActivity(
            this, 1, assignIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // === ACTION: Dismiss ===
        val dismissIntent = Intent(this, FullScreenJobAlertActivity::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("action", "dismiss")
        }
        val dismissPendingIntent = PendingIntent.getActivity(
            this, 3, dismissIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("Urgent Job Alert - Job #$jobCardNumber")
            .setContentText(description)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setOngoing(true)                    // ← Keep notification visible
            .setAutoCancel(false)                // ← Do not auto-dismiss
            .setContentIntent(pendingIntent)
            .addAction(android.R.drawable.ic_menu_add, "Assign Self", assignPendingIntent)
            .addAction(android.R.drawable.ic_menu_delete, "Dismiss", dismissPendingIntent)

        // Only add "I'm Busy" button for P5 (as per your requirement)
        if (priority == "5") {
            val busyIntent = Intent(this, FullScreenJobAlertActivity::class.java).apply {
                putExtra("jobCardNumber", jobCardNumber)
                putExtra("action", "busy")
            }
            val busyPendingIntent = PendingIntent.getActivity(
                this, 2, busyIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "I'm Busy", busyPendingIntent)
        }

        return builder.build()
    }

    private fun scheduleFullScreenAlarm(jobCardNumber: String, description: String, sourceIntent: Intent?) {
        Log.d("AlertForegroundService", "🚀 Scheduling full-screen alarm for job #$jobCardNumber")

        val alarmManager = getSystemService(ALARM_SERVICE) as AlarmManager

        // Pass all job details so FullScreenJobAlertActivity can display them correctly.
        val alarmIntent = Intent(this, AlarmReceiver::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("description", description)
            // These extras were previously missing, causing the full-screen alert to always
            // show priority "5", createdBy "Unknown", and location "Not specified".
            putExtra("level", sourceIntent?.getStringExtra("level") ?: "full-loud")
            putExtra("priority", sourceIntent?.getStringExtra("priority") ?: "5")
            putExtra("createdBy", sourceIntent?.getStringExtra("createdBy") ?: "Unknown")
            putExtra("location", sourceIntent?.getStringExtra("location") ?: "Not specified")
        }

        val pendingIntent = PendingIntent.getBroadcast(
            this, 0, alarmIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val triggerTime = System.currentTimeMillis() + 8000 // 8 seconds delay

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (alarmManager.canScheduleExactAlarms()) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerTime,
                    pendingIntent
                )
            } else {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerTime,
                    pendingIntent
                )
            }
        } else {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerTime,
                pendingIntent
            )
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
