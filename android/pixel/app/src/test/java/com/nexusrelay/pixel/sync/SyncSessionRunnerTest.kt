package com.nexusrelay.pixel.sync

import com.nexusrelay.pixel.api.ClaimDeviceSyncJobsRequest
import com.nexusrelay.pixel.api.ClaimDeviceSyncJobsResponse
import com.nexusrelay.pixel.api.ConfirmDeviceSyncJobRequest
import com.nexusrelay.pixel.api.DeviceSyncClaimedJobDto
import com.nexusrelay.pixel.api.DeviceSyncHeartbeatRequest
import com.nexusrelay.pixel.api.DeviceSyncHeartbeatResponse
import com.nexusrelay.pixel.api.NexusRelayApi
import com.nexusrelay.pixel.media.MediaImporter
import com.nexusrelay.pixel.storage.LocalSyncLedger
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.kotlin.any
import org.mockito.kotlin.argThat
import org.mockito.kotlin.eq
import org.mockito.kotlin.mock
import org.mockito.kotlin.never
import org.mockito.kotlin.times
import org.mockito.kotlin.verify
import org.mockito.kotlin.whenever
import java.io.ByteArrayInputStream
import java.io.IOException
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.Executors
import retrofit2.HttpException
import retrofit2.Response

class SyncSessionRunnerTest {

    private val api = mock<NexusRelayApi>()
    private val ledger = mock<LocalSyncLedger>()
    private val importer = mock<MediaImporter>()

    private fun claimedJob(jobId: String = "job-1"): DeviceSyncClaimedJobDto {
        return DeviceSyncClaimedJobDto(
            jobId = jobId,
            mediaId = "media-$jobId",
            fileName = "file-$jobId.jpg",
            mimeType = "image/jpeg",
            mediaType = "Image",
            sizeBytes = 1024L,
            sha256 = "sha-$jobId",
            downloadUrl = "/api/device-sync/jobs/$jobId/download",
            attemptNumber = 1,
            createdAt = "2026-06-11T09:15:00Z"
        )
    }

    @Test
    fun runClaimsUntilEmptyAndProcessesClaimedJobs() = runTest {
        val job = claimedJob()
        whenever(api.claimDeviceSyncJobs(eq("token-123"), any())).thenReturn(
            ClaimDeviceSyncJobsResponse(
                leaseId = "lease-1",
                leaseExpiresAt = "2026-06-11T10:15:00Z",
                remainingPendingCount = 0,
                jobs = listOf(job)
            ),
            ClaimDeviceSyncJobsResponse(
                leaseId = "lease-empty",
                leaseExpiresAt = "2026-06-11T10:16:00Z",
                remainingPendingCount = 0,
                jobs = emptyList()
            )
        )
        whenever(api.heartbeatDeviceSyncJob(eq("token-123"), eq("job-1"), any())).thenReturn(
            DeviceSyncHeartbeatResponse("2026-06-11T10:15:30Z")
        )
        val responseBody = mock<ResponseBody>()
        whenever(responseBody.byteStream()).thenReturn(ByteArrayInputStream(ByteArray(1024) { 1 }))
        whenever(api.downloadDeviceSyncJob("token-123", "lease-1", "job-1")).thenReturn(responseBody)
        whenever(
            importer.importMedia(
                eq(job.fileName),
                eq(job.mimeType),
                any(),
                eq(job.sizeBytes),
                any()
            )
        ).thenAnswer { invocation ->
            val onBytesCopied = invocation.getArgument<suspend (Long) -> Unit>(4)
            runBlocking {
                onBytesCopied(256L)
                onBytesCopied(768L)
            }
            "content://media/job-1"
        }

        val runner = SyncSessionRunner(
            api = api,
            deviceToken = "token-123",
            ledger = ledger,
            mediaStoreImporter = importer,
            workerRunId = "worker-1",
            clientVersion = "1.0"
        )

        val result = runner.run()

        assertTrue(result.allSucceeded)
        assertEquals(1, result.claimedJobCount)
        verify(api, times(2)).claimDeviceSyncJobs(
            eq("token-123"),
            eq(
                ClaimDeviceSyncJobsRequest(
                    workerRunId = "worker-1",
                    limit = 25,
                    leaseSeconds = 900,
                    clientVersion = "1.0"
                )
            )
        )
        verify(ledger).markClaimed(eq("job-1"), eq("lease-1"), eq("worker-1"), any())
        verify(ledger).markProgress(eq("job-1"), eq("Downloading"), eq(256L), eq(1024L), any())
        verify(ledger).markProgress(eq("job-1"), eq("Downloading"), eq(1024L), eq(1024L), any())
        verify(api).confirmDeviceSyncJob(
            eq("token-123"),
            eq("job-1"),
            eq(
                ConfirmDeviceSyncJobRequest(
                    importedUri = "content://media/job-1",
                    importedSizeBytes = 1024L,
                    leaseId = "lease-1",
                    workerRunId = "worker-1"
                )
            )
        )
    }

