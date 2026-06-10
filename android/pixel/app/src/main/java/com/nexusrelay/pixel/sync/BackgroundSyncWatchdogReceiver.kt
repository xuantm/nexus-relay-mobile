package com.nexusrelay.pixel.sync

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log
import androidx.core.content.getSystemService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.util.concurrent.TimeUnit

class BackgroundSyncWatchdogReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_WATCHDOG_SYNC) {
            return
        }

        val pendingResult = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.Default).launch {
            try {
                val configured = ensureBackgroundSyncConfigured(
                    context = context,
                    refreshBackendTokenNow = false
                )
                if (configured) {
                    SyncWorker.enqueueOneTimeSync(context, expedited = true)
                }
            } finally {
                pendingResult.finish()
            }
        }
    }

    companion object {
        private const val TAG = "BackgroundSyncWatchdog"
        private const val ACTION_WATCHDOG_SYNC = "com.nexusrelay.pixel.action.WATCHDOG_SYNC"
        private const val REQUEST_CODE = 2101
        private val WATCHDOG_INTERVAL_MS = TimeUnit.MINUTES.toMillis(15)

        fun scheduleNext(context: Context) {
            val appContext = context.applicationContext
            val alarmManager = appContext.getSystemService<AlarmManager>() ?: return
            val triggerAt = SystemClock.elapsedRealtime() + WATCHDOG_INTERVAL_MS
            val pendingIntent = watchdogPendingIntent(appContext, PendingIntent.FLAG_UPDATE_CURRENT) ?: return

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerAt,
                    pendingIntent
                )
            } else {
                alarmManager.set(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerAt,
                    pendingIntent
                )
            }
            Log.d(TAG, "Background sync watchdog scheduled.")
        }

        fun cancel(context: Context) {
            val appContext = context.applicationContext
            val alarmManager = appContext.getSystemService<AlarmManager>() ?: return
            val pendingIntent = watchdogPendingIntent(appContext, PendingIntent.FLAG_NO_CREATE) ?: return
            alarmManager.cancel(pendingIntent)
            Log.d(TAG, "Background sync watchdog cancelled.")
        }

        private fun watchdogPendingIntent(context: Context, flags: Int): PendingIntent? {
            val intent = Intent(context, BackgroundSyncWatchdogReceiver::class.java).apply {
                action = ACTION_WATCHDOG_SYNC
            }
            return PendingIntent.getBroadcast(
                context,
                REQUEST_CODE,
                intent,
                flags or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }
}
