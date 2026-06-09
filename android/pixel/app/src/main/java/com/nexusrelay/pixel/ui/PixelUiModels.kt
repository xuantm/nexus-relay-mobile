package com.nexusrelay.pixel.ui

import androidx.compose.runtime.saveable.Saver
import com.nexusrelay.pixel.api.SyncStatus
import com.nexusrelay.pixel.storage.LocalSyncRecord
import com.nexusrelay.pixel.storage.LocalSyncStatus
import com.nexusrelay.pixel.storage.toSyncStatus
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
    val syncing: Int,
    val pending: Int,
    val failed: Int,
    val cleaned: Int
)

data class CleanupPreview(
    val cleanableCount: Int,
    val cleanableBytes: Long,
    val cleanableBytesLabel: String
)

internal fun buildSyncMetrics(records: List<LocalSyncRecord>): SyncMetrics {
    val confirmed = records.count { it.status == LocalSyncStatus.Confirmed }
    val syncing = records.count { it.status.toSyncStatus() == SyncStatus.Syncing }
    val pending = records.count { it.status.toSyncStatus() == SyncStatus.Pending }
    val failed = records.count { it.status == LocalSyncStatus.Failed }
    val cleaned = records.count { it.status == LocalSyncStatus.Confirmed && it.isLocalDeleted }
    return SyncMetrics(
        confirmed = confirmed,
        syncing = syncing,
        pending = pending,
        failed = failed,
        cleaned = cleaned
    )
}

internal fun buildCleanupPreview(records: List<LocalSyncRecord>): CleanupPreview {
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

internal fun ledgerStatusLabel(record: LocalSyncRecord): String {
    if (record.status == LocalSyncStatus.Confirmed && record.isLocalDeleted) {
        return "Cleaned"
    }
    return when (record.status.toSyncStatus()) {
        SyncStatus.Pending -> "Pending"
        SyncStatus.Syncing -> "Syncing"
        SyncStatus.Synced -> "Synced"
        SyncStatus.Failed -> "Failed"
    }
}

data class LedgerMaintenancePreview(
    val historyCount: Int,
    val activeCount: Int,
    val canClearHistory: Boolean,
    val canResetLedger: Boolean
)

internal fun buildLedgerMaintenancePreview(records: List<LocalSyncRecord>): LedgerMaintenancePreview {
    val historyCount = records.count {
        it.status == LocalSyncStatus.Confirmed || it.status == LocalSyncStatus.Failed
    }
    val activeCount = records.count {
        it.status == LocalSyncStatus.Queued ||
            it.status == LocalSyncStatus.Downloading ||
            it.status == LocalSyncStatus.Imported ||
            it.status == LocalSyncStatus.ConfirmPending
    }
    return LedgerMaintenancePreview(
        historyCount = historyCount,
        activeCount = activeCount,
        canClearHistory = historyCount > 0,
        canResetLedger = activeCount == 0
    )
}
