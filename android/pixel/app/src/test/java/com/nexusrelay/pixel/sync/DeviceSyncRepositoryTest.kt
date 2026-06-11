package com.nexusrelay.pixel.sync

import android.content.ContentResolver
import android.content.Context
import com.nexusrelay.pixel.api.ClaimDeviceSyncJobsResponse
import com.nexusrelay.pixel.api.ConfirmDeviceSyncJobRequest
import com.nexusrelay.pixel.api.DeviceSyncClaimedJobDto
import com.nexusrelay.pixel.api.DeviceSyncHeartbeatResponse
import com.nexusrelay.pixel.api.FailDeviceSyncJobRequest
import com.nexusrelay.pixel.api.NexusRelayApi
import com.nexusrelay.pixel.auth.DeviceTokenStore
import com.nexusrelay.pixel.media.MediaImporter
import com.nexusrelay.pixel.storage.AppSettingsStore
import com.nexusrelay.pixel.storage.LocalSyncLedger
import com.nexusrelay.pixel.storage.LocalSyncRecord
import com.nexusrelay.pixel.storage.LocalSyncStatus
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.kotlin.any
import org.mockito.kotlin.anyOrNull
import org.mockito.kotlin.eq
import org.mockito.kotlin.never
import org.mockito.kotlin.verify
import org.mockito.kotlin.whenever
import java.io.IOException
import retrofit2.HttpException
import retrofit2.Response

class DeviceSyncRepositoryTest {

    private val mockContext = mock(Context::class.java)
    private val mockSettingsStore = mock(AppSettingsStore::class.java)
    private val mockTokenStore = mock(DeviceTokenStore::class.java)
    private val mockLedger = mock(LocalSyncLedger::class.java)
    private val mockImporter = mock(MediaImporter::class.java)
    private val mockApi = mock(NexusRelayApi::class.java)

    private fun createRepository(): DeviceSyncRepository {
        return DeviceSyncRepository(
            context = mockContext,
            appSettingsStore = mockSettingsStore,
            deviceTokenStore = mockTokenStore,
            ledger = mockLedger,
            mediaStoreImporter = mockImporter,
            apiProvider = { mockApi }
        )
    }

    private suspend fun setupConfiguredMocks(deviceToken: String = "token-123") {
        whenever(mockSettingsStore.backendBaseUrlFlow).thenReturn(flowOf("http://backend.url"))
        whenever(mockTokenStore.getDeviceToken()).thenReturn(deviceToken)
        whenever(
            mockLedger.listByStatuses(
                LocalSyncStatus.ConfirmPending,
                LocalSyncStatus.Imported
            )
        ).thenReturn(emptyList())
        whenever(mockLedger.listByStatuses(LocalSyncStatus.Queued)).thenReturn(emptyList())
        whenever(mockLedger.listByStatuses(LocalSyncStatus.Downloading)).thenReturn(emptyList())
        whenever(mockLedger.listUnreportedFailures()).thenReturn(emptyList())
        whenever(mockApi.heartbeatDeviceSyncJob(eq(deviceToken), any(), any())).thenReturn(
            DeviceSyncHeartbeatResponse("2026-06-11T10:15:30Z")
        )
        whenever(mockApi.claimDeviceSyncJobs(eq(deviceToken), any())).thenReturn(
            ClaimDeviceSyncJobsResponse(
                leaseId = "lease-empty",
                leaseExpiresAt = "2026-06-11T10:15:00Z",
                remainingPendingCount = 0,
                jobs = emptyList()
            )
        )
    }

    @Test
    fun syncPendingJobsReturnsFalseWhenNotConfigured() = runTest {
        whenever(mockSettingsStore.backendBaseUrlFlow).thenReturn(flowOf(null))
        whenever(mockTokenStore.getDeviceToken()).thenReturn(null)

        val repository = createRepository()

        assertFalse(repository.syncPendingJobs(workerRunId = "worker-1"))
    }

    @Test
    fun syncPendingJobsRetriesLocalConfirmationsWithLeaseContext() = runTest {
        setupConfiguredMocks()
        val record = LocalSyncRecord(
            jobId = "job-local-confirm",
            mediaId = "media-local-confirm",
            fileName = "confirm.jpg",
            mimeType = "image/jpeg",
            sizeBytes = 123L,
            sha256 = null,
            status = LocalSyncStatus.ConfirmPending,
            localUri = "content://media/external/images/media/local-confirm",
            lastAttemptAt = 0L,
            lastError = null,
            leaseId = "lease-42",
            workerRunId = "worker-original",
            progressBytes = 123L,
            totalBytes = 123L,
            stage = "Confirming"
        )
        whenever(
            mockLedger.listByStatuses(
                LocalSyncStatus.ConfirmPending,
                LocalSyncStatus.Imported
            )
        ).thenReturn(listOf(record))

        val repository = createRepository()

        assertTrue(repository.syncPendingJobs(workerRunId = "worker-run-1"))

        verify(mockApi).confirmDeviceSyncJob(
            eq("token-123"),
            eq("job-local-confirm"),
            eq(
                ConfirmDeviceSyncJobRequest(
                    importedUri = "content://media/external/images/media/local-confirm",
                    importedSizeBytes = 123L,
                    leaseId = "lease-42",
                    workerRunId = "worker-original"
                )
            )
        )
        verify(mockLedger).markConfirmed("job-local-confirm")
    }

