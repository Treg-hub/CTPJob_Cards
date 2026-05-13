package com.example.ctp_job_cards

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices

object GeofenceHelper {
    private const val TAG = "GeofenceHelper"
    private const val GEOFENCE_REQUEST_ID = "company_geofence_"

    // SharedPreferences keys used by BootReceiver to re-register after reboot.
    private const val PREFS_NAME = "geofence_prefs"
    private const val KEY_CLOCK_NO = "clockNo"
    private const val KEY_LAT = "lat"
    private const val KEY_LNG = "lng"
    private const val KEY_RADIUS = "radius"

    private lateinit var geofencingClient: GeofencingClient
    private lateinit var geofencePendingIntent: PendingIntent

    fun initialize(context: Context) {
        geofencingClient = LocationServices.getGeofencingClient(context)
        geofencePendingIntent = createGeofencePendingIntent(context)
    }

    private fun createGeofencePendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, GeofenceReceiver::class.java)
        return PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )
    }

    fun registerGeofence(
        context: Context,
        clockNo: String,
        latitude: Double,
        longitude: Double,
        radius: Float
    ) {
        if (!::geofencingClient.isInitialized) {
            initialize(context)
        }

        val geofence = Geofence.Builder()
            .setRequestId("$GEOFENCE_REQUEST_ID$clockNo")
            .setCircularRegion(latitude, longitude, radius)
            .setExpirationDuration(Geofence.NEVER_EXPIRE)
            .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT)
            // Increase responsiveness: notify when 70 % of the radius has been traversed.
            .setLoiteringDelay(30_000)
            .build()

        val geofencingRequest = GeofencingRequest.Builder()
            // INITIAL_TRIGGER_ENTER fires immediately if the device is already inside the fence.
            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
            .addGeofence(geofence)
            .build()

        geofencingClient.addGeofences(geofencingRequest, geofencePendingIntent)
            .addOnSuccessListener {
                Log.d(TAG, "✅ Geofence registered — clockNo=$clockNo lat=$latitude lng=$longitude radius=$radius")
                // Persist params so BootReceiver can re-register after reboot without Firestore.
                persistGeofenceParams(context, clockNo, latitude, longitude, radius)
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "❌ Geofence registration failed: ${e.message}")
            }
    }

    fun stopGeofence(context: Context) {
        if (!::geofencingClient.isInitialized) {
            initialize(context)
        }
        geofencingClient.removeGeofences(geofencePendingIntent)
            .addOnSuccessListener {
                Log.d(TAG, "✅ All geofences removed")
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "❌ Failed to remove geofences: ${e.message}")
            }
    }

    fun removeGeofence(clockNo: String) {
        if (!::geofencingClient.isInitialized) return
        geofencingClient.removeGeofences(listOf("$GEOFENCE_REQUEST_ID$clockNo"))
            .addOnSuccessListener { Log.d(TAG, "✅ Geofence removed for $clockNo") }
            .addOnFailureListener { e -> Log.e(TAG, "❌ Remove failed: ${e.message}") }
    }

    // Saves geofence parameters to SharedPreferences so BootReceiver can re-register
    // without needing a Firestore round-trip during cold boot.
    private fun persistGeofenceParams(
        context: Context,
        clockNo: String,
        lat: Double,
        lng: Double,
        radius: Float
    ) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit().apply {
            putString(KEY_CLOCK_NO, clockNo)
            putFloat(KEY_LAT, lat.toFloat())
            putFloat(KEY_LNG, lng.toFloat())
            putFloat(KEY_RADIUS, radius)
            apply()
        }
    }

    // Called by BootReceiver to restore the last-known geofence configuration.
    fun reRegisterFromPrefs(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val clockNo = prefs.getString(KEY_CLOCK_NO, null) ?: return false
        val lat = prefs.getFloat(KEY_LAT, Float.MIN_VALUE).toDouble()
        val lng = prefs.getFloat(KEY_LNG, Float.MIN_VALUE).toDouble()
        val radius = prefs.getFloat(KEY_RADIUS, -1f)

        if (lat == Float.MIN_VALUE.toDouble() || radius == -1f) return false

        registerGeofence(context, clockNo, lat, lng, radius)
        Log.d(TAG, "✅ Geofence re-registered from prefs after boot — clockNo=$clockNo")
        return true
    }
}
