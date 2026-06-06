package com.nexusrelay.pixel.ui

import androidx.compose.runtime.saveable.Saver
import com.nexusrelay.pixel.storage.LocalSyncRecord
import com.nexusrelay.pixel.storage.LocalSyncStatus
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

enum class PixelTab {
    Sync,
    Ledger,
    Settings
}

val PixelTabSaver = Saver<PixelTab, String>(
    save = { it.name },
    restore = { PixelTab.valueOf(it) }
)

data class SyncMetrics(
    val confirmed: Int,
    val pending: Int,
    val failed: Int,
    val cleaned: Int
)

data class CleanupPreview(
    val cleanableCount: Int,
    val cleanableBytes: Long,
    val cleanableBytesLabel: String
)

fun buildSyncMetrics(records: List<LocalSyncRecord>): SyncMetrics {
    val confirmed = records.count { it.status == LocalSyncStatus.Confirmed }
    val pending = records.count {
        it.status == LocalSyncStatus.Queued ||
            it.status == LocalSyncStatus.Downloading ||
            it.status == LocalSyncStatus.Imported ||
            it.status == LocalSyncStatus.ConfirmPending
    }
    val failed = records.count { it.status == LocalSyncStatus.Failed }
    val cleaned = records.count { it.status == LocalSyncStatus.Confirmed && it.isLocalDeleted }
    return SyncMetrics(
        confirmed = confirmed,
        pending = pending,
        failed = failed,
        cleaned = cleaned
    )
}

fun buildCleanupPreview(records: List<LocalSyncRecord>): CleanupPreview {
    val cleanable = records.filter {
        it.status == LocalSyncStatus.Confirmed &&
            !it.isLocalDeleted &&
            !it.localUri.isNullOrBlank()
    }
    val bytes = cleanable.sumOf { it.sizeBytes }
    return CleanupPreview(
        cleanableCount = cleanable.size,
        cleanableBytes = bytes,
        cleanableBytesLabel = formatBytes(bytes)
    )
}

fun formatBytes(bytes: Long): String {
    if (bytes < 1024L) {
        return "$bytes B"
    }
    val kb = bytes / 1024.0
    if (kb < 1024.0) {
        return "%.1f KB".format(Locale.US, kb)
    }
    val mb = kb / 1024.0
    if (mb < 1024.0) {
        return "%.2f MB".format(Locale.US, mb)
    }
    return "%.2f GB".format(Locale.US, mb / 1024.0)
}

fun formatLastSyncTime(timestampMillis: Long): String {
    if (timestampMillis <= 0L) {
        return "Never"
    }
    return SimpleDateFormat("HH:mm dd/MM", Locale.getDefault()).format(Date(timestampMillis))
}

fun ledgerStatusLabel(record: LocalSyncRecord): String {
    if (record.status == LocalSyncStatus.Confirmed && record.isLocalDeleted) {
        return "Cleaned"
    }
    return when (record.status) {
        LocalSyncStatus.Queued -> "Queued"
        LocalSyncStatus.Downloading -> "Downloading"
        LocalSyncStatus.Imported -> "Imported"
        LocalSyncStatus.ConfirmPending -> "Confirming"
        LocalSyncStatus.Confirmed -> "Confirmed"
        LocalSyncStatus.Failed -> "Failed"
    }
}
