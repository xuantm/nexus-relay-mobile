package com.nexusrelay.pixel.sync

import android.util.Log
import com.nexusrelay.pixel.api.ClaimDeviceSyncJobsRequest
import com.nexusrelay.pixel.api.ClaimDeviceSyncJobsResponse
import com.nexusrelay.pixel.api.ConfirmDeviceSyncJobRequest
import com.nexusrelay.pixel.api.DeviceSyncClaimedJobDto
import com.nexusrelay.pixel.api.DeviceSyncHeartbeatRequest
import com.nexusrelay.pixel.api.FailDeviceSyncJobRequest
import com.nexusrelay.pixel.api.NexusRelayApi
import com.nexusrelay.pixel.media.MediaImporter
import com.nexusrelay.pixel.storage.LocalSyncLedger
import com.nexusrelay.pixel.storage.LocalSyncRecord
import com.nexusrelay.pixel.storage.LocalSyncStatus
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.supervisorScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import java.io.IOException
import retrofit2.HttpException

internal data class SyncSessionResult(
    val allSucceeded: Boolean,
    val claimedJobCount: Int,
    val continuationEnqueued: Boolean
)

internal class SyncSessionRunner(
    private val api: NexusRelayApi,
    private val deviceToken: String,
    private val ledger: LocalSyncLedger,
    private val mediaStoreImporter: MediaImporter,
    private val workerRunId: String,
    private val clientVersion: String?,
    private val maxClaimLimit: Int = DEFAULT_CLAIM_LIMIT,
    private val leaseSeconds: Int = DEFAULT_LEASE_SECONDS,
    private val maxParallelJobs: Int = DEFAULT_MAX_PARALLEL_JOBS,
    private val downloadHeartbeatIntervalMillis: Long = DEFAULT_DOWNLOAD_HEARTBEAT_INTERVAL_MILLIS,
    private val jobProcessingDispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val maxRunMillis: Long = DEFAULT_MAX_RUN_MILLIS,
    private val nowProvider: () -> Long = System::currentTimeMillis,
    private val enqueueContinuation: suspend () -> Unit = {}
) {
    private val tag = "SyncSessionRunner"

    suspend fun run(): SyncSessionResult {
        val startedAt = nowProvider()
        var allSucceeded = true
        var claimedJobCount = 0
        var continuationEnqueued = false

        while (true) {
            val claimResponse = api.claimDeviceSyncJobs(
                deviceToken,
                ClaimDeviceSyncJobsRequest(
                    workerRunId = workerRunId,
                    limit = maxClaimLimit,
                    leaseSeconds = leaseSeconds,
                    clientVersion = clientVersion
                )
            )

            if (claimResponse.jobs.isEmpty()) {
                break
            }

            claimedJobCount += claimResponse.jobs.size

            val batchResult = processClaimedJobs(claimResponse)
            if (!batchResult.allSucceeded) {
                allSucceeded = false
            }
            batchResult.retriableFailure?.let { throw it }

            if (claimResponse.remainingPendingCount > 0 && nowProvider() - startedAt >= maxRunMillis) {
                enqueueContinuation()
                continuationEnqueued = true
                break
            }
        }

        return SyncSessionResult(
            allSucceeded = allSucceeded,
            claimedJobCount = claimedJobCount,
            continuationEnqueued = continuationEnqueued
        )
    }

    private suspend fun processClaimedJobs(
        claimResponse: ClaimDeviceSyncJobsResponse
    ): BatchProcessingResult = supervisorScope {
        val semaphore = Semaphore(maxParallelJobs.coerceAtLeast(1))
        val outcomes = claimResponse.jobs.map { job ->
            async(jobProcessingDispatcher) {
                semaphore.withPermit {
                    try {
                        JobProcessingResult(
                            succeeded = processClaimedJob(job, claimResponse),
                            retriableFailure = null
                        )
                    } catch (e: IOException) {
                        JobProcessingResult(
                            succeeded = false,
                            retriableFailure = e
                        )
                    }
                }
            }
        }.awaitAll()

        BatchProcessingResult(
            allSucceeded = outcomes.all { it.succeeded },
            retriableFailure = outcomes.firstNotNullOfOrNull { it.retriableFailure }
        )
    }

    private suspend fun processClaimedJob(
        job: DeviceSyncClaimedJobDto,
        claimResponse: ClaimDeviceSyncJobsResponse
    ): Boolean {
        seedLedgerRecord(job)
        ledger.markClaimed(job.jobId, claimResponse.leaseId, workerRunId)
        heartbeat(job.jobId, claimResponse.leaseId, "Claimed", 0L, job.sizeBytes)

        var importedUri: String? = null
        var lastDownloadHeartbeatAt: Long? = null
        var lastDownloadProgressPersistedAt: Long? = null
        try {
            api.downloadDeviceSyncJob(deviceToken, claimResponse.leaseId, job.jobId).use { responseBody ->
                importedUri = mediaStoreImporter.importMedia(
                    fileName = job.fileName,
                    mimeType = job.mimeType,
                    inputStream = responseBody.byteStream(),
                    sizeBytes = job.sizeBytes,
                    onBytesCopied = { copied ->
                        val boundedCopied = copied.coerceAtMost(job.sizeBytes)
                        val now = nowProvider()
                        val shouldPersistProgress = lastDownloadProgressPersistedAt == null ||
                            now - checkNotNull(lastDownloadProgressPersistedAt) >= downloadHeartbeatIntervalMillis
                        if (shouldPersistProgress) {
                            ledger.markProgress(job.jobId, "Downloading", boundedCopied, job.sizeBytes)
                            lastDownloadProgressPersistedAt = now
                        }
                        val shouldSendHeartbeat = lastDownloadHeartbeatAt == null ||
                            now - checkNotNull(lastDownloadHeartbeatAt) >= downloadHeartbeatIntervalMillis
                        if (shouldSendHeartbeat) {
                            heartbeat(job.jobId, claimResponse.leaseId, "Downloading", boundedCopied, job.sizeBytes)
                            lastDownloadHeartbeatAt = now
                        }
                    }
                )
            }

            val resolvedImportedUri = checkNotNull(importedUri)
            ledger.markProgress(job.jobId, "Downloading", job.sizeBytes, job.sizeBytes)
            ledger.markImported(job.jobId, resolvedImportedUri)
            heartbeat(job.jobId, claimResponse.leaseId, "Importing", job.sizeBytes, job.sizeBytes)
            ledger.markConfirmPending(job.jobId, resolvedImportedUri)
            heartbeat(job.jobId, claimResponse.leaseId, "Confirming", job.sizeBytes, job.sizeBytes)

            api.confirmDeviceSyncJob(
                deviceToken,
                job.jobId,
                ConfirmDeviceSyncJobRequest(
                    importedUri = resolvedImportedUri,
                    importedSizeBytes = job.sizeBytes,
                    leaseId = claimResponse.leaseId,
                    workerRunId = workerRunId
                )
            )
            ledger.markConfirmed(job.jobId)
            return true
        } catch (e: Exception) {
            Log.e(tag, "Failed to sync claimed job ${job.jobId}", e)
            val error = e.localizedMessage ?: "Unknown sync error"
            val retryable = isNetworkOrBackendFailure(e)
            val hasLocalImport = importedUri != null

            if (hasLocalImport && retryable) {
                ledger.recordRetriableFailure(job.jobId, error, nowProvider())
                throwOrPropagateIfRetriable(e)
                return false
            }

            ledger.markFailed(job.jobId, error)
            reportFailure(
                jobId = job.jobId,
                leaseId = claimResponse.leaseId,
                workerRunId = workerRunId,
                error = error,
                retryable = retryable
            )
            throwOrPropagateIfRetriable(e)
            return false
        }
    }

    private suspend fun seedLedgerRecord(job: DeviceSyncClaimedJobDto) {
        if (ledger.get(job.jobId) != null) {
            return
        }

        ledger.upsert(
            LocalSyncRecord(
                jobId = job.jobId,
                mediaId = job.mediaId,
                fileName = job.fileName,
                mimeType = job.mimeType,
                sizeBytes = job.sizeBytes,
                sha256 = job.sha256,
                status = LocalSyncStatus.Queued,
                localUri = null,
                lastAttemptAt = nowProvider(),
                lastError = null,
                totalBytes = job.sizeBytes,
                stage = "Queued"
            )
        )
    }

    private suspend fun heartbeat(
        jobId: String,
        leaseId: String,
        stage: String,
        progressBytes: Long,
        totalBytes: Long?
    ) {
        api.heartbeatDeviceSyncJob(
            deviceToken,
            jobId,
            DeviceSyncHeartbeatRequest(
                leaseId = leaseId,
                workerRunId = workerRunId,
                stage = stage,
                progressBytes = progressBytes,
                totalBytes = totalBytes,
                leaseSeconds = leaseSeconds
            )
        )
    }

    private suspend fun reportFailure(
        jobId: String,
        leaseId: String?,
        workerRunId: String?,
        error: String,
        retryable: Boolean
    ) {
        try {
            api.failDeviceSyncJob(
                deviceToken,
                jobId,
                FailDeviceSyncJobRequest(
                    error = error,
                    retryable = retryable,
                    leaseId = leaseId,
                    workerRunId = workerRunId
                )
            )
            ledger.markFailureReported(jobId, nowProvider())
        } catch (failEx: Exception) {
            Log.e(tag, "Failed to report claimed-job failure for $jobId", failEx)
        }
    }

    private fun isNetworkOrBackendFailure(e: Throwable): Boolean {
        if (e is IOException) {
            return true
        }
        if (e is HttpException) {
            val code = e.code()
            return code >= 500 || code == 408 || code == 429
        }
        return false
    }

    private fun throwOrPropagateIfRetriable(e: Throwable) {
        if (!isNetworkOrBackendFailure(e)) {
            return
        }

        if (e is IOException) {
            throw e
        }

        throw IOException("Retriable network/backend failure: ${e.message}", e)
    }

    private companion object {
        private const val DEFAULT_CLAIM_LIMIT = 25
        private const val DEFAULT_LEASE_SECONDS = 900
        private const val DEFAULT_MAX_PARALLEL_JOBS = 3
        private const val DEFAULT_DOWNLOAD_HEARTBEAT_INTERVAL_MILLIS = 3_000L
        private const val DEFAULT_MAX_RUN_MILLIS = 25L * 60L * 1000L
    }
}

private data class JobProcessingResult(
    val succeeded: Boolean,
    val retriableFailure: IOException?
)

private data class BatchProcessingResult(
    val allSucceeded: Boolean,
    val retriableFailure: IOException?
)
