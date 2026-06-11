package com.nexusrelay.pixel.sync

import androidx.work.ExistingWorkPolicy
import androidx.work.WorkInfo
import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
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

    @Test
    fun buildSyncInputDataStoresWorkerRunIdAndContinuationFlag() {
        val inputData = buildSyncInputData(
            workerRunId = "worker-123",
            isContinuation = true
        )

        assertEquals("worker-123", inputData.getString(SyncWorker.KEY_WORKER_RUN_ID))
        assertTrue(inputData.getBoolean(SyncWorker.KEY_IS_CONTINUATION, false))
    }

    @Test
    fun workerRunIdDefaultsWhenInputDataMissing() {
        val workerRunId = resolveWorkerRunId(androidx.work.Data.EMPTY)

        assertNotNull(workerRunId)
        assertFalse(workerRunId.isBlank())
    }
}
