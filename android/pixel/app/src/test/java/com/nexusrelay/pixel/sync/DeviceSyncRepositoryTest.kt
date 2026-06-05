package com.nexusrelay.pixel.sync

import android.content.Context
import com.nexusrelay.pixel.api.DeviceSyncJobDto
import com.nexusrelay.pixel.api.NexusRelayApi
import com.nexusrelay.pixel.api.ConfirmDeviceSyncJobRequest
import com.nexusrelay.pixel.api.FailDeviceSyncJobRequest
import com.nexusrelay.pixel.auth.DeviceTokenStore
import com.nexusrelay.pixel.media.MediaStoreImporter
import com.nexusrelay.pixel.storage.AppSettingsStore
import com.nexusrelay.pixel.storage.LocalSyncLedger
import com.nexusrelay.pixel.storage.LocalSyncRecord
import com.nexusrelay.pixel.storage.LocalSyncStatus
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import okhttp3.ResponseBody
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.kotlin.any
import org.mockito.kotlin.eq
import org.mockito.kotlin.never
import org.mockito.kotlin.verify
import org.mockito.kotlin.whenever
import retrofit2.HttpException
import retrofit2.Response
import java.io.IOException

class DeviceSyncRepositoryTest {

    private val mockContext = mock(Context::class.java)
    private val mockSettingsStore = mock(AppSettingsStore::class.java)
    private val mockTokenStore = mock(DeviceTokenStore::class.java)
    private val mockLedger = mock(LocalSyncLedger::class.java)
    private val mockImporter = mock(MediaStoreImporter::class.java)
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
    }

    @Test
    fun testSyncPendingJobsWhenNotConfigured() = runTest {
        whenever(mockSettingsStore.backendBaseUrlFlow).thenReturn(flowOf(null))
        whenever(mockTokenStore.getDeviceToken()).thenReturn(null)

        val repository = createRepository()
        val result = repository.syncPendingJobs()
        assertFalse(result)
    }

    @Test
    fun testSyncPendingJobs_NetworkFailureDuringFetch_ThrowsIOException() = runTest {
        setupConfiguredMocks()
        whenever(mockApi.pendingJobs("token-123")).thenAnswer { throw IOException("Network error") }

        val repository = createRepository()
        var threw = false
        try {
            repository.syncPendingJobs()
        } catch (e: IOException) {
            threw = true
        }
        assertTrue("Expected IOException to be thrown", threw)
    }

    @Test
    fun testSyncPendingJobs_NetworkFailureDuringDownload_ThrowsIOException() = runTest {
        setupConfiguredMocks()
        val job = createSampleJobDto("job-1")
        whenever(mockApi.pendingJobs("token-123")).thenReturn(listOf(job))
        whenever(mockLedger.get("job-1")).thenReturn(null)
        whenever(mockApi.downloadJob(eq("token-123"), eq("job-1"))).thenAnswer { throw IOException("Download timed out") }

        val repository = createRepository()
        var threw = false
        try {
            repository.syncPendingJobs()
        } catch (e: IOException) {
            threw = true
        }
        assertTrue("Expected IOException to be thrown", threw)

        // Ledger status should NOT be Failed, since it is a retriable network error
        verify(mockLedger, never()).markFailed(eq("job-1"), any())
        verify(mockApi, never()).fail(any(), eq("job-1"), any())
    }

    @Test
    fun testSyncPendingJobs_HttpRetriableFailure_ThrowsIOException() = runTest {
        setupConfiguredMocks()
        val job = createSampleJobDto("job-2")
        whenever(mockApi.pendingJobs("token-123")).thenReturn(listOf(job))
        whenever(mockLedger.get("job-2")).thenReturn(null)

        val errorResponse = Response.error<Any>(503, ResponseBody.create(null, "Service Unavailable"))
        whenever(mockApi.markDownloading(eq("token-123"), eq("job-2"))).thenAnswer { throw HttpException(errorResponse) }

        val repository = createRepository()
        var threw = false
        try {
            repository.syncPendingJobs()
        } catch (e: IOException) {
            threw = true
        }
        assertTrue("Expected IOException to be thrown", threw)

        verify(mockLedger, never()).markFailed(eq("job-2"), any())
        verify(mockApi, never()).fail(any(), eq("job-2"), any())
    }

    @Test
    fun testSyncPendingJobs_TerminalJobFailure_CallsFailEndpointAndContinues() = runTest {
        setupConfiguredMocks()
        val job = createSampleJobDto("job-3")
        whenever(mockApi.pendingJobs("token-123")).thenReturn(listOf(job))
        whenever(mockLedger.get("job-3")).thenReturn(null)
        
        val mockResponseBody = mock(ResponseBody::class.java)
        val mockInputStream = mock(java.io.InputStream::class.java)
        whenever(mockResponseBody.byteStream()).thenReturn(mockInputStream)
        whenever(mockApi.downloadJob(eq("token-123"), eq("job-3"))).thenReturn(mockResponseBody)
        whenever(mockApi.markDownloading(any(), any())).thenAnswer {}
        whenever(mockImporter.importMedia(any(), any(), any(), eq(100L))).thenThrow(IllegalArgumentException("Unsupported media type"))
        whenever(mockApi.fail(any(), any(), any())).thenAnswer {}

        val repository = createRepository()
        val result = repository.syncPendingJobs()
        assertFalse(result)

        // Ledger should be marked failed and backend notified
        verify(mockLedger).markFailed(eq("job-3"), eq("Unsupported media type"))
        verify(mockApi).fail(eq("token-123"), eq("job-3"), eq(FailDeviceSyncJobRequest("Unsupported media type")))
    }

    @Test
    fun testSyncPendingJobs_ConfirmPendingJob_OnlyConfirmsWithoutRedownload() = runTest {
        setupConfiguredMocks()
        val job = createSampleJobDto("job-4")
        whenever(mockApi.pendingJobs("token-123")).thenReturn(listOf(job))
        
        // Ledger already has this job in ConfirmPending status
        val record = LocalSyncRecord(
            jobId = "job-4",
            mediaId = "media-4",
            fileName = "test.jpg",
            mimeType = "image/jpeg",
            sizeBytes = 100L,
            sha256 = null,
            status = LocalSyncStatus.ConfirmPending,
            localUri = "content://media/external/images/media/4",
            lastAttemptAt = 0L,
            lastError = null
        )
        whenever(mockLedger.get("job-4")).thenReturn(record)

        val repository = createRepository()
        val result = repository.syncPendingJobs()
        assertTrue(result)

        // Verifying it confirms directly
        verify(mockApi).confirm(
            eq("token-123"),
            eq("job-4"),
            eq(ConfirmDeviceSyncJobRequest("content://media/external/images/media/4", 100L))
        )
        verify(mockLedger).markConfirmed("job-4")
        
        // Ensure no downloading or importing occurs
        verify(mockApi, never()).downloadJob(any(), eq("job-4"))
        verify(mockImporter, never()).importMedia(any(), any(), any(), any())
    }

    @Test
    fun testSyncPendingJobs_ConfirmFailureRetriable_ThrowsIOExceptionAndPreservesConfirmPending() = runTest {
        setupConfiguredMocks()
        val job = createSampleJobDto("job-5")
        whenever(mockApi.pendingJobs("token-123")).thenReturn(listOf(job))
        
        val record = LocalSyncRecord(
            jobId = "job-5",
            mediaId = "media-5",
            fileName = "test.jpg",
            mimeType = "image/jpeg",
            sizeBytes = 100L,
            sha256 = null,
            status = LocalSyncStatus.ConfirmPending,
            localUri = "content://media/external/images/media/5",
            lastAttemptAt = 0L,
            lastError = null
        )
        whenever(mockLedger.get("job-5")).thenReturn(record)
        whenever(mockApi.confirm(eq("token-123"), eq("job-5"), any())).thenAnswer { throw IOException("Confirm timeout") }

        val repository = createRepository()
        var threw = false
        try {
            repository.syncPendingJobs()
        } catch (e: IOException) {
            threw = true
        }
        assertTrue("Expected IOException to be thrown", threw)

        // Status must remain ConfirmPending and not failed
        verify(mockLedger, never()).markFailed(eq("job-5"), any())
        verify(mockApi, never()).fail(any(), eq("job-5"), any())
    }
    
    @Test
    fun testSyncPendingJobs_NewJob_DownloadImportSucceed_ConfirmFailRetriable_ThrowsAndDoesNotMarkFailed() = runTest {
        setupConfiguredMocks()
        val job = createSampleJobDto("job-new-confirm-fail")
        whenever(mockApi.pendingJobs("token-123")).thenReturn(listOf(job))
        whenever(mockLedger.get("job-new-confirm-fail")).thenReturn(null)

        val mockResponseBody = mock(ResponseBody::class.java)
        val mockInputStream = mock(java.io.InputStream::class.java)
        whenever(mockResponseBody.byteStream()).thenReturn(mockInputStream)
        whenever(mockApi.downloadJob(eq("token-123"), eq("job-new-confirm-fail"))).thenReturn(mockResponseBody)
        whenever(mockApi.markDownloading(any(), any())).thenAnswer {}
        
        val localUri = "content://media/external/images/media/999"
        whenever(mockImporter.importMedia(eq(job.fileName), eq(job.mimeType), any(), eq(job.sizeBytes))).thenReturn(localUri)
        
        // Mock confirm to fail with retriable IOException
        whenever(mockApi.confirm(eq("token-123"), eq("job-new-confirm-fail"), any())).thenAnswer { throw IOException("Confirm connection dropped") }

        val repository = createRepository()
        var threw = false
        try {
            repository.syncPendingJobs()
        } catch (e: IOException) {
            threw = true
        }
        assertTrue("Expected IOException to be thrown", threw)

        // Verify ledger marked it as downloading, then confirm pending
        verify(mockLedger).upsert(any())
        verify(mockLedger).markDownloading(eq("job-new-confirm-fail"))
        verify(mockLedger).markConfirmPending(eq("job-new-confirm-fail"), eq(localUri))

        // But must NOT be marked failed locally, and fail endpoint must NOT be called
        verify(mockLedger, never()).markFailed(eq("job-new-confirm-fail"), any())
        verify(mockApi, never()).fail(any(), eq("job-new-confirm-fail"), any())
    }

    private fun createSampleJobDto(jobId: String): DeviceSyncJobDto {
        return DeviceSyncJobDto(
            jobId = jobId,
            mediaId = "media-$jobId",
            fileName = "file-$jobId.jpg",
            mimeType = "image/jpeg",
            mediaType = "Image",
            sizeBytes = 100L,
            sha256 = "sha256-$jobId",
            downloadUrl = "/api/device-sync/jobs/$jobId/download",
            createdAt = "2026-06-05T00:00:00Z"
        )
    }
}
