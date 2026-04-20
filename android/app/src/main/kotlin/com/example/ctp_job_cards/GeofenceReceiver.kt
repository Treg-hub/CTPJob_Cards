package com.example.ctp_job_cards

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import com.google.firebase.firestore.FirebaseFirestore

class GeofenceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val geofencingEvent = GeofencingEvent.fromIntent(intent)
        if (geofencingEvent?.hasError() == true) {
            return
        }

        val geofenceTransition = geofencingEvent?.geofenceTransition
        if (geofenceTransition == Geofence.GEOFENCE_TRANSITION_ENTER || geofenceTransition == Geofence.GEOFENCE_TRANSITION_EXIT) {
            val triggeringGeofences = geofencingEvent?.triggeringGeofences
            triggeringGeofences?.forEach { geofence ->
                val requestId = geofence.requestId
                if (requestId.startsWith("company_geofence_")) {
                    val clockNo = requestId.removePrefix("company_geofence_")
                    val entering = geofenceTransition == Geofence.GEOFENCE_TRANSITION_ENTER

                    // Update Firestore
                    val db = FirebaseFirestore.getInstance()
                    db.collection("employees").document(clockNo)
                        .update("isOnSite", entering)
                        .addOnSuccessListener {
                            // Send local notification
                            sendNotification(context, entering)
                        }
                        .addOnFailureListener { e: Exception ->
                            // Still send notification even if Firestore fails
                            sendNotification(context, entering)
                        }
                }
            }
        }
    }

    private fun sendNotification(context: Context, entering: Boolean) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "onsite_channel",
                "On-Site Notifications",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications for entering/exiting company site"
            }
            notificationManager.createNotificationChannel(channel)
        }

        val title = if (entering) "✅ On-Site Detected" else "📍 Left Site Area"
        val body = if (entering) "Within 2km of CTP. Ready for jobs." else "Off-site. Filtering updated."

        val notification = NotificationCompat.Builder(context, "onsite_channel")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()

        notificationManager.notify(System.currentTimeMillis().toInt(), notification)
    }
}