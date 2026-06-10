package com.nexusrelay.pixel.sync

import android.content.Context
import android.util.Log
import androidx.work.*
import java.util.concurrent.TimeUnit

class PollWorker(
    context: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(context, workerParams) {

    override suspend fun doWork(): Result {
        Log.d(TAG, "Periodic PollWorker triggered. Enqueuing one-time sync.")
        SyncWorker.enqueueOneTimeSync(applicationContext, expedited = true)
        return Result.success()
    }

    companion object {
        private const val TAG = "PollWorker"
        const val WORK_NAME = "nexus-relay-pixel-poll"

        fun schedulePeriodicPoll(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val pollRequest = PeriodicWorkRequestBuilder<PollWorker>(15, TimeUnit.MINUTES)
                .setConstraints(constraints)
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                pollRequest
            )
            Log.d(TAG, "Periodic PollWorker scheduled (15 minutes).")
        }

        fun cancelPeriodicPoll(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
            Log.d(TAG, "Periodic PollWorker cancelled.")
        }
    }
}
