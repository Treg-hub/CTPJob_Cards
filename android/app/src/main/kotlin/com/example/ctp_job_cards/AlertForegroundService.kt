package com.example.ctp_job_cards

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

class AlertForegroundService : Service() {

    private val CHANNEL_ID = "urgent_alert_channel"
    private val NOTIFICATION_ID = 1001
    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate() {
        super.onCreate()
        Log.d("AlertForegroundService", "🚀 Service onCreate called!")
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d("AlertForegroundService", "Service started")

        val jobCardNumber = intent?.getStringExtra("jobCardNumber") ?: "Unknown"
        val description = intent?.getStringExtra("description") ?: "No description"

        // Start foreground service with notification
        val notification = createNotification(jobCardNumber, description)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        // Check exact alarm permission and schedule full-screen activity
        checkAndScheduleAlert(jobCardNumber, description)

        return START_NOT_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Urgent Job Alerts"
            val descriptionText = "Channel for urgent job card notifications"
            val importance = NotificationManager.IMPORTANCE_MAX // MAX for full-screen intents
            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = descriptionText
                setSound(null, null) // No sound for this channel
                enableVibration(false)
            }
            val notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
            Log.d("AlertForegroundService", "✅ Notification channel created with IMPORTANCE_MAX")
        }
    }

    private fun createNotification(jobCardNumber: String, description: String): Notification {
        val intent = Intent(this, FullScreenJobAlertActivity::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("description", description)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            Log.d("AlertForegroundService", "🚨 Alarm intent created for job #$jobCardNumber")
        }

        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        Log.d("AlertForegroundService", "🚨 PendingIntent created")

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("Urgent Job Alert")
            .setContentText("Job #$jobCardNumber: $description")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .build()
    }

    private fun checkAndScheduleAlert(jobCardNumber: String, description: String) {
        Log.d("AlertForegroundService", "🚀 Starting to schedule alert for job #$jobCardNumber")

        val alarmManager = getSystemService(ALARM_SERVICE) as AlarmManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (!alarmManager.canScheduleExactAlarms()) {
                Log.e("AlertForegroundService", "❌ Cannot schedule exact alarms - permission denied!")
                stopSelf()
                return
            }
            Log.d("AlertForegroundService", "✅ Exact alarm permission granted")
        }

        val triggerTime = System.currentTimeMillis() + 2000

        val fullScreenIntent = Intent(this, FullScreenJobAlertActivity::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("description", description)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }

        val options = ActivityOptions.makeBasic()
        if (Build.VERSION.SDK_INT >= 34) {
            options.setPendingIntentBackgroundActivityStartMode(
                ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
            )
        }

        val fullScreenPendingIntent = PendingIntent.getActivity(
            this, 0, fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            options.toBundle()
        )

        val showIntent = PendingIntent.getActivity(
            this, 1, fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        try {
            val alarmInfo = AlarmManager.AlarmClockInfo(triggerTime, showIntent)
            alarmManager.setAlarmClock(alarmInfo, fullScreenPendingIntent)
            Log.d("AlertForegroundService", "✅ AlarmClock scheduled successfully!")
        } catch (e: Exception) {
            Log.e("AlertForegroundService", "❌ Failed to schedule alarm: ${e.message}")
        }

        handler.postDelayed({ stopSelf() }, 3000)
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d("AlertForegroundService", "Service destroyed")
    }
}