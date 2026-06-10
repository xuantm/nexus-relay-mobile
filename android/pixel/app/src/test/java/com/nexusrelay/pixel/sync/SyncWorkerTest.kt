package com.nexusrelay.pixel.sync

import androidx.work.ExistingWorkPolicy
import androidx.work.WorkInfo
import org.junit.Assert.assertEquals
import org.junit.Test

class SyncWorkerTest {
    @Test
    fun selectExistingWorkPolicy_nonExpedited_keepsExistingWork() {
        val policy = selectExistingWorkPolicy(
            expedited = false,
            existingStates = listOf(WorkInfo.State.ENQUEUED)
        )

        assertEquals(ExistingWorkPolicy.KEEP, policy)
    }

    @Test
    fun selectExistingWorkPolicy_expeditedReplacesQueuedOrBlockedWork() {
        assertEquals(
            ExistingWorkPolicy.REPLACE,
            selectExistingWorkPolicy(
                expedited = true,
                existingStates = listOf(WorkInfo.State.ENQUEUED)
            )
        )
        assertEquals(
            ExistingWorkPolicy.REPLACE,
            selectExistingWorkPolicy(
                expedited = true,
                existingStates = listOf(WorkInfo.State.BLOCKED)
            )
        )
    }

    @Test
    fun selectExistingWorkPolicy_expeditedKeepsRunningWork() {
        val policy = selectExistingWorkPolicy(
            expedited = true,
            existingStates = listOf(WorkInfo.State.RUNNING)
        )

        assertEquals(ExistingWorkPolicy.KEEP, policy)
    }
}
