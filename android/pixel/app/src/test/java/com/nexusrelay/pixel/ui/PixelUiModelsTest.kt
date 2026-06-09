package com.nexusrelay.pixel.ui

import com.nexusrelay.pixel.storage.LocalSyncRecord
import com.nexusrelay.pixel.storage.LocalSyncStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PixelUiModelsTest {

    @Test
    fun buildLedgerMaintenancePreviewCountsHistoryAndActiveRecords() {
        val records = listOf(
            sampleRecord("confirmed", LocalSyncStatus.Confirmed),
            sampleRecord("failed", LocalSyncStatus.Failed),
            sampleRecord("queued", LocalSyncStatus.Queued),
            sampleRecord("confirm", LocalSyncStatus.ConfirmPending)
        )

        val preview = buildLedgerMaintenancePreview(records)

        assertEquals(2, preview.historyCount)
        assertEquals(2, preview.activeCount)
        assertTrue(preview.canClearHistory)
        assertFalse(preview.canResetLedger)
    }

    @Test
    fun buildLedgerMaintenancePreview_emptyList_canResetButNotClear() {
        val preview = buildLedgerMaintenancePreview(emptyList())

        assertEquals(0, preview.historyCount)
        assertEquals(0, preview.activeCount)
        assertFalse(preview.canClearHistory)
        assertTrue(preview.canResetLedger)
    }

    @Test
    fun buildLedgerMaintenancePreview_allHistory_canClearAndReset() {
        val records = listOf(
            sampleRecord("confirmed", LocalSyncStatus.Confirmed),
            sampleRecord("failed", LocalSyncStatus.Failed)
        )

        val preview = buildLedgerMaintenancePreview(records)

        assertEquals(2, preview.historyCount)
        assertEquals(0, preview.activeCount)
        assertTrue(preview.canClearHistory)
        assertTrue(preview.canResetLedger)
    }

    @Test
    fun buildLedgerMaintenancePreview_allActive_cannotClearOrReset() {
        val records = listOf(
            sampleRecord("queued", LocalSyncStatus.Queued),
            sampleRecord("downloading", LocalSyncStatus.Downloading)
        )

        val preview = buildLedgerMaintenancePreview(records)

        assertEquals(0, preview.historyCount)
        assertEquals(2, preview.activeCount)
        assertFalse(preview.canClearHistory)
        assertFalse(preview.canResetLedger)
    }

    private fun sampleRecord(jobId: String, status: LocalSyncStatus): LocalSyncRecord =
        LocalSyncRecord(
            jobId = jobId,
            mediaId = "media-$jobId",
            fileName = "$jobId.jpg",
            mimeType = "image/jpeg",
            sizeBytes = 1L,
            sha256 = null,
            status = status,
            localUri = null,
            lastAttemptAt = 1L,
            lastError = null,
            isLocalDeleted = false,
            statusEnteredAt = 1L,
            retryCount = 0
        )
}
