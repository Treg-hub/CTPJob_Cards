package com.example.ctp_job_cards

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import com.google.firebase.firestore.FirebaseFirestore
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class GeofenceReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val geofencingEvent = GeofencingEvent.fromIntent(intent)
        if (geofencingEvent?.hasError() == true) {
            Log.e("GeofenceReceiver", "Error: ${geofencingEvent.errorCode}")
            return
        }

        val transition = geofencingEvent?.geofenceTransition
        if (transition != Geofence.GEOFENCE_TRANSITION_ENTER &&
            transition != Geofence.GEOFENCE_TRANSITION_EXIT) return

        val isEntering = transition == Geofence.GEOFENCE_TRANSITION_ENTER

        geofencingEvent?.triggeringGeofences?.forEach { geofence ->
            val requestId = geofence.requestId
            if (requestId.startsWith("company_geofence_")) {
                val clockNo = requestId.removePrefix("company_geofence_")

                Log.d("GeofenceReceiver", "Event: $clockNo, entering=$isEntering")

                // 1. Update Firestore
                updateFirestore(clockNo, isEntering)

                // 2. Log event to Firestore (for debugging)
                logGeofenceEvent(clockNo, isEntering)

                // 3. Send notification
                sendNotification(context, isEntering)

                // 4. Notify Dart
                notifyDart(isEntering, clockNo)
            }
        }
    }

    private fun updateFirestore(clockNo: String, isOnSite: Boolean) {
        FirebaseFirestore.getInstance()
            .collection("employees")
            .document(clockNo)
            .update("isOnSite", isOnSite)
    }

    private fun logGeofenceEvent(clockNo: String, isEntering: Boolean) {
        val data = hashMapOf(
            "clockNo" to clockNo,
            "event" to if (isEntering) "ENTER" else "EXIT",
            "timestamp" to com.google.firebase.Timestamp.now(),
            "source" to "GeofenceReceiver"
        )

        FirebaseFirestore.getInstance()
            .collection("geofence_logs")
            .add(data)
    }

    private fun sendNotification(context: Context, isEntering: Boolean) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "onsite_channel", "On-Site Notifications",
                NotificationManager.IMPORTANCE_HIGH
            )
            manager.createNotificationChannel(channel)
        }

        val title = if (isEntering) "✅ On-Site Detected" else "📍 Left Site Area"
        val body = if (isEntering) "You are now within the company radius." else "You have left the site area."

        val notification = NotificationCompat.Builder(context, "onsite_channel")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()

        manager.notify(System.currentTimeMillis().toInt(), notification)
    }

    private fun notifyDart(isEntering: Boolean, clockNo: String) {
        try {
            val engine = FlutterEngineCache.getInstance().get("main_engine")
            engine?.let {
                MethodChannel(it.dartExecutor.binaryMessenger, "ctp/geofence")
                    .invokeMethod("onGeofenceEvent", mapOf(
                        "entering" to isEntering,
                        "clockNo" to clockNo
                    ))
            }
        } catch (e: Exception) {
            Log.e("GeofenceReceiver", "Failed to notify Dart: $e")
        }
    }
}