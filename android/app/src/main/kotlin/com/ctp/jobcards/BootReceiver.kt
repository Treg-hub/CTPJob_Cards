package com.ctp.jobcards

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Re-registers the geofence after a device reboot or app self-update.
 * GMS clears all registered geofences on reboot, so this is required for reliable detection.
 *
 * The geofence parameters (lat/lng/radius/clockNo) were saved to SharedPreferences by
 * GeofenceHelper.registerGeofence(), so no network round-trip is needed here.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != "android.intent.action.MY_PACKAGE_REPLACED") {
            return
        }

        Log.d(TAG, "Boot/update event received — attempting geofence re-registration")

        val reRegistered = GeofenceHelper.reRegisterFromPrefs(context.applicationContext)
        if (!reRegistered) {
            Log.w(TAG, "No saved geofence params found — skipping (user may not be logged in yet)")
        }
    }

    companion object {
        private const val TAG = "BootReceiver"
    }
}
