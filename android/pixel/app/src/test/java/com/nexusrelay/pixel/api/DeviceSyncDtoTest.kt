package com.nexusrelay.pixel.api

import com.nexusrelay.pixel.ui.resolveFcmTokenForRegistration
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Streaming

class DeviceSyncDtoTest {

    @Test
    fun fcmTokenResolutionFallsBackToStoredTokenWhenCurrentFetchFails() = runTest {
        var saveCalled = false

        val token = resolveFcmTokenForRegistration(
            storedFcmToken = "stored-token",
            fetchCurrentFcmToken = { error("Firebase token unavailable") },
            saveFcmToken = {
                saveCalled = true
            }
        )

        assertEquals("stored-token", token)
        assertEquals(false, saveCalled)
    }

    @Test
    fun fcmTokenResolutionSavesCurrentTokenWhenFetchSucceeds() = runTest {
        var savedToken: String? = null

        val token = resolveFcmTokenForRegistration(
            storedFcmToken = null,
            fetchCurrentFcmToken = { "current-token" },
            saveFcmToken = {
                savedToken = it
            }
        )

        assertEquals("current-token", token)
        assertEquals("current-token", savedToken)
    }

    @Test
    fun redeemPairingCodeUsesCorrectEndpoint() {
        val post = NexusRelayApi::class.java
            .declaredMethods
            .single { it.name == "redeemPairingCode" }
            .getAnnotation(POST::class.java)

        assertEquals("api/device-sync/pairing-codes/redeem", post?.value)
    }

    @Test
    fun updateFcmTokenUsesDeviceAuthenticatedEndpoint() {
        val post = NexusRelayApi::class.java
            .declaredMethods
            .single { it.name == "updateFcmToken" }
            .getAnnotation(POST::class.java)

        assertEquals("api/device-sync/fcm-token", post?.value)
    }

    @Test
    fun claimLeaseHeartbeatAndDecisionDtosMatchTheNewApiContract() {
        val moshi = Moshi.Builder()
            .add(KotlinJsonAdapterFactory())
            .build()

        val claimRequest = ClaimDeviceSyncJobsRequest(
            workerRunId = "worker-run-123",
            limit = 3,
            leaseSeconds = 120,
            clientVersion = null
        )
        val claimJson = moshi.adapter(ClaimDeviceSyncJobsRequest::class.java)
            .serializeNulls()
            .toJson(claimRequest)
        assertTrue(claimJson.contains("\"workerRunId\":\"worker-run-123\""))
        assertTrue(claimJson.contains("\"limit\":3"))
        assertTrue(claimJson.contains("\"leaseSeconds\":120"))
        assertTrue(claimJson.contains("\"clientVersion\":null"))

        val claimResponseClass = Class.forName("com.nexusrelay.pixel.api.ClaimDeviceSyncJobsResponse")
        val claimedJobClass = Class.forName("com.nexusrelay.pixel.api.DeviceSyncClaimedJobDto")
        val claimResponseJson = """
            {
              "leaseId": "lease-abc",
              "leaseExpiresAt": "2026-06-11T10:15:00Z",
              "remainingPendingCount": 7,
              "jobs": [
                {
                  "jobId": "job-1",
                  "mediaId": "media-1",
                  "fileName": "IMG_1001.HEIC",
                  "mimeType": "image/heic",
                  "mediaType": "Image",
                  "sizeBytes": 4820131,
                  "sha256": null,
                  "downloadUrl": "/api/device-sync/jobs/job-1/download",
                  "attemptNumber": 2,
                  "createdAt": "2026-06-11T09:15:00Z"
                }
              ]
            }
        """.trimIndent()
        val claimResponse = moshi.adapter<Any>(claimResponseClass).fromJson(claimResponseJson)
        assertNotNull(claimResponse)
        assertEquals("lease-abc", getter(claimResponse!!, "leaseId"))
        assertEquals("2026-06-11T10:15:00Z", getter(claimResponse, "leaseExpiresAt"))
        assertEquals(7, getter(claimResponse, "remainingPendingCount"))
        val jobs = getter(claimResponse, "jobs") as List<*>
        assertEquals(1, jobs.size)
        val claimedJob = jobs[0]!!
        assertEquals("job-1", getter(claimedJob, "jobId"))
        assertEquals("media-1", getter(claimedJob, "mediaId"))
        assertEquals("IMG_1001.HEIC", getter(claimedJob, "fileName"))
        assertEquals("image/heic", getter(claimedJob, "mimeType"))
        assertEquals("Image", getter(claimedJob, "mediaType"))
        assertEquals(4820131L, getter(claimedJob, "sizeBytes"))
        assertNull(getter(claimedJob, "sha256"))
        assertEquals("/api/device-sync/jobs/job-1/download", getter(claimedJob, "downloadUrl"))
        assertEquals(2, getter(claimedJob, "attemptNumber"))
        assertEquals("2026-06-11T09:15:00Z", getter(claimedJob, "createdAt"))

        val heartbeatRequest = DeviceSyncHeartbeatRequest(
            leaseId = "lease-abc",
            workerRunId = "worker-run-123",
            stage = "Downloading",
            progressBytes = 2048L,
            totalBytes = null,
            leaseSeconds = 150
        )
        val heartbeatJson = moshi.adapter(DeviceSyncHeartbeatRequest::class.java)
            .serializeNulls()
            .toJson(heartbeatRequest)
        assertTrue(heartbeatJson.contains("\"leaseId\":\"lease-abc\""))
        assertTrue(heartbeatJson.contains("\"workerRunId\":\"worker-run-123\""))
        assertTrue(heartbeatJson.contains("\"stage\":\"Downloading\""))
        assertTrue(heartbeatJson.contains("\"progressBytes\":2048"))
        assertTrue(heartbeatJson.contains("\"totalBytes\":null"))
        assertTrue(heartbeatJson.contains("\"leaseSeconds\":150"))

        val heartbeatResponseClass = Class.forName("com.nexusrelay.pixel.api.DeviceSyncHeartbeatResponse")
        val heartbeatResponse = moshi.adapter<Any>(heartbeatResponseClass).fromJson(
            """{"leaseExpiresAt":"2026-06-11T10:20:00Z"}"""
        )
        assertNotNull(heartbeatResponse)
        assertEquals("2026-06-11T10:20:00Z", getter(heartbeatResponse!!, "leaseExpiresAt"))

        val confirmRequest = ConfirmDeviceSyncJobRequest(
            importedUri = "content://media/external/images/media/1",
            importedSizeBytes = 4820131L,
            leaseId = "lease-abc",
            workerRunId = "worker-run-123"
        )
        val confirmJson = moshi.adapter(ConfirmDeviceSyncJobRequest::class.java).toJson(confirmRequest)
        assertTrue(confirmJson.contains("\"leaseId\":\"lease-abc\""))
        assertTrue(confirmJson.contains("\"workerRunId\":\"worker-run-123\""))
        assertTrue(confirmJson.contains("\"importedUri\":\"content://media/external/images/media/1\""))
        assertTrue(confirmJson.contains("\"importedSizeBytes\":4820131"))

        val failRequest = FailDeviceSyncJobRequest(
            error = "HTTP 503 Response.error()",
            retryable = true,
            leaseId = "lease-abc",
            workerRunId = "worker-run-123"
        )
        val failJson = moshi.adapter(FailDeviceSyncJobRequest::class.java).toJson(failRequest)
        assertTrue(failJson.contains("\"leaseId\":\"lease-abc\""))
        assertTrue(failJson.contains("\"workerRunId\":\"worker-run-123\""))
        assertTrue(failJson.contains("\"error\":\"HTTP 503 Response.error()\""))
        assertTrue(failJson.contains("\"retryable\":true"))
    }