    @Test
    fun syncPendingJobsReportsPreviouslyUnreportedFailuresWithLeaseContext() = runTest {
        setupConfiguredMocks()
        val failedRecord = LocalSyncRecord(
            jobId = "job-unreported-failed",
            mediaId = "media-unreported-failed",
            fileName = "failed.jpg",
            mimeType = "image/jpeg",
            sizeBytes = 10L,
            sha256 = null,
            status = LocalSyncStatus.Failed,
            localUri = null,
            lastAttemptAt = 0L,
            lastError = "Previous report failed",
            leaseId = "lease-failed",
            workerRunId = "worker-failed",
            progressBytes = 7L,
            totalBytes = 10L,
            stage = "Downloading"
        )
        whenever(mockLedger.listUnreportedFailures()).thenReturn(listOf(failedRecord))

        val repository = createRepository()

        assertTrue(repository.syncPendingJobs(workerRunId = "worker-run-1"))

        verify(mockApi).failDeviceSyncJob(
            eq("token-123"),
            eq("job-unreported-failed"),
            eq(
                FailDeviceSyncJobRequest(
                    error = "Previous report failed",
                    retryable = false,
                    leaseId = "lease-failed",
                    workerRunId = "worker-failed"
                )
            )
        )
        verify(mockLedger).markFailureReported(eq("job-unreported-failed"), any())
    }

    @Test
    fun syncPendingJobsPropagatesRetriableClaimFailures() = runTest {
        setupConfiguredMocks()
        whenever(mockApi.claimDeviceSyncJobs(eq("token-123"), any())).thenAnswer {
            throw IOException("claim failed")
        }

        val repository = createRepository()

        var threw = false
        try {
            repository.syncPendingJobs(workerRunId = "worker-run-1")
        } catch (expected: IOException) {
            threw = true
        }

        assertTrue(threw)
    }

    @Test
    fun syncPendingJobsFailsStaleClaimedQueuedRecordsBeforeClaimLoop() = runTest {
        setupConfiguredMocks()
        val staleQueuedRecord = LocalSyncRecord(
            jobId = "job-queued-stale",
            mediaId = "media-queued-stale",
            fileName = "queued.jpg",
            mimeType = "image/jpeg",
            sizeBytes = 10L,
            sha256 = null,
            status = LocalSyncStatus.Queued,
            localUri = null,
            lastAttemptAt = System.currentTimeMillis() - (2 * 60 * 60 * 1000L),
            lastError = null,
            leaseId = "lease-queued",
            workerRunId = "worker-queued"
        )
        whenever(mockLedger.listByStatuses(LocalSyncStatus.Queued)).thenReturn(listOf(staleQueuedRecord))

        val repository = createRepository()

        assertTrue(repository.syncPendingJobs(workerRunId = "worker-run-1"))

        verify(mockLedger).markFailed("job-queued-stale", "Sync timed out before download started")
        verify(mockApi).failDeviceSyncJob(
            eq("token-123"),
            eq("job-queued-stale"),
            eq(
                FailDeviceSyncJobRequest(
                    error = "Sync timed out before download started",
                    retryable = false,
                    leaseId = "lease-queued",
                    workerRunId = "worker-queued"
                )
            )
        )
    }

    @Test
    fun syncPendingJobsTimesOutLongRunningConfirmPendingByStatusEnteredAt() = runTest {
        setupConfiguredMocks()
        val staleConfirmPending = LocalSyncRecord(
            jobId = "job-confirm-timeout",
            mediaId = "media-confirm-timeout",
            fileName = "confirm-timeout.jpg",
            mimeType = "image/jpeg",
            sizeBytes = 512L,
            sha256 = null,
            status = LocalSyncStatus.ConfirmPending,
            localUri = "content://media/confirm-timeout",
            lastAttemptAt = System.currentTimeMillis(),
            lastError = null,
            statusEnteredAt = System.currentTimeMillis() - (2 * 60 * 60 * 1000L),
            retryCount = 4,
            leaseId = "lease-confirm-timeout",
            workerRunId = "worker-confirm-timeout"
        )
        whenever(
            mockLedger.listByStatuses(
                LocalSyncStatus.ConfirmPending,
                LocalSyncStatus.Imported
            )
        ).thenReturn(listOf(staleConfirmPending))
        whenever(
            mockApi.confirmDeviceSyncJob(
                eq("token-123"),
                eq("job-confirm-timeout"),
                any()
            )
        ).thenThrow(
            HttpException(
                Response.error<Any>(
                    503,
                    "backend unavailable".toResponseBody("text/plain".toMediaType())
                )
            )
        )

        val repository = createRepository()

        assertFalse(repository.syncPendingJobs(workerRunId = "worker-run-1"))

        verify(mockLedger).markFailed("job-confirm-timeout", "Sync confirmation timed out after 1 hour")
    }