    @Test
    fun runEnqueuesContinuationWhenBudgetIsReachedAndBacklogRemains() = runTest {
        val job = claimedJob("job-2")
        whenever(api.claimDeviceSyncJobs(eq("token-123"), any())).thenReturn(
            ClaimDeviceSyncJobsResponse(
                leaseId = "lease-2",
                leaseExpiresAt = "2026-06-11T10:15:00Z",
                remainingPendingCount = 8,
                jobs = listOf(job)
            )
        )
        whenever(api.heartbeatDeviceSyncJob(eq("token-123"), eq("job-2"), any())).thenReturn(
            DeviceSyncHeartbeatResponse("2026-06-11T10:15:30Z")
        )
        val responseBody = mock<ResponseBody>()
        whenever(responseBody.byteStream()).thenReturn(ByteArrayInputStream(ByteArray(16) { 1 }))
        whenever(api.downloadDeviceSyncJob("token-123", "lease-2", "job-2")).thenReturn(responseBody)
        whenever(
            importer.importMedia(
                eq(job.fileName),
                eq(job.mimeType),
                any(),
                eq(job.sizeBytes),
                any()
            )
        ).thenReturn("content://media/job-2")

        var continuationEnqueued = 0
        val timestamps = ArrayDeque(listOf(0L, 0L, 60_000L))
        val runner = SyncSessionRunner(
            api = api,
            deviceToken = "token-123",
            ledger = ledger,
            mediaStoreImporter = importer,
            workerRunId = "worker-2",
            clientVersion = "1.0",
            maxRunMillis = 1L,
            nowProvider = { timestamps.removeFirst() },
            enqueueContinuation = { continuationEnqueued++ }
        )

        val result = runner.run()

        assertEquals(1, continuationEnqueued)
        assertTrue(result.continuationEnqueued)
    }

    @Test
    fun runPropagatesRetriableClaimFailures() = runTest {
        whenever(api.claimDeviceSyncJobs(eq("token-123"), any())).thenAnswer {
            throw IOException("claim failed")
        }

        val runner = SyncSessionRunner(
            api = api,
            deviceToken = "token-123",
            ledger = ledger,
            mediaStoreImporter = importer,
            workerRunId = "worker-3",
            clientVersion = "1.0"
        )

        var threw = false
        try {
            runner.run()
        } catch (expected: IOException) {
            threw = true
        }

        assertTrue(threw)
    }

