package com.nexusrelay.pixel.sync

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BackgroundSyncBootstrapperTest {

    @Test
    fun ensureConfigured_skipsSchedulingWhenDeviceIsNotRegistered() = runTest {
        var scheduled = false
        var refreshed = false

        val bootstrapper = BackgroundSyncBootstrapper(
            loadDeviceToken = { null },
            schedulePeriodicPoll = { scheduled = true },
            refreshBackendToken = { refreshed = true }
        )

        val configured = bootstrapper.ensureConfigured(refreshBackendTokenNow = true)

        assertFalse(configured)
        assertFalse(scheduled)
        assertFalse(refreshed)
    }

    @Test
    fun ensureConfigured_schedulesPollingAndRefreshesWhenRegistered() = runTest {
        var scheduled = false
        var refreshed = false

        val bootstrapper = BackgroundSyncBootstrapper(
            loadDeviceToken = { "device-token" },
            schedulePeriodicPoll = { scheduled = true },
            refreshBackendToken = { refreshed = true }
        )

        val configured = bootstrapper.ensureConfigured(refreshBackendTokenNow = true)

        assertTrue(configured)
        assertTrue(scheduled)
        assertTrue(refreshed)
    }

    @Test
    fun ensureConfigured_schedulesPollingWithoutRefreshingWhenNotRequested() = runTest {
        var scheduled = false
        var refreshed = false

        val bootstrapper = BackgroundSyncBootstrapper(
            loadDeviceToken = { "device-token" },
            schedulePeriodicPoll = { scheduled = true },
            refreshBackendToken = { refreshed = true }
        )

        val configured = bootstrapper.ensureConfigured(refreshBackendTokenNow = false)

        assertTrue(configured)
        assertTrue(scheduled)
        assertFalse(refreshed)
    }
}
