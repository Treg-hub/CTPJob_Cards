package com.example.ctp_job_cards

import android.content.Intent
import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class FirebaseMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)

        Log.d("FirebaseMessagingService", "📩 BACKGROUND FCM received")

        // Check if this is a full-loud urgent notification
        val notificationLevel = remoteMessage.data["notificationLevel"]
        val jobCardNumber = remoteMessage.data["jobCardNumber"]
        val description = remoteMessage.data["body"] ?: remoteMessage.data["description"]

        Log.d("FirebaseMessagingService", "📩 Level: $notificationLevel, Job: $jobCardNumber")

        if (notificationLevel == "full-loud" && jobCardNumber != null && description != null) {
            Log.d("FirebaseMessagingService", "🚨 BACKGROUND FULL-LOUD detected! Starting AlertForegroundService")

            // Start the AlertForegroundService directly (same as MainActivity)
            val intent = Intent(this, AlertForegroundService::class.java).apply {
                putExtra("jobCardNumber", jobCardNumber)
                putExtra("description", description)
            }
            startForegroundService(intent)

            Log.d("FirebaseMessagingService", "✅ AlertForegroundService started from background")
        } else {
            Log.d("FirebaseMessagingService", "📩 Normal notification - not urgent")
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d("FirebaseMessagingService", "🔄 FCM Token refreshed: ${token.take(20)}...")
    }
}