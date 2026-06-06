package com.nexusrelay.pixel.sync

data class CleanupSpaceResult(
    val scannedCount: Int,
    val deletedCount: Int,
    val skippedCount: Int,
    val failedCount: Int,
    val freedBytes: Long
)
