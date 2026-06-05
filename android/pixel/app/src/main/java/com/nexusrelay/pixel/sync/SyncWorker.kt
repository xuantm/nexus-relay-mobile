package com.nexusrelay.pixel.sync

import android.content.Context
import android.util.Log
import androidx.work.*
import com.nexusrelay.pixel.storage.AppSettingsStore
import kotlinx.coroutines.flow.first
import java.io.IOException

class SyncWorker(
    context: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(context, workerParams) {

    private val repository = DeviceSyncRepository(context)

    override suspend fun doWork(): Result {
        Log.d(TAG, "Sync background worker started execution.")
        return try {
            val success = repository.syncPendingJobs()
            if (success) {
                Result.success()
            } else {
                Result.success()
            }
        } catch (e: IOException) {
            Log.e(TAG, "Network failure during background sync. Retrying...", e)
            Result.retry()
        } catch (e: Exception) {
            Log.e(TAG, "Unexpected failure during background sync.", e)
            Result.failure()
        }
    }

    companion object {
        private const val TAG = "SyncWorker"
        const val WORK_NAME = "nexus-relay-pixel-sync"

        suspend fun enqueueOneTimeSync(context: Context) {
            val appSettingsStore = AppSettingsStore(context)
            val wifiOnly = appSettingsStore.wifiOnlyFlow.first()

            val networkType = if (wifiOnly) {
                NetworkType.UNMETERED
            } else {
                NetworkType.CONNECTED
            }

            val constraints = Constraints.Builder()
                .setRequiredNetworkType(networkType)
                .setRequiresBatteryNotLow(true)
                .setRequiresStorageNotLow(true)
                .build()

            val syncRequest = OneTimeWorkRequestBuilder<SyncWorker>()
                .setConstraints(constraints)
                .setBackoffCriteria(
                    BackoffPolicy.EXPONENTIAL,
                    WorkRequest.MIN_BACKOFF_MILLIS,
                    java.util.concurrent.TimeUnit.MILLISECONDS
                )
                .build()

            WorkManager.getInstance(context).enqueueUniqueWork(
                WORK_NAME,
                ExistingWorkPolicy.KEEP,
                syncRequest
            )
            Log.d(TAG, "Unique OneTime Sync enqueued. wifiOnly=$wifiOnly")
        }
    }
}
