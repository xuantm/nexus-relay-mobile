package com.nexusrelay.pixel.storage

import android.content.Context
import android.content.ContextWrapper
import com.nexusrelay.pixel.api.SyncStatus
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class LocalSyncLedgerTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private class TestContext : ContextWrapper(null)

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun testLedgerOperations() = runTest {
        val tempFile = File(tempFolder.root, "test_ledger.preferences_pb")
        val dataStore = PreferenceDataStoreFactory.create { tempFile }
        val ledger = LocalSyncLedger(TestContext(), dataStore)

        // 1. Initial get should be null
        val initialRecord = ledger.get("job-1")
        assertNull(initialRecord)

        // 2. Insert record
        val record = LocalSyncRecord(
            jobId = "job-1",
            mediaId = "media-1",
            fileName = "image.png",
            mimeType = "image/png",
            sizeBytes = 100L,
            sha256 = "hash123",
            status = LocalSyncStatus.Queued,
            localUri = null,
            lastAttemptAt = System.currentTimeMillis(),
            lastError = null
        )
        ledger.upsert(record)

        val saved = ledger.get("job-1")
        assertNotNull(saved)
        assertEquals("job-1", saved!!.jobId)
        assertEquals(LocalSyncStatus.Queued, saved.status)

        // 3. Mark claimed/progress
        ledger.markClaimed("job-1", "lease-1", "worker-1")
        ledger.markProgress("job-1", "Downloading", 64L, 100L)
        val downloading = ledger.get("job-1")
        assertNotNull(downloading)
        assertEquals(LocalSyncStatus.Downloading, downloading!!.status)
        assertEquals("lease-1", downloading.leaseId)
        assertEquals("worker-1", downloading.workerRunId)
        assertEquals(64L, downloading.progressBytes)
        assertEquals(100L, downloading.totalBytes)
        assertEquals("Downloading", downloading.stage)

        // 4. Mark imported/confirm pending
        ledger.markConfirmPending("job-1", "content://media/1")
        val pending = ledger.get("job-1")
        assertNotNull(pending)
        assertEquals(LocalSyncStatus.ConfirmPending, pending!!.status)
        assertEquals("content://media/1", pending.localUri)

        // 5. Mark confirmed
        ledger.markConfirmed("job-1")
        val confirmed = ledger.get("job-1")
        assertNotNull(confirmed)
        assertEquals(LocalSyncStatus.Confirmed, confirmed!!.status)

        // 6. Mark failed
        ledger.markFailed("job-1", "Network error")
        val failed = ledger.get("job-1")
        assertNotNull(failed)
        assertEquals(LocalSyncStatus.Failed, failed!!.status)
        assertEquals("Network error", failed.lastError)
    }

    @Test
    fun localSyncStatusProjectsToSharedSyncStatus() {
        assertEquals(SyncStatus.Pending, LocalSyncStatus.Queued.toSyncStatus())
        assertEquals(SyncStatus.Syncing, LocalSyncStatus.Downloading.toSyncStatus())
        assertEquals(SyncStatus.Syncing, LocalSyncStatus.Imported.toSyncStatus())
        assertEquals(SyncStatus.Syncing, LocalSyncStatus.ConfirmPending.toSyncStatus())
        assertEquals(SyncStatus.Synced, LocalSyncStatus.Confirmed.toSyncStatus())
        assertEquals(SyncStatus.Failed, LocalSyncStatus.Failed.toSyncStatus())
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun testLedgerFlowLimits() = runTest {
        val tempFile = File(tempFolder.root, "test_ledger_flow.preferences_pb")
        val dataStore = PreferenceDataStoreFactory.create { tempFile }
        val ledger = LocalSyncLedger(TestContext(), dataStore)

        // Insert 60 records
        for (i in 1..60) {
            val record = LocalSyncRecord(
                jobId = "job-$i",
                mediaId = "media-$i",
                fileName = "image-$i.png",
                mimeType = "image/png",
                sizeBytes = 100L,
                sha256 = "hash-$i",
                status = LocalSyncStatus.Confirmed,
                localUri = "content://media/$i",
                lastAttemptAt = i.toLong(),
                lastError = null
            )
            ledger.upsert(record)
        }

        // Verify allRecordsFlow returns 60
        val allRecords = ledger.allRecordsFlow.first()
        assertEquals(60, allRecords.size)

        // Verify recentRecordsFlow returns 50
        val recentRecords = ledger.recentRecordsFlow.first()
        assertEquals(50, recentRecords.size)

        // Verify sorting (descending by lastAttemptAt)
        assertEquals("job-60", allRecords.first().jobId)
        assertEquals("job-1", allRecords.last().jobId)
        assertEquals("job-60", recentRecords.first().jobId)
        assertEquals("job-11", recentRecords.last().jobId)
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun clearHistoryRemovesOnlyConfirmedAndFailedRecords() = runTest {
        val tempFile = File(tempFolder.root, "clear_history.preferences_pb")
        val dataStore = PreferenceDataStoreFactory.create { tempFile }
        val ledger = LocalSyncLedger(TestContext(), dataStore)

        ledger.upsert(
            LocalSyncRecord(
                jobId = "confirmed",
                mediaId = "media-confirmed",
                fileName = "confirmed.jpg",
                mimeType = "image/jpeg",
                sizeBytes = 1L,
                sha256 = null,
                status = LocalSyncStatus.Confirmed,
                localUri = "content://confirmed",
                lastAttemptAt = 10L,
                lastError = null,
                isLocalDeleted = false,
                statusEnteredAt = 10L,
                retryCount = 0
            )
        )
        ledger.upsert(
            LocalSyncRecord(
                jobId = "failed",
                mediaId = "media-failed",
                fileName = "failed.jpg",
                mimeType = "image/jpeg",
                sizeBytes = 1L,
                sha256 = null,
                status = LocalSyncStatus.Failed,
                localUri = null,
                lastAttemptAt = 20L,
                lastError = "timeout",
                isLocalDeleted = false,
                statusEnteredAt = 20L,
                retryCount = 2
            )
        )
        ledger.upsert(
            LocalSyncRecord(
                jobId = "confirm-pending",
                mediaId = "media-confirm-pending",
                fileName = "pending.jpg",
                mimeType = "image/jpeg",
                sizeBytes = 1L,
                sha256 = null,
                status = LocalSyncStatus.ConfirmPending,
                localUri = "content://pending",
                lastAttemptAt = 30L,
                lastError = null,
                isLocalDeleted = false,
                statusEnteredAt = 30L,
                retryCount = 1
            )
        )

        ledger.clearHistory()

        assertNull(ledger.get("confirmed"))
        assertNull(ledger.get("failed"))
        assertEquals(LocalSyncStatus.ConfirmPending, ledger.get("confirm-pending")?.status)
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun recordRetriableFailurePreservesStatusAndIncrementsRetryCount() = runTest {
        val tempFile = File(tempFolder.root, "retriable.preferences_pb")
        val dataStore = PreferenceDataStoreFactory.create { tempFile }
        val ledger = LocalSyncLedger(TestContext(), dataStore)

        ledger.upsert(
            LocalSyncRecord(
                jobId = "job-1",
                mediaId = "media-1",
                fileName = "image.jpg",
                mimeType = "image/jpeg",
                sizeBytes = 100L,
                sha256 = null,
                status = LocalSyncStatus.ConfirmPending,
                localUri = "content://media/1",
                lastAttemptAt = 100L,
                lastError = null,
                isLocalDeleted = false,
                statusEnteredAt = 80L,
                retryCount = 0
            )
        )

        ledger.recordRetriableFailure("job-1", "Confirm timeout", now = 200L)

        val updated = ledger.get("job-1")!!
        assertEquals(LocalSyncStatus.ConfirmPending, updated.status)
        assertEquals("Confirm timeout", updated.lastError)
        assertEquals(200L, updated.lastAttemptAt)
        assertEquals(80L, updated.statusEnteredAt)
        assertEquals(1, updated.retryCount)
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun hasActiveRecordsIgnoresConfirmedAndFailedHistory() = runTest {
        val tempFile = File(tempFolder.root, "active.preferences_pb")
        val dataStore = PreferenceDataStoreFactory.create { tempFile }
        val ledger = LocalSyncLedger(TestContext(), dataStore)

        ledger.upsert(
            LocalSyncRecord(
                jobId = "history",
                mediaId = "media-history",
                fileName = "history.jpg",
                mimeType = "image/jpeg",
                sizeBytes = 1L,
                sha256 = null,
                status = LocalSyncStatus.Failed,
                localUri = null,
                lastAttemptAt = 1L,
                lastError = "fail",
                isLocalDeleted = false,
                statusEnteredAt = 1L,
                retryCount = 1
            )
        )
        assertFalse(ledger.hasActiveRecords())

        ledger.upsert(
            LocalSyncRecord(
                jobId = "active",
                mediaId = "media-active",
                fileName = "active.jpg",
                mimeType = "image/jpeg",
                sizeBytes = 1L,
                sha256 = null,
                status = LocalSyncStatus.Queued,
                localUri = null,
                lastAttemptAt = 2L,
                lastError = null,
                isLocalDeleted = false,
                statusEnteredAt = 2L,
                retryCount = 0
            )
        )
        assertTrue(ledger.hasActiveRecords())
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun markQueuedClearsFailureStateForRetry() = runTest {
        val tempFile = File(tempFolder.root, "mark_queued.preferences_pb")
        val dataStore = PreferenceDataStoreFactory.create { tempFile }
        val ledger = LocalSyncLedger(TestContext(), dataStore)

        ledger.upsert(
            LocalSyncRecord(
                jobId = "failed-job",
                mediaId = "media-failed-job",
                fileName = "failed.jpg",
                mimeType = "image/jpeg",
                sizeBytes = 1L,
                sha256 = null,
                status = LocalSyncStatus.Failed,
                localUri = null,
                lastAttemptAt = 50L,
                lastError = "network error",
                isLocalDeleted = false,
                statusEnteredAt = 40L,
                retryCount = 3
            )
        )

        ledger.markQueued("failed-job", now = 99L)

        val retried = ledger.get("failed-job")!!
        assertEquals(LocalSyncStatus.Queued, retried.status)
        assertNull(retried.lastError)
        assertEquals(99L, retried.lastAttemptAt)
        assertEquals(99L, retried.statusEnteredAt)
        assertEquals(0, retried.retryCount)
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun markFailureReportedRemovesRecordFromUnreportedFailures() = runTest {
        val tempFile = File(tempFolder.root, "failure_reported.preferences_pb")
        val dataStore = PreferenceDataStoreFactory.create { tempFile }
        val ledger = LocalSyncLedger(TestContext(), dataStore)

        ledger.upsert(
            LocalSyncRecord(
                jobId = "failed-job",
                mediaId = "media-failed-job",
                fileName = "failed.jpg",
                mimeType = "image/jpeg",
                sizeBytes = 1L,
                sha256 = null,
                status = LocalSyncStatus.Failed,
                localUri = null,
                lastAttemptAt = 50L,
                lastError = "download failed",
                isLocalDeleted = false,
                statusEnteredAt = 40L,
                retryCount = 0
            )
        )

        assertEquals(listOf("failed-job"), ledger.listUnreportedFailures().map { it.jobId })

        ledger.markFailureReported("failed-job", now = 88L)

        val reported = ledger.get("failed-job")!!
        assertEquals(88L, reported.backendFailureReportedAt)
        assertTrue(ledger.listUnreportedFailures().isEmpty())
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun markClaimedStoresLeaseAndWorkerContext() = runTest {
        val tempFile = File(tempFolder.root, "mark_claimed.preferences_pb")
        val dataStore = PreferenceDataStoreFactory.create { tempFile }
        val ledger = LocalSyncLedger(TestContext(), dataStore)

        ledger.upsert(
            LocalSyncRecord(
                jobId = "job-lease",
                mediaId = "media-lease",
                fileName = "lease.jpg",
                mimeType = "image/jpeg",
                sizeBytes = 200L,
                sha256 = null,
                status = LocalSyncStatus.Queued,
                localUri = null,
                lastAttemptAt = 10L,
                lastError = null
            )
        )

        ledger.markClaimed("job-lease", "lease-123", "worker-123")
        ledger.markProgress("job-lease", "Confirming", 200L, 200L)

        val record = ledger.get("job-lease")!!
        assertEquals("lease-123", record.leaseId)
        assertEquals("worker-123", record.workerRunId)
        assertEquals(200L, record.progressBytes)
        assertEquals(200L, record.totalBytes)
        assertEquals("Confirming", record.stage)
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun concurrentUpsertsPreserveAllRecords() = runTest {
        val tempFile = File(tempFolder.root, "concurrent_upserts.preferences_pb")
        val dataStore = PreferenceDataStoreFactory.create { tempFile }
        val ledger = LocalSyncLedger(TestContext(), dataStore)

        val writes = (1..25).map { index ->
            launch {
                ledger.upsert(
                    LocalSyncRecord(
                        jobId = "job-$index",
                        mediaId = "media-$index",
                        fileName = "image-$index.jpg",
                        mimeType = "image/jpeg",
                        sizeBytes = index.toLong(),
                        sha256 = null,
                        status = LocalSyncStatus.Queued,
                        localUri = null,
                        lastAttemptAt = index.toLong(),
                        lastError = null
                    )
                )
            }
        }

        writes.joinAll()

        val allRecords = ledger.allRecordsFlow.first()
        assertEquals(25, allRecords.size)
        assertEquals((1..25).map { "job-$it" }.toSet(), allRecords.map { it.jobId }.toSet())
    }
}
