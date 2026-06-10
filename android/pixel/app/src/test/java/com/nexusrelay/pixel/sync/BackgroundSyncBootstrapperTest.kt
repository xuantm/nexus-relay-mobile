package com.nexusrelay.pixel.sync

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BackgroundSyncBootstrapperTest {

    @Test
    fun ensureConfigured_skipsSchedulingWhenDeviceIsNotRegistered() = runTest {
        var pollScheduled = false
        var watchdogScheduled = false
        var refreshed = false

        val bootstrapper = BackgroundSyncBootstrapper(
            loadDeviceToken = { null },
            schedulePeriodicPoll = { pollScheduled = true },
            scheduleWatchdog = { watchdogScheduled = true },
            refreshBackendToken = { refreshed = true }
        )

        val configured = bootstrapper.ensureConfigured(refreshBackendTokenNow = true)

        assertFalse(configured)
        assertFalse(pollScheduled)
        assertFalse(watchdogScheduled)
        assertFalse(refreshed)
    }

    @Test
    fun ensureConfigured_schedulesPollingWatchdogAndRefreshesWhenRegistered() = runTest {
        var pollScheduled = false
        var watchdogScheduled = false
        var refreshed = false

        val bootstrapper = BackgroundSyncBootstrapper(
            loadDeviceToken = { "device-token" },
            schedulePeriodicPoll = { pollScheduled = true },
            scheduleWatchdog = { watchdogScheduled = true },
            refreshBackendToken = { refreshed = true }
        )

        val configured = bootstrapper.ensureConfigured(refreshBackendTokenNow = true)

        assertTrue(configured)
        assertTrue(pollScheduled)
        assertTrue(watchdogScheduled)
        assertTrue(refreshed)
    }

    @Test
    fun ensureConfigured_schedulesPollingWithoutRefreshingWhenNotRequested() = runTest {
        var pollScheduled = false
        var watchdogScheduled = false
        var refreshed = false

        val bootstrapper = BackgroundSyncBootstrapper(
            loadDeviceToken = { "device-token" },
            schedulePeriodicPoll = { pollScheduled = true },
            scheduleWatchdog = { watchdogScheduled = true },
            refreshBackendToken = { refreshed = true }
        )

        val configured = bootstrapper.ensureConfigured(refreshBackendTokenNow = false)

        assertTrue(configured)
        assertTrue(pollScheduled)
        assertTrue(watchdogScheduled)
        assertFalse(refreshed)
    }
}