    @Test
    fun runPersistsImportedUriBeforeRetriablePostImportHeartbeatFailure() = runTest {
        val job = claimedJob("job-heartbeat")
        whenever(api.claimDeviceSyncJobs(eq("token-123"), any())).thenReturn(
            ClaimDeviceSyncJobsResponse(
                leaseId = "lease-heartbeat",
                leaseExpiresAt = "2026-06-11T10:15:00Z",
                remainingPendingCount = 0,
                jobs = listOf(job)
            )
        )
        whenever(
            api.heartbeatDeviceSyncJob(
                eq("token-123"),
                eq("job-heartbeat"),
                argThat { stage == "Importing" }
            )
        ).thenThrow(
            HttpException(
                Response.error<Any>(
                    503,
                    "import heartbeat failed".toResponseBody("text/plain".toMediaType())
                )
            )
        )
        whenever(api.heartbeatDeviceSyncJob(eq("token-123"), eq("job-heartbeat"), any())).thenReturn(
            DeviceSyncHeartbeatResponse("2026-06-11T10:15:30Z")
        )
        val responseBody = mock<ResponseBody>()
        whenever(responseBody.byteStream()).thenReturn(ByteArrayInputStream(ByteArray(16) { 1 }))
        whenever(api.downloadDeviceSyncJob("token-123", "lease-heartbeat", "job-heartbeat")).thenReturn(responseBody)
        whenever(
            importer.importMedia(
                eq(job.fileName),
                eq(job.mimeType),
                any(),
                eq(job.sizeBytes),
                any()
            )
        ).thenReturn("content://media/job-heartbeat")

        val runner = SyncSessionRunner(
            api = api,
            deviceToken = "token-123",
            ledger = ledger,
            mediaStoreImporter = importer,
            workerRunId = "worker-heartbeat",
            clientVersion = "1.0"
        )

        var threw = false
        try {
            runner.run()
        } catch (expected: IOException) {
            threw = true
        }

        assertTrue(threw)
        verify(ledger).markImported("job-heartbeat", "content://media/job-heartbeat")
        verify(ledger, never()).markFailed(eq("job-heartbeat"), any())
        verify(ledger).recordRetriableFailure(eq("job-heartbeat"), eq("HTTP 503 Response.error()"), any())
    }

    @Test
    fun runThrottlesDownloadHeartbeatsToOncePerThreeSeconds() = runTest {
        val job = claimedJob("job-throttle")
        whenever(api.claimDeviceSyncJobs(eq("token-123"), any())).thenReturn(
            ClaimDeviceSyncJobsResponse(
                leaseId = "lease-throttle",
                leaseExpiresAt = "2026-06-11T10:15:00Z",
                remainingPendingCount = 0,
                jobs = listOf(job)
            ),
            ClaimDeviceSyncJobsResponse(
                leaseId = "lease-empty",
                leaseExpiresAt = "2026-06-11T10:16:00Z",
                remainingPendingCount = 0,
                jobs = emptyList()
            )
        )
        whenever(api.heartbeatDeviceSyncJob(eq("token-123"), eq("job-throttle"), any())).thenReturn(
            DeviceSyncHeartbeatResponse("2026-06-11T10:15:30Z")
        )
        val responseBody = mock<ResponseBody>()
        whenever(responseBody.byteStream()).thenReturn(ByteArrayInputStream(ByteArray(1024) { 1 }))
        whenever(api.downloadDeviceSyncJob("token-123", "lease-throttle", "job-throttle")).thenReturn(responseBody)

        val timestamps = ArrayDeque(
            listOf(
                0L,
                0L,
                1_000L,
                2_000L,
                2_999L,
                3_000L,
                3_001L,
                3_002L
            )
        )

        whenever(
            importer.importMedia(
                eq(job.fileName),
                eq(job.mimeType),
                any(),
                eq(job.sizeBytes),
                any()
            )
        ).thenAnswer { invocation ->
            val onBytesCopied = invocation.getArgument<suspend (Long) -> Unit>(4)
            runBlocking {
                onBytesCopied(128L)
                onBytesCopied(256L)
                onBytesCopied(512L)
                onBytesCopied(768L)
                onBytesCopied(1024L)
            }
            "content://media/job-throttle"
        }

        val runner = SyncSessionRunner(
            api = api,
            deviceToken = "token-123",
            ledger = ledger,
            mediaStoreImporter = importer,
            workerRunId = "worker-throttle",
            clientVersion = "1.0",
            nowProvider = { timestamps.removeFirst() }
        )

        runner.run()

        verify(api, times(4)).heartbeatDeviceSyncJob(eq("token-123"), eq("job-throttle"), any())
        verify(api).heartbeatDeviceSyncJob(
            eq("token-123"),
            eq("job-throttle"),
            argThat { stage == "Downloading" && progressBytes == 128L }
        )
        verify(ledger, times(2)).markProgress(eq("job-throttle"), eq("Downloading"), any(), eq(1024L), any())
        verify(ledger).markProgress(eq("job-throttle"), eq("Downloading"), eq(128L), eq(1024L), any())
        verify(ledger).markProgress(eq("job-throttle"), eq("Downloading"), eq(1024L), eq(1024L), any())
    }

