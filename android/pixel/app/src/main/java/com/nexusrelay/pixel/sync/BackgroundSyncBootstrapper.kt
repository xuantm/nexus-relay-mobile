package com.nexusrelay.pixel.sync

import android.content.Context
import com.nexusrelay.pixel.auth.DeviceTokenStore

internal class BackgroundSyncBootstrapper(
    private val loadDeviceToken: suspend () -> String?,
    private val schedulePeriodicPoll: () -> Unit,
    private val scheduleWatchdog: () -> Unit,
    private val refreshBackendToken: suspend () -> Unit
) {
    suspend fun ensureConfigured(refreshBackendTokenNow: Boolean): Boolean {
        val deviceToken = loadDeviceToken()?.trim().orEmpty()
        if (deviceToken.isEmpty()) {
            return false
        }

        schedulePeriodicPoll()
        scheduleWatchdog()

        if (refreshBackendTokenNow) {
            refreshBackendToken()
        }

        return true
    }
}

internal suspend fun ensureBackgroundSyncConfigured(
    context: Context,
    refreshBackendTokenNow: Boolean
): Boolean {
    val appContext = context.applicationContext
    val bootstrapper = BackgroundSyncBootstrapper(
        loadDeviceToken = { DeviceTokenStore(appContext).getDeviceToken() },
        schedulePeriodicPoll = { PollWorker.schedulePeriodicPoll(appContext) },
        scheduleWatchdog = { BackgroundSyncWatchdogReceiver.scheduleNext(appContext) },
        refreshBackendToken = { refreshBackendFcmToken(appContext) }
    )

    return bootstrapper.ensureConfigured(refreshBackendTokenNow)
}