    @Test
    fun cleanUpLocalFilesDisabledDoesNotDelete() = runTest {
        whenever(mockSettingsStore.autoDeleteEnabledFlow).thenReturn(flowOf(false))

        val repository = createRepository()
        repository.cleanUpLocalFiles()

        verify(mockLedger, never()).listByStatuses(any())
    }

    @Test
    fun cleanUpLocalFilesEnabledAndOlderThanDelayDeletesAndMarksDeleted() = runTest {
        whenever(mockSettingsStore.autoDeleteEnabledFlow).thenReturn(flowOf(true))
        whenever(mockSettingsStore.autoDeleteDelayMinutesFlow).thenReturn(flowOf(2 * 60))

        val record = LocalSyncRecord(
            jobId = "job-old",
            mediaId = "media-old",
            fileName = "test.jpg",
            mimeType = "image/jpeg",
            sizeBytes = 100L,
            sha256 = null,
            status = LocalSyncStatus.Confirmed,
            localUri = "content://media/external/images/media/old",
            lastAttemptAt = System.currentTimeMillis() - 3 * 3600 * 1000L,
            lastError = null
        )
        whenever(mockLedger.listByStatuses(LocalSyncStatus.Confirmed)).thenReturn(listOf(record))

        val mockContentResolver = mock(ContentResolver::class.java)
        whenever(mockContext.contentResolver).thenReturn(mockContentResolver)
        whenever(mockContentResolver.delete(anyOrNull(), anyOrNull(), anyOrNull())).thenReturn(1)

        val repository = createRepository()
        repository.cleanUpLocalFiles()

        verify(mockLedger).markLocalDeleted("job-old")
    }

    @Test
    fun retryFailedJobRequeuesFailedRecord() = runTest {
        val failedRecord = LocalSyncRecord(
            jobId = "job-retry",
            mediaId = "media-retry",
            fileName = "retry.jpg",
            mimeType = "image/jpeg",
            sizeBytes = 100L,
            sha256 = null,
            status = LocalSyncStatus.Failed,
            localUri = null,
            lastAttemptAt = 0L,
            lastError = "download failed"
        )
        whenever(mockLedger.get("job-retry")).thenReturn(failedRecord)

        val repository = createRepository()

        assertTrue(repository.retryFailedJob("job-retry"))

        verify(mockLedger).markQueued(eq("job-retry"), any())
    }

    @Test
    fun retryFailedJobIgnoresNonFailedRecord() = runTest {
        val queuedRecord = LocalSyncRecord(
            jobId = "job-queued",
            mediaId = "media-queued",
            fileName = "queued.jpg",
            mimeType = "image/jpeg",
            sizeBytes = 100L,
            sha256 = null,
            status = LocalSyncStatus.Queued,
            localUri = null,
            lastAttemptAt = 0L,
            lastError = null
        )
        whenever(mockLedger.get("job-queued")).thenReturn(queuedRecord)

        val repository = createRepository()

        assertFalse(repository.retryFailedJob("job-queued"))

        verify(mockLedger, never()).markQueued(eq("job-queued"), any())
    }

    @Test
    fun syncPendingJobsSavesLastSuccessfulSyncAfterClaimedWork() = runTest {
        setupConfiguredMocks()
        val claimedJob = DeviceSyncClaimedJobDto(
            jobId = "job-claimed",
            mediaId = "media-job-claimed",
            fileName = "file-job-claimed.jpg",
            mimeType = "image/jpeg",
            mediaType = "Image",
            sizeBytes = 100L,
            sha256 = "sha-job-claimed",
            downloadUrl = "/api/device-sync/jobs/job-claimed/download",
            attemptNumber = 1,
            createdAt = "2026-06-11T09:15:00Z"
        )
        whenever(mockApi.claimDeviceSyncJobs(eq("token-123"), any())).thenReturn(
            ClaimDeviceSyncJobsResponse(
                leaseId = "lease-claimed",
                leaseExpiresAt = "2026-06-11T10:15:00Z",
                remainingPendingCount = 0,
                jobs = listOf(claimedJob)
            ),
            ClaimDeviceSyncJobsResponse(
                leaseId = "lease-empty",
                leaseExpiresAt = "2026-06-11T10:16:00Z",
                remainingPendingCount = 0,
                jobs = emptyList()
            )
        )
        whenever(mockLedger.get("job-claimed")).thenReturn(null)
        val responseBody = mock(okhttp3.ResponseBody::class.java)
        val inputStream = java.io.ByteArrayInputStream(byteArrayOf(1, 2, 3))
        whenever(responseBody.byteStream()).thenReturn(inputStream)
        whenever(mockApi.downloadDeviceSyncJob("token-123", "lease-claimed", "job-claimed")).thenReturn(responseBody)
        whenever(
            mockImporter.importMedia(
                eq(claimedJob.fileName),
                eq(claimedJob.mimeType),
                any(),
                eq(claimedJob.sizeBytes),
                any()
            )
        ).thenReturn("content://media/claimed")

        val repository = createRepository()

        assertTrue(repository.syncPendingJobs(workerRunId = "worker-run-1"))

        verify(mockSettingsStore).saveLastSuccessfulSyncAt(any())
    }
}
