package com.example.ctp_job_cards

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import com.google.android.gms.tasks.Tasks
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FirebaseFirestore
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class GeofenceReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        // goAsync() extends the BroadcastReceiver lifetime from ~10 s to ~30 s so that
        // async Firestore writes can complete before the process is eligible for killing.
        val pendingResult = goAsync()

        try {
            val geofencingEvent = GeofencingEvent.fromIntent(intent)
            if (geofencingEvent == null || geofencingEvent.hasError()) {
                Log.e(TAG, "Geofencing event error code: ${geofencingEvent?.errorCode}")
                pendingResult.finish()
                return
            }

            val transition = geofencingEvent.geofenceTransition
            if (transition != Geofence.GEOFENCE_TRANSITION_ENTER &&
                transition != Geofence.GEOFENCE_TRANSITION_EXIT) {
                pendingResult.finish()
                return
            }

            val isEntering = transition == Geofence.GEOFENCE_TRANSITION_ENTER
            val eventType = if (isEntering) "enter" else "exit"

            val relevantGeofence = geofencingEvent.triggeringGeofences
                ?.firstOrNull { it.requestId.startsWith(GEOFENCE_PREFIX) }

            if (relevantGeofence == null) {
                pendingResult.finish()
                return
            }

            val clockNo = relevantGeofence.requestId.removePrefix(GEOFENCE_PREFIX)
            Log.d(TAG, "Geofence $eventType for clockNo=$clockNo")

            val db = FirebaseFirestore.getInstance()

            // Update the isOnSite flag on the employee document.
            val updateTask = db.collection("employees")
                .document(clockNo)
                .update("isOnSite", isEntering)

            // Append an audit entry so the source (native_geofence) is traceable.
            val logTask = db.collection("geofence_logs").add(
                mapOf(
                    "clockNo" to clockNo,
                    "event" to eventType,
                    "source" to "native_geofence",
                    "timestamp" to Timestamp.now()
                )
            )

            // Wait for both writes before releasing the receiver process.
            Tasks.whenAll(updateTask, logTask).addOnCompleteListener { task ->
                if (task.isSuccessful) {
                    Log.d(TAG, "✅ Firestore updated — clockNo=$clockNo isOnSite=$isEntering")
                } else {
                    Log.e(TAG, "❌ Firestore write failed: ${task.exception?.message}")
                }
                // Notify Dart only when the Flutter engine is already running (foreground).
                // This drives any in-app UI refresh; Firestore is already updated above.
                notifyDart(isEntering, clockNo)
                pendingResult.finish()
            }

        } catch (e: Exception) {
            Log.e(TAG, "Exception in onReceive: ${e.message}")
            pendingResult.finish()
        }
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
            // Engine not running — normal when the app is backgrounded.
            Log.d(TAG, "Flutter engine not available for Dart notification")
        }
    }

    companion object {
        private const val TAG = "GeofenceReceiver"
        const val GEOFENCE_PREFIX = "company_geofence_"
        const val FLUTTER_ENGINE_ID = "main_engine"
        const val GEOFENCE_CHANNEL = "ctp/geofence"
    }
}
