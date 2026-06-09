package com.nexusrelay.pixel

import android.app.Application
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class NexusRelayApp : Application() {
    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onCreate() {
        super.onCreate()

        appScope.launch {
            com.nexusrelay.pixel.sync.ensureBackgroundSyncConfigured(
                context = this@NexusRelayApp,
                refreshBackendTokenNow = true
            )
        }
    }
}
