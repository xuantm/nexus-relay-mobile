package com.nexusrelay.pixel.api

import okhttp3.ResponseBody
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Streaming

interface NexusRelayApi {
    @POST("api/device-sync/pairing-codes/redeem")
    suspend fun redeemPairingCode(
        @Body request: RedeemPairingCodeRequest
    ): RedeemPairingCodeResponse

    @POST("api/device-sync/fcm-token")
    suspend fun updateFcmToken(
        @Header("X-Device-Token") deviceToken: String,
        @Body request: UpdateDeviceFcmTokenRequest
    )

    @POST("api/device-sync/jobs/claim")
    suspend fun claimDeviceSyncJobs(
        @Header("X-Device-Token") deviceToken: String,
        @Body request: ClaimDeviceSyncJobsRequest
    ): ClaimDeviceSyncJobsResponse

    @GET("api/device-sync/jobs/{jobId}/download")
    @Streaming
    suspend fun downloadDeviceSyncJob(
        @Header("X-Device-Token") deviceToken: String,
        @Header("X-Device-Sync-Lease") leaseId: String,
        @Path("jobId") jobId: String
    ): ResponseBody

    @POST("api/device-sync/jobs/{jobId}/heartbeat")
    suspend fun heartbeatDeviceSyncJob(
        @Header("X-Device-Token") deviceToken: String,
        @Path("jobId") jobId: String,
        @Body request: DeviceSyncHeartbeatRequest
    ): DeviceSyncHeartbeatResponse

    @POST("api/device-sync/jobs/{jobId}/confirm")
    suspend fun confirmDeviceSyncJob(
        @Header("X-Device-Token") deviceToken: String,
        @Path("jobId") jobId: String,
        @Body request: ConfirmDeviceSyncJobRequest
    )

    @POST("api/device-sync/jobs/{jobId}/fail")
    suspend fun failDeviceSyncJob(
        @Header("X-Device-Token") deviceToken: String,
        @Path("jobId") jobId: String,
        @Body request: FailDeviceSyncJobRequest
    )

    @Deprecated("Use claimDeviceSyncJobs")
    @GET("api/device-sync/jobs/pending")
    suspend fun pendingJobs(
        @Header("X-Device-Token") deviceToken: String
    ): List<DeviceSyncJobDto>

    @Deprecated("Use downloadDeviceSyncJob")
    suspend fun downloadJob(
        @Header("X-Device-Token") deviceToken: String,
        @Path("jobId") jobId: String
    ): ResponseBody {
        throw UnsupportedOperationException("Use downloadDeviceSyncJob with X-Device-Sync-Lease")
    }

    @Deprecated("Use downloadDeviceSyncJob")
    @POST("api/device-sync/jobs/{jobId}/downloading")
    suspend fun markDownloading(
        @Header("X-Device-Token") deviceToken: String,
        @Path("jobId") jobId: String
    )

    @Deprecated("Use confirmDeviceSyncJob")
    @POST("api/device-sync/jobs/{jobId}/confirm")
    suspend fun confirm(
        @Header("X-Device-Token") deviceToken: String,
        @Path("jobId") jobId: String,
        @Body request: ConfirmDeviceSyncJobRequest
    )

    @Deprecated("Use failDeviceSyncJob")
    @POST("api/device-sync/jobs/{jobId}/fail")
    suspend fun fail(
        @Header("X-Device-Token") deviceToken: String,
        @Path("jobId") jobId: String,
        @Body request: FailDeviceSyncJobRequest
    )
}
