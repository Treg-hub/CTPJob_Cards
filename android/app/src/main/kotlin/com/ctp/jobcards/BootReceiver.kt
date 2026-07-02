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
 *
 * Also relaunches the app after boot/update when Kiosk Mode is enabled on this
 * device — otherwise a power cut would leave the kiosk tablet sitting unlocked
 * on the Android home screen until someone taps the app icon. Once the activity
 * is up, KioskLifecycleGuard (Flutter) re-enters Lock Task Mode.
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

        maybeRelaunchKioskApp(context.applicationContext)
    }

    private fun maybeRelaunchKioskApp(context: Context) {
        // Written by Flutter's shared_preferences (KioskModeService) — the plugin
        // stores bools in the FlutterSharedPreferences file with a "flutter." prefix.
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("flutter.kiosk_mode_enabled", false)) return

        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
        if (launch == null) {
            Log.e(TAG, "Kiosk relaunch skipped — no launch intent for own package")
            return
        }
        // Background activity starts are restricted on Android 10+, but this app
        // qualifies for two documented exemptions on a provisioned kiosk device:
        // SYSTEM_ALERT_WINDOW granted (onboarding flow) and/or Device Owner status.
        try {
            context.startActivity(launch)
            Log.d(TAG, "Kiosk Mode enabled — relaunched app after boot/update")
        } catch (e: Exception) {
            Log.e(TAG, "Kiosk relaunch failed: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "BootReceiver"
    }
}