    @Test
    fun runProcessesTwoClaimedJobsConcurrently() = runTest {
        val job1 = claimedJob("job-concurrent-1")
        val job2 = claimedJob("job-concurrent-2")
        whenever(api.claimDeviceSyncJobs(eq("token-123"), any())).thenReturn(
            ClaimDeviceSyncJobsResponse(
                leaseId = "lease-concurrent",
                leaseExpiresAt = "2026-06-11T10:15:00Z",
                remainingPendingCount = 0,
                jobs = listOf(job1, job2)
            ),
            ClaimDeviceSyncJobsResponse(
                leaseId = "lease-empty",
                leaseExpiresAt = "2026-06-11T10:16:00Z",
                remainingPendingCount = 0,
                jobs = emptyList()
            )
        )
        whenever(api.heartbeatDeviceSyncJob(eq("token-123"), any(), any())).thenReturn(
            DeviceSyncHeartbeatResponse("2026-06-11T10:15:30Z")
        )

        val responseBody1 = mock<ResponseBody>()
        val responseBody2 = mock<ResponseBody>()
        whenever(responseBody1.byteStream()).thenReturn(ByteArrayInputStream(ByteArray(16) { 1 }))
        whenever(responseBody2.byteStream()).thenReturn(ByteArrayInputStream(ByteArray(16) { 1 }))
        whenever(api.downloadDeviceSyncJob("token-123", "lease-concurrent", "job-concurrent-1")).thenReturn(responseBody1)
        whenever(api.downloadDeviceSyncJob("token-123", "lease-concurrent", "job-concurrent-2")).thenReturn(responseBody2)

        val currentInFlight = AtomicInteger(0)
        val maxInFlight = AtomicInteger(0)
        val dispatcher = Executors.newFixedThreadPool(2).asCoroutineDispatcher()
        val trackingImporter = object : MediaImporter {
            override suspend fun importMedia(
                fileName: String,
                mimeType: String,
                inputStream: java.io.InputStream,
                sizeBytes: Long,
                onBytesCopied: suspend (Long) -> Unit
            ): String {
                val inFlight = currentInFlight.incrementAndGet()
                maxInFlight.updateAndGet { currentMax -> maxOf(currentMax, inFlight) }
                delay(250)
                currentInFlight.decrementAndGet()
                return "content://media/$fileName"
            }
        }

        val result = try {
            val runner = SyncSessionRunner(
                api = api,
                deviceToken = "token-123",
                ledger = ledger,
                mediaStoreImporter = trackingImporter,
                workerRunId = "worker-concurrent",
                clientVersion = "1.0",
                jobProcessingDispatcher = dispatcher
            )
            runner.run()
        } finally {
            dispatcher.close()
        }

        assertTrue(result.allSucceeded)
        assertEquals(2, result.claimedJobCount)
        assertEquals(2, maxInFlight.get())
        verify(api).confirmDeviceSyncJob(eq("token-123"), eq("job-concurrent-1"), any())
        verify(api).confirmDeviceSyncJob(eq("token-123"), eq("job-concurrent-2"), any())
    }
}
