package com.nexusrelay.pixel.sync

import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.nexusrelay.pixel.storage.AppSettingsStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class FcmReceiverService : FirebaseMessagingService() {

    private val tag = "FcmReceiverService"
    private val serviceScope = CoroutineScope(Dispatchers.IO)

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        Log.d(tag, "FCM Message received from: ${message.from}")

        val type = message.data["type"]
        val jobId = message.data["jobId"]

        Log.d(tag, "FCM sync signal received. type=$type jobId=$jobId")
        serviceScope.launch {
            syncSignalHandler().handleMessage(type)
        }
    }

    override fun onDeletedMessages() {
        super.onDeletedMessages()
        Log.w(tag, "FCM messages were deleted before delivery. Enqueuing full sync.")
        serviceScope.launch {
            syncSignalHandler().handleDeletedMessages()
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(tag, "FCM token rotated: $token")

        serviceScope.launch {
            val appSettingsStore = AppSettingsStore(applicationContext)
            appSettingsStore.saveFcmToken(token)
            refreshBackendFcmToken(applicationContext, token)
        }
    }

    private fun syncSignalHandler(): FcmSyncSignalHandler {
        return FcmSyncSignalHandler(
            enqueueExpeditedSync = {
                SyncWorker.enqueueOneTimeSync(applicationContext, expedited = true)
            }
        )
    }
}
