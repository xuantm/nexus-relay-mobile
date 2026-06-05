package com.nexusrelay.pixel.sync

import android.content.Context
import android.util.Log
import com.nexusrelay.pixel.BuildConfig
import com.nexusrelay.pixel.api.ApiClientFactory
import com.nexusrelay.pixel.api.ConfirmDeviceSyncJobRequest
import com.nexusrelay.pixel.api.FailDeviceSyncJobRequest
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
    private val mediaStoreImporter: MediaStoreImporter = MediaStoreImporter(context)
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

    suspend fun syncPendingJobs(): Boolean {
        val backendUrl = appSettingsStore.backendBaseUrlFlow.first()
        val deviceToken = deviceTokenStore.getDeviceToken()

        if (backendUrl.isNullOrBlank() || deviceToken.isNullOrBlank()) {
            Log.e(tag, "Sync skipped: Backend URL or Device Token is not configured.")
            return false
        }

        val api = ApiClientFactory.create(backendUrl, debugLoggingEnabled = BuildConfig.DEBUG)
        val pendingJobs = try {
            api.pendingJobs(deviceToken)
        } catch (e: Exception) {
            Log.e(tag, "Failed to fetch pending jobs", e)
            throwOrPropagateIfRetriable(e)
            throw e
        }

        var allSucceeded = true

        for (job in pendingJobs) {
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
                val localUri = ledgerRecord.localUri
                if (localUri != null) {
                    try {
                        api.confirm(deviceToken, job.jobId, ConfirmDeviceSyncJobRequest(localUri, job.sizeBytes))
                        ledger.markConfirmed(job.jobId)
                        continue
                    } catch (e: Exception) {
                        Log.e(tag, "Re-confirming job ${job.jobId} failed, will retry later", e)
                        throwOrPropagateIfRetriable(e)

                        val errorMsg = e.localizedMessage ?: "Terminal confirmation error"
                        ledger.markFailed(job.jobId, errorMsg)
                        try {
                            api.fail(deviceToken, job.jobId, FailDeviceSyncJobRequest(errorMsg))
                        } catch (failEx: Exception) {
                            Log.e(tag, "Failed to report job failure to backend for job ${job.jobId}", failEx)
                        }
                        allSucceeded = false
                        continue
                    }
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

        return allSucceeded
    }
}
