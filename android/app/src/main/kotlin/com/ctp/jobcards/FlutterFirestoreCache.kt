package com.ctp.jobcards

import android.util.Log
import com.google.firebase.firestore.FirebaseFirestore

/**
 * Bridges native [FirebaseFirestore.getInstance] usage (GeofenceReceiver, alert
 * assign flows) into the Flutter `cloud_firestore` plugin instance cache.
 *
 * Without this, the sequence:
 *   1. Native code calls [FirebaseFirestore.getInstance] + any op → client starts
 *   2. Flutter [getFirestoreFromPigeon] cache-misses → [setFirestoreSettings]
 *      throws "already been started and its settings can no longer be changed"
 *   3. The instance is never cached → every later Flutter call fails the same way
 *
 * Registering the shared instance into the plugin cache makes step 2 a cache hit
 * so Flutter never re-applies settings.
 */
object FlutterFirestoreCache {
    private const val TAG = "FlutterFirestoreCache"
    private const val DEFAULT_DATABASE = "(default)"

    /**
     * Idempotent. Safe to call before or after the client has started.
     * Never calls setFirestoreSettings (that must only happen when Flutter owns
     * first access, or not at all once native has already started the client).
     */
    @JvmStatic
    fun ensureRegistered(firestore: FirebaseFirestore = FirebaseFirestore.getInstance()) {
        try {
            val pluginClass = Class.forName(
                "io.flutter.plugins.firebase.firestore.FlutterFirebaseFirestorePlugin",
            )
            val setter = pluginClass.getDeclaredMethod(
                "setCachedFirebaseFirestoreInstanceForKey",
                FirebaseFirestore::class.java,
                String::class.java,
            )
            setter.isAccessible = true
            setter.invoke(null, firestore, DEFAULT_DATABASE)
            Log.d(TAG, "Registered Firestore instance in Flutter plugin cache")
        } catch (e: Exception) {
            // Plugin class may be absent in pure-native test hosts; never crash
            // geofence / assign paths over cache registration.
            Log.w(TAG, "Could not register Firestore in Flutter cache: ${e.message}")
        }
    }
}
