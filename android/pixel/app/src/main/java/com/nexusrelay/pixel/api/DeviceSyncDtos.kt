package com.nexusrelay.pixel.api

import com.squareup.moshi.JsonClass

enum class DeviceSyncScope {
    AccountUploads,
    Folder
}

enum class SyncStatus {
    Pending,
    Syncing,
    Synced,
    Failed
}

@JsonClass(generateAdapter = true)
data class RegisterDeviceRequest(
    val deviceName: String,
    val fcmToken: String?,
    val wifiOnly: Boolean,
    val syncScope: DeviceSyncScope = DeviceSyncScope.AccountUploads,
    val scopedFolderId: String? = null
)

@JsonClass(generateAdapter = true)
data class RegisterDeviceResponse(
    val targetId: String,
    val deviceToken: String,
    val syncScope: DeviceSyncScope = DeviceSyncScope.AccountUploads,
    val scopedFolderId: String? = null
)

@JsonClass(generateAdapter = true)
data class UpdateDeviceFcmTokenRequest(
    val fcmToken: String
)

@JsonClass(generateAdapter = true)
data class ClaimDeviceSyncJobsRequest(
    val workerRunId: String,
    val limit: Int,
    val leaseSeconds: Int,
    val clientVersion: String?
)

@JsonClass(generateAdapter = true)
data class DeviceSyncClaimedJobDto(
    val jobId: String,
    val mediaId: String,
    val fileName: String,
    val mimeType: String,
    val mediaType: String,
    val sizeBytes: Long,
    val sha256: String?,
    val downloadUrl: String,
    val attemptNumber: Int,
    val createdAt: String
)

@JsonClass(generateAdapter = true)
data class ClaimDeviceSyncJobsResponse(
    val leaseId: String,
    val leaseExpiresAt: String,
    val remainingPendingCount: Int,
    val jobs: List<DeviceSyncClaimedJobDto>
)

@JsonClass(generateAdapter = true)
data class DeviceSyncHeartbeatRequest(
    val leaseId: String,
    val workerRunId: String,
    val stage: String,
    val progressBytes: Long,
    val totalBytes: Long?,
    val leaseSeconds: Int
)

@JsonClass(generateAdapter = true)
data class DeviceSyncHeartbeatResponse(
    val leaseExpiresAt: String
)

@JsonClass(generateAdapter = true)
data class WakeDeviceSyncTargetResponse(
    val signalSent: Boolean
)

@JsonClass(generateAdapter = true)
data class DeviceSyncJobDto(
    val jobId: String,
    val mediaId: String,
    val fileName: String,
    val mimeType: String,
    val mediaType: String,
    val sizeBytes: Long,
    val sha256: String?,
    val downloadUrl: String,
    val createdAt: String,
    val status: SyncStatus = SyncStatus.Pending
)

@JsonClass(generateAdapter = true)
data class ConfirmDeviceSyncJobRequest(
    val importedUri: String?,
    val importedSizeBytes: Long?,
    val leaseId: String? = null,
    val workerRunId: String? = null
)

@JsonClass(generateAdapter = true)
data class FailDeviceSyncJobRequest(
    val error: String,
    val retryable: Boolean = false,
    val leaseId: String? = null,
    val workerRunId: String? = null
)

@JsonClass(generateAdapter = true)
data class RedeemPairingCodeRequest(
    val code: String,
    val deviceName: String,
    val platform: String = "Android",
    val fcmToken: String?
)

@JsonClass(generateAdapter = true)
data class PairingCodePayload(
    val baseUrl: String,
    val code: String
)

@JsonClass(generateAdapter = true)
data class RedeemPairingCodeResponse(
    val targetId: String,
    val deviceToken: String,
    val syncScope: DeviceSyncScope = DeviceSyncScope.AccountUploads,
    val scopedFolderId: String? = null,
    val wifiOnly: Boolean = true
)
