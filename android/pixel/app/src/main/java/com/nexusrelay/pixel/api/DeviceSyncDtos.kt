package com.nexusrelay.pixel.api

import com.squareup.moshi.JsonClass

enum class DeviceSyncScope {
    AccountUploads,
    Folder
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
data class DeviceSyncJobDto(
    val jobId: String,
    val mediaId: String,
    val fileName: String,
    val mimeType: String,
    val mediaType: String,
    val sizeBytes: Long,
    val sha256: String?,
    val downloadUrl: String,
    val createdAt: String
)

@JsonClass(generateAdapter = true)
data class ConfirmDeviceSyncJobRequest(
    val importedUri: String?,
    val importedSizeBytes: Long?
)

@JsonClass(generateAdapter = true)
data class FailDeviceSyncJobRequest(
    val error: String
)

@JsonClass(generateAdapter = true)
data class LoginRequest(
    val username: String,
    val password: String
)

@JsonClass(generateAdapter = true)
data class LoginResponse(
    val token: String,
    val refreshToken: String? = null,
    val username: String? = null
)
