package com.nexusrelay.pixel.sync

internal class FcmSyncSignalHandler(
    private val enqueueExpeditedSync: suspend () -> Unit
) {
    suspend fun handleMessage(type: String?) {
        if (type == DEVICE_SYNC_JOB_AVAILABLE || type == DEVICE_SYNC_WAKE_REQUESTED) {
            enqueueExpeditedSync()
        }
    }

    suspend fun handleDeletedMessages() {
        enqueueExpeditedSync()
    }

    private companion object {
        private const val DEVICE_SYNC_JOB_AVAILABLE = "device_sync_job_available"
        private const val DEVICE_SYNC_WAKE_REQUESTED = "device_sync_wake_requested"
    }
}
