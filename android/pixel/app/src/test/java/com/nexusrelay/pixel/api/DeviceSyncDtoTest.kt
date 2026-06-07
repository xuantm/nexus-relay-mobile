package com.nexusrelay.pixel.api

import com.nexusrelay.pixel.ui.resolveFcmTokenForRegistration
import com.squareup.moshi.Moshi
import com.squareup.moshi.Types
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import retrofit2.http.POST

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
    fun testPendingJobsJsonDeserialization() {
        val json = """
            [
              {
                "jobId": "8af63b26-f7af-4fe0-8cb5-5dc43edcc9ef",
                "mediaId": "94aa00ac-219a-4d65-8ff4-11ffc7a042e1",
                "fileName": "IMG_1001.HEIC",
                "mimeType": "image/heic",
                "mediaType": "Image",
                "sizeBytes": 4820131,
                "sha256": "3a6eb0790f39ac87c94f3856b2dd2c5d110e6811602261a9a923d3bb23adc8b7",
                "downloadUrl": "/api/device-sync/jobs/8af63b26-f7af-4fe0-8cb5-5dc43edcc9ef/download",
                "createdAt": "2026-06-02T00:00:00Z"
              }
            ]
        """.trimIndent()

        val moshi = Moshi.Builder()
            .add(KotlinJsonAdapterFactory())
            .build()

        val listType = Types.newParameterizedType(List::class.java, DeviceSyncJobDto::class.java)
        val adapter = moshi.adapter<List<DeviceSyncJobDto>>(listType)

        val jobs = adapter.fromJson(json)
        assertNotNull(jobs)
        assertEquals(1, jobs!!.size)

        val job = jobs[0]
        assertEquals("8af63b26-f7af-4fe0-8cb5-5dc43edcc9ef", job.jobId)
        assertEquals("94aa00ac-219a-4d65-8ff4-11ffc7a042e1", job.mediaId)
        assertEquals("IMG_1001.HEIC", job.fileName)
        assertEquals("image/heic", job.mimeType)
        assertEquals("Image", job.mediaType)
        assertEquals(4820131L, job.sizeBytes)
        assertEquals("3a6eb0790f39ac87c94f3856b2dd2c5d110e6811602261a9a923d3bb23adc8b7", job.sha256)
        assertEquals("/api/device-sync/jobs/8af63b26-f7af-4fe0-8cb5-5dc43edcc9ef/download", job.downloadUrl)
        assertEquals("2026-06-02T00:00:00Z", job.createdAt)
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
}
