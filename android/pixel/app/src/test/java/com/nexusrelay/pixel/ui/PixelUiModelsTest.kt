package com.nexusrelay.pixel.ui

import com.nexusrelay.pixel.storage.LocalSyncRecord
import com.nexusrelay.pixel.storage.LocalSyncStatus
import org.junit.Assert.assertEquals
import org.junit.Test

class PixelUiModelsTest {
    @Test
    fun formatBytesUsesMbForLargeFiles() {
        assertEquals("4.80 MB", formatBytes(5_033_165L))
    }

    @Test
    fun formatLastSyncShowsNeverForZero() {
        assertEquals("Never", formatLastSyncTime(0L))
    }

    @Test
    fun buildSyncMetricsCountsConfirmedPendingAndFailed() {
        val records = listOf(
            record("confirmed", LocalSyncStatus.Confirmed),
            record("cleaned", LocalSyncStatus.Confirmed, isLocalDeleted = true),
            record("downloading", LocalSyncStatus.Downloading),
            record("queued", LocalSyncStatus.Queued),
            record("failed", LocalSyncStatus.Failed)
        )

        val metrics = buildSyncMetrics(records)

        assertEquals(2, metrics.confirmed)
        assertEquals(2, metrics.pending)
        assertEquals(1, metrics.failed)
        assertEquals(1, metrics.cleaned)
    }

    @Test
    fun buildCleanupPreviewIncludesOnlyConfirmedNotDeletedLocalFiles() {
        val records = listOf(
            record("ready", LocalSyncStatus.Confirmed, localUri = "content://ready", sizeBytes = 100L),
            record("deleted", LocalSyncStatus.Confirmed, localUri = "content://deleted", sizeBytes = 200L, isLocalDeleted = true),
            record("failed", LocalSyncStatus.Failed, localUri = "content://failed", sizeBytes = 300L),
            record("missing-uri", LocalSyncStatus.Confirmed, localUri = null, sizeBytes = 400L)
        )

        val preview = buildCleanupPreview(records)

        assertEquals(1, preview.cleanableCount)
        assertEquals(100L, preview.cleanableBytes)
        assertEquals("100 B", preview.cleanableBytesLabel)
    }

    private fun record(
        id: String,
        status: LocalSyncStatus,
        localUri: String? = "content://$id",
        sizeBytes: Long = 1024L,
        isLocalDeleted: Boolean = false
    ): LocalSyncRecord {
        return LocalSyncRecord(
            jobId = id,
            mediaId = "media-$id",
            fileName = "$id.jpg",
            mimeType = "image/jpeg",
            sizeBytes = sizeBytes,
            sha256 = null,
            status = status,
            localUri = localUri,
            lastAttemptAt = 0L,
            lastError = null,
            isLocalDeleted = isLocalDeleted
        )
    }
}
