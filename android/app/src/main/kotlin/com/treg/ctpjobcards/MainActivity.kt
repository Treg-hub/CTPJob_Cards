package com.treg.ctpjobcards

import android.app.PendingIntent
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices

class MainActivity : FlutterActivity() {
    companion object {
        var geofenceChannel: MethodChannel? = null
    }

    private lateinit var geofencingClient: GeofencingClient
    private val geofencePendingIntent: PendingIntent by lazy {
        val intent = Intent(this, GeofenceBroadcastReceiver::class.java)
        PendingIntent.getBroadcast(this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        geofenceChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ctp/geofence")
        geofencingClient = LocationServices.getGeofencingClient(this)

        geofenceChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "registerGeofence" -> {
                    val lat = call.argument<Double>("lat")!!
                    val lng = call.argument<Double>("lng")!!
                    val radius = call.argument<Double>("radius")!!
                    val clockNo = call.argument<String>("clockNo")!!

                    registerGeofence(lat, lng, radius, clockNo)
                    result.success(null)
                }
                "stopGeofence" -> {
                    stopGeofence()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun registerGeofence(lat: Double, lng: Double, radius: Double, clockNo: String) {
        val geofence = Geofence.Builder()
            .setRequestId(clockNo)
            .setCircularRegion(lat, lng, radius.toFloat())
            .setExpirationDuration(Geofence.NEVER_EXPIRE)
            .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT)
            .build()

        val geofencingRequest = GeofencingRequest.Builder()
            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
            .addGeofence(geofence)
            .build()

        geofencingClient.addGeofences(geofencingRequest, geofencePendingIntent)
    }

    private fun stopGeofence() {
        geofencingClient.removeGeofences(geofencePendingIntent)
    }
}