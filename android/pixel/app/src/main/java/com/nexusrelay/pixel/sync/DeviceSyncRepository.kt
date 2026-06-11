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
import com.nexusrelay.pixel.media.MediaImporter
import com.nexusrelay.pixel.media.MediaStoreImporter
import com.nexusrelay.pixel.storage.AppSettingsStore
import com.nexusrelay.pixel.storage.LocalSyncLedger
import com.nexusrelay.pixel.storage.LocalSyncRecord
import com.nexusrelay.pixel.storage.LocalSyncStatus
import kotlinx.coroutines.flow.first
import java.io.IOException
import java.util.UUID
import retrofit2.HttpException

internal class DeviceSyncRepository(
    private val context: Context,
    private val appSettingsStore: AppSettingsStore = AppSettingsStore(context),
    private val deviceTokenStore: DeviceTokenStore = DeviceTokenStore(context),
    private val ledger: LocalSyncLedger = LocalSyncLedger(context),
    private val mediaStoreImporter: MediaImporter = MediaStoreImporter(context),
    private val apiProvider: (String) -> NexusRelayApi = { baseUrl -> ApiClientFactory.create(baseUrl, debugLoggingEnabled = BuildConfig.DEBUG) }
) {
    private val tag = "DeviceSyncRepository"

    companion object {
        private const val STALE_STATUS_TIMEOUT_MS = 60L * 60L * 1000L
        private const val MAX_CONFIRMATION_RETRIES = 4
        private const val QUEUED_TIMEOUT_MESSAGE = "Sync timed out before download started"
        private const val DOWNLOADING_TIMEOUT_MESSAGE = "Download stalled for over 1 hour before import completed"
        private const val CONFIRMATION_TIMEOUT_MESSAGE = "Sync confirmation timed out after 1 hour"
    }

    private fun hasTimedOut(record: LocalSyncRecord, now: Long): Boolean {
        val referenceTime = when (record.status) {
            LocalSyncStatus.Imported,
            LocalSyncStatus.ConfirmPending -> record.statusEnteredAt
            else -> record.lastAttemptAt
        }
        return now - referenceTime >= STALE_STATUS_TIMEOUT_MS
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

    private suspend fun reportFailure(
        api: NexusRelayApi,
        deviceToken: String,
        jobId: String,
        error: String,
        retryable: Boolean = false,
        leaseId: String? = null,
        workerRunId: String? = null
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
            ledger.markFailureReported(jobId, System.currentTimeMillis())
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
            reportFailure(
                api = api,
                deviceToken = deviceToken,
                jobId = record.jobId,
                error = error,
                retryable = false,
                leaseId = record.leaseId,
                workerRunId = record.workerRunId
            )
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
                reportFailure(
                    api = api,
                    deviceToken = deviceToken,
                    jobId = record.jobId,
                    error = DOWNLOADING_TIMEOUT_MESSAGE,
                    leaseId = record.leaseId,
                    workerRunId = record.workerRunId
                )
            }
        }
    }

    private suspend fun recoverInterruptedClaims(
        api: NexusRelayApi,
        deviceToken: String,
        now: Long
    ) {
        val claimedQueuedRecords = ledger.listByStatuses(LocalSyncStatus.Queued)
            .filter { !it.leaseId.isNullOrBlank() }
        for (record in claimedQueuedRecords) {
            if (hasTimedOut(record, now)) {
                ledger.markFailed(record.jobId, QUEUED_TIMEOUT_MESSAGE)
                reportFailure(
                    api = api,
                    deviceToken = deviceToken,
                    jobId = record.jobId,
                    error = QUEUED_TIMEOUT_MESSAGE,
                    leaseId = record.leaseId,
                    workerRunId = record.workerRunId
                )
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
            api.confirmDeviceSyncJob(
                deviceToken,
                record.jobId,
                ConfirmDeviceSyncJobRequest(
                    importedUri = localUri,
                    importedSizeBytes = record.sizeBytes,
                    leaseId = record.leaseId,
                    workerRunId = record.workerRunId
                )
            )
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
            reportFailure(
                api = api,
                deviceToken = deviceToken,
                jobId = record.jobId,
                error = finalMessage,
                leaseId = record.leaseId,
                workerRunId = record.workerRunId
            )
            false
        }
    }

    suspend fun syncPendingJobs(
        workerRunId: String = UUID.randomUUID().toString(),
        enqueueContinuation: suspend () -> Unit = {}
    ): Boolean {
        val backendUrl = appSettingsStore.backendBaseUrlFlow.first()
        val deviceToken = deviceTokenStore.getDeviceToken()

        if (backendUrl.isNullOrBlank() || deviceToken.isNullOrBlank()) {
            Log.e(tag, "Sync skipped: Backend URL or Device Token is not configured.")
            return false
        }

        val api = apiProvider(backendUrl)
        val now = System.currentTimeMillis()
        reportUnreportedFailures(api, deviceToken)
        recoverInterruptedClaims(api, deviceToken, now)
        recoverInterruptedDownloads(api, deviceToken, now)

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

        val runnerResult = try {
            SyncSessionRunner(
                api = api,
                deviceToken = deviceToken,
                ledger = ledger,
                mediaStoreImporter = mediaStoreImporter,
                workerRunId = workerRunId,
                clientVersion = "pixel/${BuildConfig.VERSION_NAME}",
                enqueueContinuation = enqueueContinuation
            ).run()
        } catch (e: Exception) {
            Log.e(tag, "Lease-based sync session failed", e)
            throwOrPropagateIfRetriable(e)
            throw e
        }

        if (runnerResult.claimedJobCount == 0 && locallyHandledJobIds.isEmpty()) {
            allSucceeded = true
        } else if (!runnerResult.allSucceeded) {
            allSucceeded = false
        }

        if (allSucceeded && (runnerResult.claimedJobCount > 0 || locallyHandledJobIds.isNotEmpty())) {
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
