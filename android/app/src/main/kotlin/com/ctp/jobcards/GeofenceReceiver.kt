package com.ctp.jobcards

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
import com.google.android.gms.tasks.Tasks
import com.google.firebase.FirebaseApp
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FirebaseFirestore
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit

class GeofenceReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        // goAsync() keeps the process alive (and the wake lock held) while we do
        // async work on a background thread. finish() is always called in finally.
        val pendingResult = goAsync()

        Thread {
            try {
                val geofencingEvent = GeofencingEvent.fromIntent(intent)
                if (geofencingEvent == null || geofencingEvent.hasError()) {
                    Log.e(TAG, "Geofencing event error: ${geofencingEvent?.errorCode}")
                    return@Thread
                }

                val transition = geofencingEvent.geofenceTransition
                if (transition != Geofence.GEOFENCE_TRANSITION_ENTER &&
                    transition != Geofence.GEOFENCE_TRANSITION_EXIT) {
                    return@Thread
                }

                val isEntering = transition == Geofence.GEOFENCE_TRANSITION_ENTER
                val eventType = if (isEntering) "enter" else "exit"

                val relevantGeofence = geofencingEvent.triggeringGeofences
                    ?.firstOrNull { it.requestId.startsWith(GEOFENCE_PREFIX) }
                    ?: return@Thread

                val clockNo = relevantGeofence.requestId.removePrefix(GEOFENCE_PREFIX)
                Log.d(TAG, "Geofence $eventType for clockNo=$clockNo")

                // Ensure Firebase is initialised — FirebaseInitProvider normally handles this
                // before any receiver fires, but an explicit guard prevents silent failures
                // when the process is cold-started solely to handle this broadcast.
                if (FirebaseApp.getApps(context).isEmpty()) {
                    FirebaseApp.initializeApp(context)
                }

                val db = FirebaseFirestore.getInstance()

                val updateTask = db.collection("employees")
                    .document(clockNo)
                    .update("isOnSite", isEntering)

                val logTask = db.collection("geofence_logs").add(
                    mapOf(
                        "clockNo"   to clockNo,
                        "event"     to eventType,
                        "source"    to "native_geofence",
                        "timestamp" to Timestamp.now()
                    )
                )

                // Block this background thread for up to 25 s waiting for both writes.
                // This is safe here (not the main thread) and more reliable than posting
                // a callback back onto the main looper of a freshly-woken process.
                try {
                    Tasks.await(Tasks.whenAll(updateTask, logTask), 25, TimeUnit.SECONDS)
                    Log.d(TAG, "✅ Firestore updated — clockNo=$clockNo isOnSite=$isEntering")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Firestore write failed: ${e.message}")
                }

                // Notify the Dart side only when the Flutter engine is running (foreground).
                notifyDart(isEntering, clockNo)

                // Always show a local notification so the user is informed even when the
                // app is killed and the Dart notification path is unavailable.
                sendLocalNotification(context, isEntering)

            } catch (e: Exception) {
                Log.e(TAG, "Exception in GeofenceReceiver: ${e.message}")
            } finally {
                pendingResult.finish()
            }
        }.start()
    }

    private fun notifyDart(isEntering: Boolean, clockNo: String) {
        try {
            val engine = FlutterEngineCache.getInstance().get(FLUTTER_ENGINE_ID)
            engine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, GEOFENCE_CHANNEL).invokeMethod(
                    "onGeofenceEvent",
                    mapOf("entering" to isEntering, "clockNo" to clockNo)
                )
            }
        } catch (e: Exception) {
            // Engine not running — normal when app is backgrounded or killed.
            Log.d(TAG, "Flutter engine not available for Dart notification")
        }
    }

    private fun sendLocalNotification(context: Context, isEntering: Boolean) {
        try {
            val notificationManager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    NOTIF_CHANNEL_ID,
                    "Site Presence",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply { description = "Notifies when you arrive at or leave the work site" }
                notificationManager.createNotificationChannel(channel)
            }

            val notification = NotificationCompat.Builder(context, NOTIF_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(if (isEntering) "Arrived On-Site" else "Left Site Area")
                .setContentText(
                    if (isEntering) "You are now within the company radius."
                    else "You have left the site area."
                )
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setAutoCancel(true)
                .build()

            notificationManager.notify(NOTIF_ID, notification)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send local notification: ${e.message}")
        }
    }

    companion object {
        private const val TAG              = "GeofenceReceiver"
        const val  GEOFENCE_PREFIX         = "company_geofence_"
        const val  FLUTTER_ENGINE_ID       = "main_engine"
        const val  GEOFENCE_CHANNEL        = "ctp/geofence"
        private const val NOTIF_CHANNEL_ID = "geofence_status_channel"
        private const val NOTIF_ID         = 2001
    }
}
