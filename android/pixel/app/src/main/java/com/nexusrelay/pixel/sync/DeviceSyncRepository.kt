package com.nexusrelay.pixel.sync

import android.content.Context
import android.net.Uri
import android.util.Log
import com.nexusrelay.pixel.BuildConfig
import com.nexusrelay.pixel.api.ApiClientFactory
import com.nexusrelay.pixel.api.ConfirmDeviceSyncJobRequest
import com.nexusrelay.pixel.api.FailDeviceSyncJobRequest
import com.nexusrelay.pixel.api.NexusRelayApi
import com.nexusrelay.pixel.auth.DeviceTokenStore
import com.nexusrelay.pixel.media.MediaStoreImporter
import com.nexusrelay.pixel.storage.AppSettingsStore
import com.nexusrelay.pixel.storage.LocalSyncLedger
import com.nexusrelay.pixel.storage.LocalSyncRecord
import com.nexusrelay.pixel.storage.LocalSyncStatus
import kotlinx.coroutines.flow.first
import java.io.IOException
import retrofit2.HttpException

internal class DeviceSyncRepository(
    private val context: Context,
    private val appSettingsStore: AppSettingsStore = AppSettingsStore(context),
    private val deviceTokenStore: DeviceTokenStore = DeviceTokenStore(context),
    private val ledger: LocalSyncLedger = LocalSyncLedger(context),
    private val mediaStoreImporter: MediaStoreImporter = MediaStoreImporter(context),
    private val apiProvider: (String) -> NexusRelayApi = { baseUrl -> ApiClientFactory.create(baseUrl, debugLoggingEnabled = BuildConfig.DEBUG) }
) {
    private val tag = "DeviceSyncRepository"

    companion object {
        private const val STALE_STATUS_TIMEOUT_MS = 60L * 60L * 1000L
        private const val MAX_CONFIRMATION_RETRIES = 4
        private const val DOWNLOADING_TIMEOUT_MESSAGE = "Download stalled for over 1 hour before import completed"
        private const val QUEUED_TIMEOUT_MESSAGE = "Sync timed out before download started"
        private const val CONFIRMATION_TIMEOUT_MESSAGE = "Sync confirmation timed out after 1 hour"
    }

    private fun hasTimedOut(record: LocalSyncRecord, now: Long): Boolean {
        return now - record.statusEnteredAt >= STALE_STATUS_TIMEOUT_MS
    }

    private fun hasConfirmationBudget(record: LocalSyncRecord, now: Long): Boolean {
        return !hasTimedOut(record, now) && record.retryCount < MAX_CONFIRMATION_RETRIES
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
        if (isNetworkOrBackendFailure(e)) {
            if (e is IOException) {
                throw e
            } else {
                throw IOException("Retriable network/backend failure: ${e.message}", e)
            }
        }
    }

    private fun shouldPreserveConfirmationState(status: LocalSyncStatus?): Boolean {
        return status == LocalSyncStatus.ConfirmPending || status == LocalSyncStatus.Imported
    }

    private suspend fun reportFailure(
        api: NexusRelayApi,
        deviceToken: String,
        jobId: String,
        error: String
    ) {
        try {
            api.fail(deviceToken, jobId, FailDeviceSyncJobRequest(error))
            ledger.markFailureReported(jobId)
        } catch (failEx: Exception) {
            Log.e(tag, "Failed to report job failure to backend for job $jobId", failEx)
        }
    }

    private suspend fun reportUnreportedFailures(
        api: NexusRelayApi,
        deviceToken: String
    ) {
        val records = ledger.listUnreportedFailures()
        for (record in records) {
            val error = record.lastError ?: "Local sync failed"
            reportFailure(api, deviceToken, record.jobId, error)
        }
    }

    private suspend fun recoverInterruptedDownloads(
        api: NexusRelayApi,
        deviceToken: String,
        now: Long
    ) {
        val interruptedRecords = ledger.listByStatuses(LocalSyncStatus.Downloading)
        for (record in interruptedRecords) {
            if (hasTimedOut(record, now)) {
                ledger.markFailed(record.jobId, DOWNLOADING_TIMEOUT_MESSAGE)
                reportFailure(api, deviceToken, record.jobId, DOWNLOADING_TIMEOUT_MESSAGE)
            }
        }
    }

    private suspend fun failOrphanedQueuedRecords(
        api: NexusRelayApi,
        deviceToken: String,
        pendingJobIds: Set<String>,
        now: Long
    ) {
        val queuedRecords = ledger.listByStatuses(LocalSyncStatus.Queued)
        for (record in queuedRecords) {
            if (record.jobId !in pendingJobIds && hasTimedOut(record, now)) {
                ledger.markFailed(record.jobId, QUEUED_TIMEOUT_MESSAGE)
                reportFailure(api, deviceToken, record.jobId, QUEUED_TIMEOUT_MESSAGE)
            }
        }
    }

    private suspend fun retryLocalConfirmation(
        api: NexusRelayApi,
        deviceToken: String,
        record: LocalSyncRecord
    ): Boolean? {
        val localUri = record.localUri ?: return null
        val now = System.currentTimeMillis()

        return try {
            api.confirm(deviceToken, record.jobId, ConfirmDeviceSyncJobRequest(localUri, record.sizeBytes))
            ledger.markConfirmed(record.jobId)
            true
        } catch (e: Exception) {
            Log.e(tag, "Re-confirming job ${record.jobId} failed, will retry later", e)
            val errorMsg = e.localizedMessage ?: "Terminal confirmation error"

            if (isNetworkOrBackendFailure(e) && hasConfirmationBudget(record, now)) {
                ledger.recordRetriableFailure(record.jobId, errorMsg, now)
                throwOrPropagateIfRetriable(e)
                return false // defensive: should not reach here for network errors
            }

            val finalMessage = if (isNetworkOrBackendFailure(e) && hasTimedOut(record, now)) {
                CONFIRMATION_TIMEOUT_MESSAGE
            } else {
                errorMsg
            }
            ledger.markFailed(record.jobId, finalMessage)
            reportFailure(api, deviceToken, record.jobId, finalMessage)
            false
        }
    }

    suspend fun syncPendingJobs(): Boolean {
        val backendUrl = appSettingsStore.backendBaseUrlFlow.first()
        val deviceToken = deviceTokenStore.getDeviceToken()

        if (backendUrl.isNullOrBlank() || deviceToken.isNullOrBlank()) {
            Log.e(tag, "Sync skipped: Backend URL or Device Token is not configured.")
            return false
        }

        val api = apiProvider(backendUrl)
        val now = System.currentTimeMillis()
        reportUnreportedFailures(api, deviceToken)
        recoverInterruptedDownloads(api, deviceToken, now)
        val pendingJobs = try {
            api.pendingJobs(deviceToken)
        } catch (e: Exception) {
            Log.e(tag, "Failed to fetch pending jobs", e)
            throwOrPropagateIfRetriable(e)
            throw e
        }
        failOrphanedQueuedRecords(api, deviceToken, pendingJobs.map { it.jobId }.toSet(), now)

        var allSucceeded = true

        val locallyHandledJobIds = mutableSetOf<String>()
        val localConfirmations = ledger.listByStatuses(
            LocalSyncStatus.ConfirmPending,
            LocalSyncStatus.Imported
        )
        for (record in localConfirmations) {
            val confirmationSucceeded = retryLocalConfirmation(api, deviceToken, record) ?: continue
            locallyHandledJobIds += record.jobId
            if (!confirmationSucceeded) {
                allSucceeded = false
            }
        }

        for (job in pendingJobs) {
            if (job.jobId in locallyHandledJobIds) {
                continue
            }

            var ledgerRecord = ledger.get(job.jobId)
            if (ledgerRecord == null) {
                ledgerRecord = LocalSyncRecord(
                    jobId = job.jobId,
                    mediaId = job.mediaId,
                    fileName = job.fileName,
                    mimeType = job.mimeType,
                    sizeBytes = job.sizeBytes,
                    sha256 = job.sha256,
                    status = LocalSyncStatus.Queued,
                    localUri = null,
                    lastAttemptAt = System.currentTimeMillis(),
                    lastError = null
                )
                ledger.upsert(ledgerRecord)
            }

            if (ledgerRecord.status == LocalSyncStatus.Confirmed) {
                continue
            }

            if (ledgerRecord.status == LocalSyncStatus.ConfirmPending || ledgerRecord.status == LocalSyncStatus.Imported) {
                val confirmationSucceeded = retryLocalConfirmation(api, deviceToken, ledgerRecord)
                if (confirmationSucceeded != null) {
                    if (!confirmationSucceeded) {
                        allSucceeded = false
                    }
                    continue
                }
            }

            var confirmationPending = false
            try {
                api.markDownloading(deviceToken, job.jobId)
                ledger.markDownloading(job.jobId)

                val responseBody = api.downloadJob(deviceToken, job.jobId)
                val inputStream = responseBody.byteStream()

                val localUri = mediaStoreImporter.importMedia(
                    fileName = job.fileName,
                    mimeType = job.mimeType,
                    inputStream = inputStream,
                    sizeBytes = job.sizeBytes
                )

                ledger.markConfirmPending(job.jobId, localUri)
                confirmationPending = true

                api.confirm(deviceToken, job.jobId, ConfirmDeviceSyncJobRequest(localUri, job.sizeBytes))

                ledger.markConfirmed(job.jobId)

            } catch (e: Exception) {
                Log.e(tag, "Failed to sync job ${job.jobId}", e)

                val errorMsg = e.localizedMessage ?: "Unknown error"
                val nowVal = System.currentTimeMillis()
                val currentRecord = ledger.get(job.jobId)
                val currentStatus = currentRecord?.status
                val inConfirmationRecovery = confirmationPending || shouldPreserveConfirmationState(currentStatus)

                if (!inConfirmationRecovery) {
                    ledger.markFailed(job.jobId, errorMsg)
                    reportFailure(api, deviceToken, job.jobId, errorMsg)
                    throwOrPropagateIfRetriable(e)
                    allSucceeded = false
                    continue
                }

                if (isNetworkOrBackendFailure(e) && currentRecord != null && hasConfirmationBudget(currentRecord, nowVal)) {
                    ledger.recordRetriableFailure(job.jobId, errorMsg, nowVal)
                    throwOrPropagateIfRetriable(e)
                    continue // defensive: should not reach here for network errors
                }

                val finalMessage = if (currentRecord != null && hasTimedOut(currentRecord, nowVal)) {
                    CONFIRMATION_TIMEOUT_MESSAGE
                } else {
                    errorMsg
                }
                ledger.markFailed(job.jobId, finalMessage)
                reportFailure(api, deviceToken, job.jobId, finalMessage)
                allSucceeded = false
                continue
            }
        }

        if (allSucceeded && pendingJobs.isNotEmpty()) {
            appSettingsStore.saveLastSuccessfulSyncAt(System.currentTimeMillis())
        }

        try {
            cleanUpLocalFiles()
        } catch (e: Exception) {
            Log.e(tag, "Failed to run cleanUpLocalFiles", e)
        }

        return allSucceeded
    }

    suspend fun cleanUpLocalFiles() {
        val autoDeleteEnabled = appSettingsStore.autoDeleteEnabledFlow.first()
        if (!autoDeleteEnabled) {
            return
        }

        val delayMinutes = appSettingsStore.autoDeleteDelayMinutesFlow.first()
        val delayMillis = delayMinutes * 60L * 1000L
        val thresholdTime = System.currentTimeMillis() - delayMillis

        val confirmedRecords = ledger.listByStatuses(LocalSyncStatus.Confirmed)
            .filter { it.lastAttemptAt <= thresholdTime }

        deleteLocalFiles(confirmedRecords)
    }

    suspend fun cleanUpSpaceNow(): CleanupSpaceResult {
        val confirmedRecords = ledger.listByStatuses(LocalSyncStatus.Confirmed)
        return deleteLocalFiles(confirmedRecords)
    }

    suspend fun clearHistory() {
        ledger.clearHistory()
    }

    suspend fun retryFailedJob(jobId: String): Boolean {
        val record = ledger.get(jobId) ?: return false
        if (record.status != LocalSyncStatus.Failed) {
            return false
        }
        ledger.markQueued(jobId)
        return true
    }

    suspend fun resetLedgerIfSafe(): Boolean {
        if (ledger.hasActiveRecords()) {
            return false
        }
        ledger.clear()
        return true
    }

    private suspend fun deleteLocalFiles(records: List<LocalSyncRecord>): CleanupSpaceResult {
        val resolver = context.contentResolver
        var deletedCount = 0
        var skippedCount = 0
        var failedCount = 0
        var freedBytes = 0L

        for (record in records) {
            if (record.isLocalDeleted || record.localUri.isNullOrBlank()) {
                skippedCount++
                continue
            }

            try {
                val uri = Uri.parse(record.localUri)
                Log.d(tag, "Deleting local file: ${record.fileName} (URI: ${record.localUri})")
                val deletedRows = resolver.delete(uri, null, null)
                if (deletedRows > 0) {
                    deletedCount++
                    freedBytes += record.sizeBytes
                    ledger.markLocalDeleted(record.jobId)
                } else {
                    skippedCount++
                    ledger.markLocalDeleted(record.jobId)
                    Log.w(tag, "Local file not deleted or already missing: ${record.fileName}")
                }
            } catch (e: SecurityException) {
                failedCount++
                Log.e(tag, "SecurityException deleting local file ${record.fileName}: ${e.message}", e)
            } catch (e: Exception) {
                if (e.message?.contains("does not exist") == true || e is java.io.FileNotFoundException) {
                    skippedCount++
                    ledger.markLocalDeleted(record.jobId)
                } else {
                    failedCount++
                    Log.e(tag, "Error deleting local file ${record.fileName}: ${e.message}", e)
                }
            }
        }

        return CleanupSpaceResult(
            scannedCount = records.size,
            deletedCount = deletedCount,
            skippedCount = skippedCount,
            failedCount = failedCount,
            freedBytes = freedBytes
        )
    }
}
