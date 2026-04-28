package com.example.ctp_job_cards

import android.content.Intent
import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class FirebaseMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        Log.d("FirebaseMessagingService", "📩 BACKGROUND FCM received")
        Log.d("FirebaseMessagingService", "📊 Full data payload: ${remoteMessage.data}")

        val level = remoteMessage.data["notificationLevel"] ?: ""
        if (level == "full-loud") {
            val jobCardNumber = remoteMessage.data["jobCardNumber"]
                ?: remoteMessage.data["jobcardnumber"]
                ?: remoteMessage.data["job_card_number"]
                ?: "Unknown"
            val description = remoteMessage.data["body"]
                ?: remoteMessage.data["description"]
                ?: remoteMessage.data["message"]
                ?: "Urgent job alert"

            Log.d("FirebaseMessagingService", "🚨 BACKGROUND FULL-LOUD detected! Job: $jobCardNumber")

            val intent = Intent(this, AlertForegroundService::class.java).apply {
                putExtra("jobCardNumber", jobCardNumber)
                putExtra("description", description)
            }
            startForegroundService(intent)
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d("FirebaseMessagingService", "🔄 FCM Token refreshed: ${token.take(20)}...")
    }
}