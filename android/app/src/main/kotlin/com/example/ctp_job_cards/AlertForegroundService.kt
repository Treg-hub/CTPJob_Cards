package com.example.ctp_job_cards

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
 * AlertForegroundService v2 - More reliable urgent alarm for P5 full-loud notifications
 * 
 * Changes from v1:
 * - Uses setExactAndAllowWhileIdle instead of setAlarmClock (more reliable on Android 14+)
 * - Uses BroadcastReceiver (AlarmReceiver) instead of direct Activity PendingIntent
 * - Better logging and slightly longer delay
 * - Prevents premature stopSelf that could kill the alarm
 */
class AlertForegroundService : Service() {
    private val CHANNEL_ID = "urgent_alert_channel"
    private val NOTIFICATION_ID = 1001
    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate() {
        super.onCreate()
        Log.d("AlertForegroundService", "🚀 Service onCreate called (v2)")
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d("AlertForegroundService", "Service started (v2)")
        val jobCardNumber = intent?.getStringExtra("jobCardNumber") ?: "Unknown"
        val description = intent?.getStringExtra("description") ?: "No description"

        // Start foreground service with notification (this is the fallback visible notification)
        val notification = createNotification(jobCardNumber, description)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        // Schedule the real full-screen alarm via AlarmReceiver (more reliable)
        scheduleFullScreenAlarm(jobCardNumber, description)

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
            .setContentTitle("Urgent Job Alert - Job #$jobCardNumber")
            .setContentText(description)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    /**
     * Schedule full-screen alarm using AlarmReceiver (more reliable on Android 14+ / Huawei)
     */
    private fun scheduleFullScreenAlarm(jobCardNumber: String, description: String) {
        Log.d("AlertForegroundService", "🚀 Scheduling full-screen alarm for job #$jobCardNumber (v2)")

        val alarmManager = getSystemService(ALARM_SERVICE) as AlarmManager

        // Check exact alarm permission (Android 12+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (!alarmManager.canScheduleExactAlarms()) {
                Log.e("AlertForegroundService", "❌ Cannot schedule exact alarms - permission denied!")
                stopSelf()
                return
            }
            Log.d("AlertForegroundService", "✅ Exact alarm permission granted")
        }

        // Use a slightly longer delay (8 seconds) to give the system time
        val triggerTime = System.currentTimeMillis() + 8000

        // Intent that goes to AlarmReceiver (BroadcastReceiver)
        val alarmIntent = Intent(this, AlarmReceiver::class.java).apply {
            putExtra("jobCardNumber", jobCardNumber)
            putExtra("description", description)
        }

        val alarmPendingIntent = PendingIntent.getBroadcast(
            this,
            jobCardNumber.hashCode(), // unique request code per job
            alarmIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        try {
            // Use setExactAndAllowWhileIdle - this is more reliable than setAlarmClock
            // when the app is killed/backgrounded on Android 14+
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerTime,
                alarmPendingIntent
            )
            Log.d("AlertForegroundService", "✅ Alarm scheduled successfully via AlarmReceiver (8s delay)")
        } catch (e: Exception) {
            Log.e("AlertForegroundService", "❌ Failed to schedule alarm: ${e.message}")
        }

        // Do NOT stop the service immediately - let it live a bit longer
        // The receiver will handle launching the full-screen activity
        handler.postDelayed({
            Log.d("AlertForegroundService", "Service stopping after alarm scheduled")
            stopSelf()
        }, 15000) // 15 seconds
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d("AlertForegroundService", "Service destroyed (v2)")
    }
}