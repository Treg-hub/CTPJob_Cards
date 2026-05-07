package com.treg.ctpjobcards

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent

class GeofenceBroadcastReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val geofencingEvent = GeofencingEvent.fromIntent(intent) ?: return
        if (geofencingEvent.hasError()) return

        val transition = geofencingEvent.geofenceTransition
        val isEntering = transition == Geofence.GEOFENCE_TRANSITION_ENTER

        // Send event to Flutter
        val channel = MainActivity.geofenceChannel
        channel?.invokeMethod("onGeofenceEvent", mapOf("entering" to isEntering))
    }
}