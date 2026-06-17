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
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
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
                val empRef = db.collection("employees").document(clockNo)

                // Transaction so we only write + log on a REAL transition. This keeps
                // lastOnSiteAt a true session start (so the admin 14h-stuck flag is
                // meaningful) and stops INITIAL_TRIGGER_ENTER / re-registration from
                // resetting it or double-logging. The write touches only the presence
                // fields, so it satisfies the Wave B own-presence carve-out rule.
                var didTransition = false
                try {
                    didTransition = Tasks.await(
                        db.runTransaction<Boolean> { txn ->
                            val prev = txn.get(empRef).getBoolean("isOnSite")
                            if (prev != null && prev == isEntering) return@runTransaction false
                            val update = hashMapOf<String, Any>(
                                "isOnSite" to isEntering,
                                "presenceSource" to "native_geofence",
                                "presenceUpdatedAt" to FieldValue.serverTimestamp()
                            )
                            if (isEntering) update["lastOnSiteAt"] = FieldValue.serverTimestamp()
                            else update["lastOffSiteAt"] = FieldValue.serverTimestamp()
                            txn.set(empRef, update, SetOptions.merge())
                            true
                        },
                        25, TimeUnit.SECONDS
                    )
                    Log.d(TAG, "✅ Presence txn — clockNo=$clockNo isOnSite=$isEntering transition=$didTransition")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Presence transaction failed: ${e.message}")
                }

                // Central audit log — only on a real transition (app_geofence).
                if (didTransition) {
                    try {
                        Tasks.await(
                            db.collection("app_geofence").add(
                                mapOf(
                                    "clockNo"   to clockNo,
                                    "eventType" to eventType,
                                    "source"    to "native_geofence",
                                    "isOnSite"  to isEntering,
                                    "timestamp" to Timestamp.now(),
                                    "createdAt" to Timestamp.now()
                                )
                            ),
                            25, TimeUnit.SECONDS
                        )
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ app_geofence log failed: ${e.message}")
                    }
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
