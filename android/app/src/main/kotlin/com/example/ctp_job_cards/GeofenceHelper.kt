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
            .build()

        val geofencingRequest = GeofencingRequest.Builder()
            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
            .addGeofence(geofence)
            .build()

        geofencingClient.addGeofences(geofencingRequest, geofencePendingIntent)
            .addOnSuccessListener {
                Log.d(TAG, "Geofence registered successfully for $clockNo")
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "Failed to register geofence: ${e.message}")
            }
    }

    fun removeGeofence(clockNo: String) {
        if (!::geofencingClient.isInitialized) return

        geofencingClient.removeGeofences(listOf("$GEOFENCE_REQUEST_ID$clockNo"))
            .addOnSuccessListener {
                Log.d(TAG, "Geofence removed for $clockNo")
            }
    }
}