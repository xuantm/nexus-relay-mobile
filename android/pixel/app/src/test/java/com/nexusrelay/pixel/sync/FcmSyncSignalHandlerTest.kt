package com.nexusrelay.pixel.sync

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

class FcmSyncSignalHandlerTest {
    @Test
    fun handleMessage_enqueuesSyncForDeviceSyncJobAvailable() = runTest {
        var enqueued = 0
        val handler = FcmSyncSignalHandler(
            enqueueExpeditedSync = { enqueued++ }
        )

        handler.handleMessage(type = "device_sync_job_available")

        assertEquals(1, enqueued)
    }

    @Test
    fun handleMessage_ignoresUnknownMessageTypes() = runTest {
        var enqueued = 0
        val handler = FcmSyncSignalHandler(
            enqueueExpeditedSync = { enqueued++ }
        )

        handler.handleMessage(type = "unknown")

        assertEquals(0, enqueued)
    }

    @Test
    fun handleDeletedMessages_enqueuesFullSync() = runTest {
        var enqueued = 0
        val handler = FcmSyncSignalHandler(
            enqueueExpeditedSync = { enqueued++ }
        )

        handler.handleDeletedMessages()

        assertEquals(1, enqueued)
    }
}
