package com.nexusrelay.pixel.storage

import android.content.Context
import android.content.ContextWrapper
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class LocalSyncLedgerTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private class TestContext : ContextWrapper(null)

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun testLedgerOperations() = runTest {
        val tempFile = File(tempFolder.root, "test_ledger.preferences_pb")
        val dataStore = PreferenceDataStoreFactory.create { tempFile }
        val ledger = LocalSyncLedger(TestContext(), dataStore)

        // 1. Initial get should be null
        val initialRecord = ledger.get("job-1")
        assertNull(initialRecord)

        // 2. Insert record
        val record = LocalSyncRecord(
            jobId = "job-1",
            mediaId = "media-1",
            fileName = "image.png",
            mimeType = "image/png",
            sizeBytes = 100L,
            sha256 = "hash123",
            status = LocalSyncStatus.Queued,
            localUri = null,
            lastAttemptAt = System.currentTimeMillis(),
            lastError = null
        )
        ledger.upsert(record)

        val saved = ledger.get("job-1")
        assertNotNull(saved)
        assertEquals("job-1", saved!!.jobId)
        assertEquals(LocalSyncStatus.Queued, saved.status)

        // 3. Mark downloading
        ledger.markDownloading("job-1")
        val downloading = ledger.get("job-1")
        assertNotNull(downloading)
        assertEquals(LocalSyncStatus.Downloading, downloading!!.status)

        // 4. Mark imported/confirm pending
        ledger.markConfirmPending("job-1", "content://media/1")
        val pending = ledger.get("job-1")
        assertNotNull(pending)
        assertEquals(LocalSyncStatus.ConfirmPending, pending!!.status)
        assertEquals("content://media/1", pending.localUri)

        // 5. Mark confirmed
        ledger.markConfirmed("job-1")
        val confirmed = ledger.get("job-1")
        assertNotNull(confirmed)
        assertEquals(LocalSyncStatus.Confirmed, confirmed!!.status)

        // 6. Mark failed
        ledger.markFailed("job-1", "Network error")
        val failed = ledger.get("job-1")
        assertNotNull(failed)
        assertEquals(LocalSyncStatus.Failed, failed!!.status)
        assertEquals("Network error", failed.lastError)
    }
}