    @Test
    fun claimHeartbeatAndDecisionEndpointsUseTheLeaseBasedPaths() {
        val claimPost = NexusRelayApi::class.java
            .declaredMethods
            .single { it.name == "claimDeviceSyncJobs" }
            .getAnnotation(POST::class.java)
        assertEquals("api/device-sync/jobs/claim", claimPost?.value)

        val download = NexusRelayApi::class.java
            .declaredMethods
            .single { it.name == "downloadDeviceSyncJob" }
        assertEquals("api/device-sync/jobs/{jobId}/download", download.getAnnotation(GET::class.java)?.value)
        assertNotNull(download.getAnnotation(Streaming::class.java))
        assertEquals(
            "X-Device-Token",
            download.parameters[0].getAnnotation(Header::class.java)?.value
        )
        assertEquals(
            "X-Device-Sync-Lease",
            download.parameters[1].getAnnotation(Header::class.java)?.value
        )
        assertEquals(
            "jobId",
            download.parameters[2].getAnnotation(Path::class.java)?.value
        )

        val legacyDownload = NexusRelayApi::class.java
            .declaredMethods
            .single { it.name == "downloadJob" }
        assertNull(legacyDownload.getAnnotation(GET::class.java))
        assertNull(legacyDownload.getAnnotation(Streaming::class.java))

        val heartbeatPost = NexusRelayApi::class.java
            .declaredMethods
            .single { it.name == "heartbeatDeviceSyncJob" }
            .getAnnotation(POST::class.java)
        assertEquals("api/device-sync/jobs/{jobId}/heartbeat", heartbeatPost?.value)

        val confirmPost = NexusRelayApi::class.java
            .declaredMethods
            .single { it.name == "confirmDeviceSyncJob" }
            .getAnnotation(POST::class.java)
        assertEquals("api/device-sync/jobs/{jobId}/confirm", confirmPost?.value)

        val failPost = NexusRelayApi::class.java
            .declaredMethods
            .single { it.name == "failDeviceSyncJob" }
            .getAnnotation(POST::class.java)
        assertEquals("api/device-sync/jobs/{jobId}/fail", failPost?.value)
    }

