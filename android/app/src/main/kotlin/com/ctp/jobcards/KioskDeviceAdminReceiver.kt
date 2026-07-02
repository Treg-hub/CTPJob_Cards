package com.ctp.jobcards

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Required to make this app eligible for Device Owner provisioning on a
 * dedicated kiosk tablet (e.g. the main-gate security device):
 *
 *   adb shell dpm set-device-owner com.ctp.jobcards/.KioskDeviceAdminReceiver
 *
 * Device Owner status is what lets MainActivity's Lock Task Mode fully
 * suppress the system "unpin" gesture instead of just best-effort screen
 * pinning. See KioskModeScreen (Flutter) for the in-app setup guide. This
 * receiver is inert on every other install — nothing here runs unless a
 * specific device has actually been enrolled as Device Owner.
 */
class KioskDeviceAdminReceiver : DeviceAdminReceiver() {
    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Log.d("KioskDeviceAdmin", "Device admin enabled")
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        Log.d("KioskDeviceAdmin", "Device admin disabled")
    }
}
