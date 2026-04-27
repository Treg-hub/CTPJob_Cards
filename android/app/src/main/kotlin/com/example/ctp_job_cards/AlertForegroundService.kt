package com.example.ctp_job_cards

import android.app.*
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

class AlertForegroundService : Service() {

    private val CHANNEL_ID = "urgent_alert_channel"
    private val NOTIFICATION_ID = 1001
    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate() {
        super.onCreate()
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
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = descriptionText
                setSound(null, null) // No sound for this channel
                enableVibration(false)
            }
            val notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(jobCardNumber: String, description: String): Notification {
        val intent = Intent(this, FullScreenJobAlertActivity::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("description", description)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }

        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("Urgent Job Alert")
            .setContentText("Job #$jobCardNumber: $description")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setFullScreenIntent(pendingIntent, true)
            .setAutoCancel(true)
            .build()
    }

    private fun checkAndScheduleAlert(jobCardNumber: String, description: String) {
        val alarmManager = getSystemService(ALARM_SERVICE) as AlarmManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (!alarmManager.canScheduleExactAlarms()) {
                Log.w("AlertForegroundService", "Cannot schedule exact alarms - opening settings")
                // Open settings to request permission
                val intent = Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                stopSelf()
                return
            }
        }

        // Schedule the full-screen activity to start after 2 seconds
        val intent = Intent(this, FullScreenJobAlertActivity::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("description", description)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }

        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val triggerTime = System.currentTimeMillis() + 2000 // 2 seconds from now

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerTime, pendingIntent)
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerTime, pendingIntent)
        }

        // Stop the service after scheduling
        handler.postDelayed({
            stopSelf()
        }, 3000) // Stop after 3 seconds
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d("AlertForegroundService", "Service destroyed")
    }
}