    @Test
    fun nullableContractFieldsSerializeAndDeserializeAsNull() {
        val moshi = Moshi.Builder()
            .add(KotlinJsonAdapterFactory())
            .build()

        val claimRequest = ClaimDeviceSyncJobsRequest(
            workerRunId = "worker-run-null",
            limit = 1,
            leaseSeconds = 45,
            clientVersion = null
        )
        val claimJson = moshi.adapter(ClaimDeviceSyncJobsRequest::class.java)
            .serializeNulls()
            .toJson(claimRequest)
        assertTrue(claimJson.contains("\"clientVersion\":null"))

        val claimRequestDecoded = moshi.adapter(ClaimDeviceSyncJobsRequest::class.java).fromJson(
            """{"workerRunId":"worker-run-null","limit":1,"leaseSeconds":45,"clientVersion":null}"""
        )
        assertNotNull(claimRequestDecoded)
        assertNull(claimRequestDecoded!!.clientVersion)

        val claimedJobDecoded = moshi.adapter(DeviceSyncClaimedJobDto::class.java).fromJson(
            """
                {
                  "jobId": "job-null",
                  "mediaId": "media-null",
                  "fileName": "IMG_NULL.HEIC",
                  "mimeType": "image/heic",
                  "mediaType": "Image",
                  "sizeBytes": 1,
                  "sha256": null,
                  "downloadUrl": "/api/device-sync/jobs/job-null/download",
                  "attemptNumber": 1,
                  "createdAt": "2026-06-11T09:15:00Z"
                }
            """.trimIndent()
        )
        assertNotNull(claimedJobDecoded)
        assertNull(claimedJobDecoded!!.sha256)

        val heartbeatRequest = DeviceSyncHeartbeatRequest(
            leaseId = "lease-null",
            workerRunId = "worker-run-null",
            stage = "Claimed",
            progressBytes = 0L,
            totalBytes = null,
            leaseSeconds = 30
        )
        val heartbeatJson = moshi.adapter(DeviceSyncHeartbeatRequest::class.java)
            .serializeNulls()
            .toJson(heartbeatRequest)
        assertTrue(heartbeatJson.contains("\"totalBytes\":null"))

        val heartbeatRequestDecoded = moshi.adapter(DeviceSyncHeartbeatRequest::class.java).fromJson(
            """
                {
                  "leaseId": "lease-null",
                  "workerRunId": "worker-run-null",
                  "stage": "Claimed",
                  "progressBytes": 0,
                  "totalBytes": null,
                  "leaseSeconds": 30
                }
            """.trimIndent()
        )
        assertNotNull(heartbeatRequestDecoded)
        assertNull(heartbeatRequestDecoded!!.totalBytes)
    }

    @Test
    fun testRegisterDeviceRequestSerializesFolderScope() {
        val moshi = Moshi.Builder()
            .add(KotlinJsonAdapterFactory())
            .build()
        val adapter = moshi.adapter(RegisterDeviceRequest::class.java)

        val json = adapter.toJson(
            RegisterDeviceRequest(
                deviceName = "Pixel",
                fcmToken = null,
                wifiOnly = true,
                syncScope = DeviceSyncScope.Folder,
                scopedFolderId = "folder-123"
            )
        )

        assertTrue(json.contains("\"syncScope\":\"Folder\""))
        assertTrue(json.contains("\"scopedFolderId\":\"folder-123\""))
    }

    @Test
    fun testPairingCodeParser_withValidJson_returnsPayload() {
        val json = """
            {
              "baseUrl": "https://relay.xuantruong.org",
              "code": "12345678"
            }
        """.trimIndent()
        val parsed = PairingCodeParser.parse(json)
        assertNotNull(parsed)
        assertEquals("https://relay.xuantruong.org", parsed!!.baseUrl)
        assertEquals("12345678", parsed.code)
    }

    @Test
    fun testPairingCodeParser_withRawCode_returnsPayloadWithEmptyBaseUrl() {
        val rawCode = " 87654321 "
        val parsed = PairingCodeParser.parse(rawCode)
        assertNotNull(parsed)
        assertEquals("", parsed!!.baseUrl)
        assertEquals("87654321", parsed.code)
    }

    @Test
    fun testPairingCodeParser_withEmptyCode_returnsNull() {
        assertNull(PairingCodeParser.parse(""))
        assertNull(PairingCodeParser.parse("   "))
    }

    @Test
    fun testPairingCodeParser_withMalformedJson_returnsNull() {
        val badJson = "{\"baseUrl\": \"url\", \"code\": \"\"}"
        assertNull(PairingCodeParser.parse(badJson))

        val brokenJson = "{\"baseUrl\": "
        assertNull(PairingCodeParser.parse(brokenJson))
    }

    private fun getter(instance: Any, propertyName: String): Any? {
        val methodName = "get" + propertyName.replaceFirstChar { it.uppercaseChar() }
        return instance.javaClass.methods.single { it.name == methodName && it.parameterCount == 0 }.invoke(instance)
    }
}
