package com.nexusrelay.pixel.sync

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.getSystemService
import androidx.work.*
import com.nexusrelay.pixel.MainActivity
import com.nexusrelay.pixel.R
import com.nexusrelay.pixel.storage.AppSettingsStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import java.io.IOException
import java.util.UUID
import java.util.concurrent.TimeUnit

class SyncWorker(
    context: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(context, workerParams) {

    private val repository = DeviceSyncRepository(context)

    override suspend fun getForegroundInfo(): ForegroundInfo {
        return createForegroundInfo()
    }

    override suspend fun doWork(): Result {
        Log.d(TAG, "Sync background worker started execution.")
        setForeground(createForegroundInfo())
        val workerRunId = resolveWorkerRunId(inputData)
        return try {
            val success = repository.syncPendingJobs(
                workerRunId = workerRunId,
                enqueueContinuation = {
                    enqueueContinuationSync(applicationContext, workerRunId)
                }
            )
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

    private fun createForegroundInfo(): ForegroundInfo {
        ensureNotificationChannel()

        val launchIntent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            applicationContext,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentTitle(applicationContext.getString(R.string.sync_notification_title))
            .setContentText(applicationContext.getString(R.string.sync_notification_body))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pendingIntent)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            ForegroundInfo(NOTIFICATION_ID, notification)
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val notificationManager = applicationContext.getSystemService<NotificationManager>() ?: return
        val existingChannel = notificationManager.getNotificationChannel(CHANNEL_ID)
        if (existingChannel != null) {
            return
        }

        val channel = NotificationChannel(
            CHANNEL_ID,
            applicationContext.getString(R.string.sync_notification_channel_name),
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = applicationContext.getString(R.string.sync_notification_channel_description)
            setShowBadge(false)
        }
        notificationManager.createNotificationChannel(channel)
    }

    companion object {
        private const val TAG = "SyncWorker"
        const val WORK_NAME = "nexus-relay-pixel-sync"
        const val KEY_WORKER_RUN_ID = "worker_run_id"
        const val KEY_IS_CONTINUATION = "is_continuation"
        private const val CHANNEL_ID = "nexus-relay-pixel-sync"
        private const val NOTIFICATION_ID = 1101

        suspend fun enqueueOneTimeSync(
            context: Context,
            expedited: Boolean = false,
            inputData: Data = buildSyncInputData(
                workerRunId = UUID.randomUUID().toString(),
                isContinuation = false
            )
        ) {
            val appSettingsStore = AppSettingsStore(context)
            val wifiOnly = appSettingsStore.wifiOnlyFlow.first()

            val networkType = if (wifiOnly) {
                NetworkType.UNMETERED
            } else {
                NetworkType.CONNECTED
            }

            val constraints = Constraints.Builder()
                .setRequiredNetworkType(networkType)
                .setRequiresStorageNotLow(true)
                .apply {
                    if (!expedited) {
                        setRequiresBatteryNotLow(true)
                    }
                }
                .build()

            val syncRequestBuilder = OneTimeWorkRequestBuilder<SyncWorker>()
                .setInputData(inputData)
                .setConstraints(constraints)
                .setBackoffCriteria(
                    BackoffPolicy.EXPONENTIAL,
                    WorkRequest.MIN_BACKOFF_MILLIS,
                    TimeUnit.MILLISECONDS
                )

            if (expedited) {
                syncRequestBuilder.setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            }

            val syncRequest = syncRequestBuilder.build()
            val workManager = WorkManager.getInstance(context)
            val existingStates = withContext(Dispatchers.IO) {
                workManager.getWorkInfosForUniqueWork(WORK_NAME).get()
                    .map { it.state }
            }
            val existingWorkPolicy = selectExistingWorkPolicy(expedited, existingStates)

            workManager.enqueueUniqueWork(
                WORK_NAME,
                existingWorkPolicy,
                syncRequest
            )
            Log.d(TAG, "Unique OneTime Sync enqueued. wifiOnly=$wifiOnly expedited=$expedited policy=$existingWorkPolicy")
        }

        suspend fun enqueueContinuationSync(context: Context, workerRunId: String) {
            val appSettingsStore = AppSettingsStore(context)
            val wifiOnly = appSettingsStore.wifiOnlyFlow.first()
            val networkType = if (wifiOnly) {
                NetworkType.UNMETERED
            } else {
                NetworkType.CONNECTED
            }

            val constraints = Constraints.Builder()
                .setRequiredNetworkType(networkType)
                .setRequiresStorageNotLow(true)
                .setRequiresBatteryNotLow(true)
                .build()

            val continuationRequest = OneTimeWorkRequestBuilder<SyncWorker>()
                .setInputData(buildSyncInputData(workerRunId, isContinuation = true))
                .setConstraints(constraints)
                .setBackoffCriteria(
                    BackoffPolicy.EXPONENTIAL,
                    WorkRequest.MIN_BACKOFF_MILLIS,
                    TimeUnit.MILLISECONDS
                )
                .build()

            WorkManager.getInstance(context).enqueueUniqueWork(
                WORK_NAME,
                ExistingWorkPolicy.APPEND_OR_REPLACE,
                continuationRequest
            )
            Log.d(TAG, "Sync continuation enqueued. workerRunId=$workerRunId")
        }
    }
}

internal fun selectExistingWorkPolicy(
    expedited: Boolean,
    existingStates: List<WorkInfo.State>
): ExistingWorkPolicy {
    if (!expedited) {
        return ExistingWorkPolicy.KEEP
    }

    if (existingStates.any { it == WorkInfo.State.RUNNING }) {
        return ExistingWorkPolicy.KEEP
    }

    return if (existingStates.any { it == WorkInfo.State.ENQUEUED || it == WorkInfo.State.BLOCKED }) {
        ExistingWorkPolicy.REPLACE
    } else {
        ExistingWorkPolicy.KEEP
    }
}

internal fun buildSyncInputData(workerRunId: String, isContinuation: Boolean): Data {
    return Data.Builder()
        .putString(SyncWorker.KEY_WORKER_RUN_ID, workerRunId)
        .putBoolean(SyncWorker.KEY_IS_CONTINUATION, isContinuation)
        .build()
}

internal fun resolveWorkerRunId(inputData: Data): String {
    return inputData.getString(SyncWorker.KEY_WORKER_RUN_ID)
        ?.takeIf { it.isNotBlank() }
        ?: UUID.randomUUID().toString()
}
