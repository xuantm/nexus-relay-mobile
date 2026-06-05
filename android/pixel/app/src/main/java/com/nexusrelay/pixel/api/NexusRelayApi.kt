package com.nexusrelay.pixel.api

import okhttp3.ResponseBody
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Streaming

interface NexusRelayApi {
    @POST("api/device-sync/register")
    suspend fun registerDevice(
        @Body request: RegisterDeviceRequest
    ): RegisterDeviceResponse

    @GET("api/device-sync/jobs/pending")
    suspend fun pendingJobs(
        @Header("X-Device-Token") deviceToken: String
    ): List<DeviceSyncJobDto>

    @POST("api/device-sync/jobs/{jobId}/downloading")
    suspend fun markDownloading(
        @Header("X-Device-Token") deviceToken: String,
        @Path("jobId") jobId: String
    )

    @GET("api/device-sync/jobs/{jobId}/download")
    @Streaming
    suspend fun downloadJob(
        @Header("X-Device-Token") deviceToken: String,
        @Path("jobId") jobId: String
    ): ResponseBody

    @POST("api/device-sync/jobs/{jobId}/confirm")
    suspend fun confirm(
        @Header("X-Device-Token") deviceToken: String,
        @Path("jobId") jobId: String,
        @Body request: ConfirmDeviceSyncJobRequest
    )

    @POST("api/device-sync/jobs/{jobId}/fail")
    suspend fun fail(
        @Header("X-Device-Token") deviceToken: String,
        @Path("jobId") jobId: String,
        @Body request: FailDeviceSyncJobRequest
    )
}
