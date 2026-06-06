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

class DeviceSyncRepository(
    private val context: Context,
    private val appSettingsStore: AppSettingsStore = AppSettingsStore(context),
    private val deviceTokenStore: DeviceTokenStore = DeviceTokenStore(context),
    private val ledger: LocalSyncLedger = LocalSyncLedger(context),
    private val mediaStoreImporter: MediaStoreImporter = MediaStoreImporter(context),
    private val apiProvider: (String) -> NexusRelayApi = { baseUrl -> ApiClientFactory.create(baseUrl, debugLoggingEnabled = BuildConfig.DEBUG) }
) {
    private val tag = "DeviceSyncRepository"

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

    private suspend fun retryLocalConfirmation(
        api: NexusRelayApi,
        deviceToken: String,
        record: LocalSyncRecord
    ): Boolean? {
        val localUri = record.localUri ?: return null

        return try {
            api.confirm(deviceToken, record.jobId, ConfirmDeviceSyncJobRequest(localUri, record.sizeBytes))
            ledger.markConfirmed(record.jobId)
            true
        } catch (e: Exception) {
            Log.e(tag, "Re-confirming job ${record.jobId} failed, will retry later", e)
            throwOrPropagateIfRetriable(e)

            val errorMsg = e.localizedMessage ?: "Terminal confirmation error"
            ledger.markFailed(record.jobId, errorMsg)
            try {
                api.fail(deviceToken, record.jobId, FailDeviceSyncJobRequest(errorMsg))
            } catch (failEx: Exception) {
                Log.e(tag, "Failed to report job failure to backend for job ${record.jobId}", failEx)
            }
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
        val pendingJobs = try {
            api.pendingJobs(deviceToken)
        } catch (e: Exception) {
            Log.e(tag, "Failed to fetch pending jobs", e)
            throwOrPropagateIfRetriable(e)
            throw e
        }

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

                api.confirm(deviceToken, job.jobId, ConfirmDeviceSyncJobRequest(localUri, job.sizeBytes))

                ledger.markConfirmed(job.jobId)

            } catch (e: Exception) {
                Log.e(tag, "Failed to sync job ${job.jobId}", e)

                throwOrPropagateIfRetriable(e)

                val errorMsg = e.localizedMessage ?: "Unknown error"
                ledger.markFailed(job.jobId, errorMsg)

                try {
                    api.fail(deviceToken, job.jobId, FailDeviceSyncJobRequest(errorMsg))
                } catch (failEx: Exception) {
                    Log.e(tag, "Failed to report job failure to backend for job ${job.jobId}", failEx)
                }

                allSucceeded = false
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

