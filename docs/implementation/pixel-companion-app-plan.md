# Pixel Companion App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Android Pixel companion app that receives NexusRelay device-sync jobs, downloads media through the backend, imports media into Android MediaStore, and confirms completion.

**Architecture:** The Pixel app treats FCM as a wake-up signal and the NexusRelay backend as the durable queue. WorkManager performs all sync execution, while a periodic polling worker recovers missed FCM events.

**Tech Stack:** Kotlin, Android Gradle Plugin, Jetpack Compose, WorkManager, Firebase Messaging, Retrofit, OkHttp, Moshi, DataStore, AndroidX Security, Android MediaStore.

---

## Scope

This plan covers only the mobile repo implementation for the Pixel app.

Included:

- Android project scaffold under `android/pixel`.
- Setup/status UI.
- Device registration against NexusRelay backend.
- Secure device token storage.
- FCM receiver.
- WorkManager sync worker.
- Polling fallback.
- Device sync API client.
- Local sync ledger.
- MediaStore import for image and video.
- Debug APK build.

Excluded:

- NexusRelay backend implementation.
- iPhone uploader app.
- Play Store release.
- Google Drive direct access.
- Two-way sync from Pixel to NexusRelay.

## Expected Repository Layout

```text
android/
  pixel/
    settings.gradle.kts
    build.gradle.kts
    app/
      build.gradle.kts
      src/main/AndroidManifest.xml
      src/main/java/com/nexusrelay/pixel/
        MainActivity.kt
        NexusRelayApp.kt
        api/
        auth/
        media/
        sync/
        storage/
        ui/
docs/
  architecture/pixel-companion-sync.md
  contracts/device-sync-api.md
  implementation/pixel-companion-app-plan.md
```

## Worker Assignment Map

- Worker A: Part 1 Android scaffold and build baseline.
- Worker B: Part 2 API client and DTOs.
- Worker C: Part 3 token storage, settings store, and setup UI.
- Worker D: Part 4 local ledger.
- Worker E: Part 5 MediaStore importer.
- Worker F: Part 6 WorkManager sync worker.
- Worker G: Part 7 FCM receiver.
- Worker H: Part 8 polling fallback and status UI.
- Worker I: Part 9 integration verification and docs.

Parts 2, 3, and 4 can start after Part 1. Parts 5 and 6 should start after Part 2. Parts 7 and 8 should start after Part 6 defines the sync enqueue API.

## Shared Constants

Use these defaults unless the owner changes them:

```text
Package name: com.nexusrelay.pixel
Min SDK: 29
Target SDK: 35
App name: NexusRelay Pixel
Image destination: Pictures/NexusRelay
Video destination: Movies/NexusRelay
Polling interval: 15 minutes
Device token header: X-Device-Token
```

## Part 1: Android Project Scaffold

**Worker:** Android scaffold worker.

**Files:**

- Create: `android/pixel/settings.gradle.kts`
- Create: `android/pixel/build.gradle.kts`
- Create: `android/pixel/app/build.gradle.kts`
- Create: `android/pixel/app/src/main/AndroidManifest.xml`
- Create: `android/pixel/app/src/main/java/com/nexusrelay/pixel/NexusRelayApp.kt`
- Create: `android/pixel/app/src/main/java/com/nexusrelay/pixel/MainActivity.kt`

- [ ] **Step 1: Create Gradle Android project**

Create a Kotlin Android app at:

```text
android/pixel
```

Use package:

```text
com.nexusrelay.pixel
```

- [ ] **Step 2: Configure app module**

Configure:

```text
minSdk = 29
targetSdk = 35
compileSdk = 35
```

Add dependencies:

```text
androidx.activity:activity-compose
androidx.compose.material3:material3
androidx.lifecycle:lifecycle-runtime-ktx
androidx.work:work-runtime-ktx
androidx.datastore:datastore-preferences
androidx.security:security-crypto
com.squareup.retrofit2:retrofit
com.squareup.retrofit2:converter-moshi
com.squareup.okhttp3:logging-interceptor
com.google.firebase:firebase-messaging
```

- [ ] **Step 3: Add manifest**

Add permissions:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

Register application class:

```xml
<application
    android:name=".NexusRelayApp"
    android:theme="@style/Theme.NexusRelayPixel">
</application>
```

- [ ] **Step 4: Add minimal Compose screen**

`MainActivity` should render:

```text
NexusRelay Pixel
Backend URL input
Device name input
Register button
Sync now button disabled until registered
```

- [ ] **Step 5: Verify scaffold build**

Run:

```bash
cd android/pixel
./gradlew assembleDebug
```

Expected:

```text
BUILD SUCCESSFUL
```

Commit:

```bash
git add android/pixel
git commit -m "feat: scaffold pixel android app"
```

## Part 2: Device Sync API Client

**Worker:** Android API worker.

**Depends on:** Part 1.

**Files:**

- Create: `android/pixel/app/src/main/java/com/nexusrelay/pixel/api/DeviceSyncDtos.kt`
- Create: `android/pixel/app/src/main/java/com/nexusrelay/pixel/api/NexusRelayApi.kt`
- Create: `android/pixel/app/src/main/java/com/nexusrelay/pixel/api/ApiClientFactory.kt`
- Test: `android/pixel/app/src/test/java/com/nexusrelay/pixel/api/DeviceSyncDtoTest.kt`

- [ ] **Step 1: Add DTOs**

```kotlin
data class RegisterDeviceRequest(
    val deviceName: String,
    val fcmToken: String?,
    val wifiOnly: Boolean
)

data class RegisterDeviceResponse(
    val targetId: String,
    val deviceToken: String
)

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

data class ConfirmDeviceSyncJobRequest(
    val importedUri: String?,
    val importedSizeBytes: Long?
)

data class FailDeviceSyncJobRequest(
    val error: String
)
```

- [ ] **Step 2: Add Retrofit interface**

```kotlin
interface NexusRelayApi {
    @POST("api/device-sync/register")
    suspend fun registerDevice(@Body request: RegisterDeviceRequest): RegisterDeviceResponse

    @GET("api/device-sync/jobs/pending")
    suspend fun pendingJobs(@Header("X-Device-Token") deviceToken: String): List<DeviceSyncJobDto>

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
```

- [ ] **Step 3: Add API client factory**

Factory inputs:

```text
backendBaseUrl
debugLoggingEnabled
```

Rules:

- Ensure base URL ends with `/`.
- Use Moshi converter.
- Use OkHttp logging only for debug builds.
- Set connect/read/write timeouts to 60 seconds for large media transfers.

- [ ] **Step 4: Add DTO serialization test**

Test that sample pending-job JSON from `docs/contracts/device-sync-api.md` parses into `DeviceSyncJobDto`.

- [ ] **Step 5: Verify**

Run:

```bash
cd android/pixel
./gradlew test assembleDebug
```

Expected:

```text
BUILD SUCCESSFUL
```

Commit:

```bash
git add android/pixel
git commit -m "feat: add device sync api client"
```

## Part 3: Secure Settings And Registration UI

**Worker:** Android settings worker.

**Depends on:** Parts 1 and 2.

**Files:**

- Create: `android/pixel/app/src/main/java/com/nexusrelay/pixel/auth/DeviceTokenStore.kt`
- Create: `android/pixel/app/src/main/java/com/nexusrelay/pixel/storage/AppSettingsStore.kt`
- Create: `android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/SetupScreen.kt`
- Modify: `android/pixel/app/src/main/java/com/nexusrelay/pixel/MainActivity.kt`

- [ ] **Step 1: Store app settings**

Persist:

```text
backendBaseUrl
targetId
deviceName
wifiOnly
lastSuccessfulSyncAt
```

Use DataStore Preferences.

- [ ] **Step 2: Store device token securely**

Use AndroidX Security encrypted preferences.

Required methods:

```kotlin
suspend fun saveDeviceToken(token: String)
suspend fun getDeviceToken(): String?
suspend fun clear()
```

- [ ] **Step 3: Build setup screen**

Fields:

```text
Backend URL
Device name
Wi-Fi only checkbox
Register button
```

Button behavior:

```text
Call registerDevice.
Save targetId, settings, and raw device token.
Enable Sync now.
Show registration result.
```

- [ ] **Step 4: Verify**

Run:

```bash
cd android/pixel
./gradlew test assembleDebug
```

Expected:

```text
BUILD SUCCESSFUL
```

Commit:

```bash
git add android/pixel
git commit -m "feat: add pixel device registration"
```

## Part 4: Local Sync Ledger

**Worker:** Android ledger worker.

**Depends on:** Part 1.

**Files:**

- Create: `android/pixel/app/src/main/java/com/nexusrelay/pixel/storage/LocalSyncLedger.kt`
- Test: `android/pixel/app/src/test/java/com/nexusrelay/pixel/storage/LocalSyncLedgerTest.kt`

- [ ] **Step 1: Define local record**

```kotlin
data class LocalSyncRecord(
    val jobId: String,
    val mediaId: String,
    val fileName: String,
    val mimeType: String,
    val sizeBytes: Long,
    val sha256: String?,
    val status: LocalSyncStatus,
    val localUri: String?,
    val lastAttemptAt: Long,
    val lastError: String?
)

enum class LocalSyncStatus {
    Queued,
    Downloading,
    Imported,
    ConfirmPending,
    Confirmed,
    Failed
}
```

- [ ] **Step 2: Implement ledger operations**

Required methods:

```kotlin
suspend fun upsert(record: LocalSyncRecord)
suspend fun markDownloading(jobId: String)
suspend fun markImported(jobId: String, localUri: String)
suspend fun markConfirmPending(jobId: String, localUri: String)
suspend fun markConfirmed(jobId: String)
suspend fun markFailed(jobId: String, error: String)
suspend fun get(jobId: String): LocalSyncRecord?
suspend fun listRecent(limit: Int): List<LocalSyncRecord>
```

Use DataStore JSON for MVP. If job count becomes large, replace with Room in a later migration.

- [ ] **Step 3: Verify ledger tests**

Run:

```bash
cd android/pixel
./gradlew test
```

Expected:

```text
BUILD SUCCESSFUL
```

Commit:

```bash
git add android/pixel
git commit -m "feat: add local sync ledger"
```

## Part 5: MediaStore Importer

**Worker:** Android media worker.

**Depends on:** Part 1.

**Files:**

- Create: `android/pixel/app/src/main/java/com/nexusrelay/pixel/media/MediaStoreImporter.kt`
- Test: `android/pixel/app/src/androidTest/java/com/nexusrelay/pixel/media/MediaStoreImporterTest.kt`

- [ ] **Step 1: Implement importer**

Rules:

- Images go to `Pictures/NexusRelay`.
- Videos go to `Movies/NexusRelay`.
- Set `IS_PENDING=1` before writing.
- Set `IS_PENDING=0` only after the stream copy succeeds.
- Delete the pending MediaStore row if copy fails.
- Return the final `content://` URI.

- [ ] **Step 2: Add file type routing**

Use MIME type:

```text
image/* -> MediaStore.Images
video/* -> MediaStore.Video
other -> fail with unsupported media type
```

- [ ] **Step 3: Add instrumentation test**

Use a tiny generated byte stream and verify that insert returns a non-null URI. Clean up the inserted URI after test.

- [ ] **Step 4: Verify**

Run:

```bash
cd android/pixel
./gradlew connectedDebugAndroidTest
```

Expected:

```text
Tests pass on connected Pixel or emulator.
```

If no device is connected, record that this verification was not run and still run:

```bash
cd android/pixel
./gradlew test assembleDebug
```

Commit:

```bash
git add android/pixel
git commit -m "feat: add mediastore importer"
```

## Part 6: WorkManager Sync Worker

**Worker:** Android sync worker.

**Depends on:** Parts 2, 3, 4, and 5.

**Files:**

- Create: `android/pixel/app/src/main/java/com/nexusrelay/pixel/sync/DeviceSyncRepository.kt`
- Create: `android/pixel/app/src/main/java/com/nexusrelay/pixel/sync/SyncWorker.kt`
- Test: `android/pixel/app/src/test/java/com/nexusrelay/pixel/sync/DeviceSyncRepositoryTest.kt`

- [ ] **Step 1: Add sync repository**

Responsibilities:

```text
Read backend URL and device token.
Fetch pending jobs.
Mark job downloading.
Download job stream.
Import into MediaStore.
Confirm import.
Report failure when a job-level error occurs.
Update local ledger after every state change.
```

- [ ] **Step 2: Add worker logic**

Worker loop:

```text
jobs = pendingJobs()
for job in jobs:
  ledger.upsert(Queued)
  api.markDownloading(jobId)
  ledger.markDownloading(jobId)
  stream = api.downloadJob(jobId)
  localUri = mediaStoreImporter.importMedia(job.fileName, job.mimeType, responseStream, job.sizeBytes)
  ledger.markConfirmPending(jobId, localUri)
  api.confirm(jobId, localUri, job.sizeBytes)
  ledger.markConfirmed(jobId)
```

Failure behavior:

```text
Network/backend-wide failure -> WorkManager Result.retry()
Single job failure -> call fail endpoint, mark local Failed, continue next job
Confirm failure after import -> keep ConfirmPending and retry confirm on next sync
```

- [ ] **Step 3: Add constraints**

Default constraints:

```text
Network connected
Battery not low
Storage not low
```

If Wi-Fi only is enabled:

```text
Network unmetered
```

- [ ] **Step 4: Add enqueue API**

Expose:

```kotlin
fun enqueueOneTimeSync(context: Context)
```

Use unique work name:

```text
nexus-relay-pixel-sync
```

Policy:

```text
ExistingWorkPolicy.KEEP
```

- [ ] **Step 5: Verify**

Run:

```bash
cd android/pixel
./gradlew test assembleDebug
```

Expected:

```text
BUILD SUCCESSFUL
```

Commit:

```bash
git add android/pixel
git commit -m "feat: add workmanager device sync"
```

## Part 7: FCM Receiver

**Worker:** Android FCM worker.

**Depends on:** Part 6.

**Files:**

- Create: `android/pixel/app/src/main/java/com/nexusrelay/pixel/sync/FcmReceiverService.kt`
- Modify: `android/pixel/app/src/main/AndroidManifest.xml`
- Modify: `android/pixel/app/src/main/java/com/nexusrelay/pixel/sync/DeviceSyncRepository.kt`

- [ ] **Step 1: Add Firebase messaging service**

Behavior:

```text
When data.type == device_sync_job_available:
  enqueue one-time sync
```

- [ ] **Step 2: Handle new FCM token**

When Firebase rotates the token:

```text
Save token locally.
Note: Backend FCM token refresh is not yet supported in the current MVP. The new token is stored locally and will be sent to the backend during the next manual registration/pairing flow.
```

- [ ] **Step 3: Register service in manifest**

```xml
<service
    android:name=".sync.FcmReceiverService"
    android:exported="false">
    <intent-filter>
        <action android:name="com.google.firebase.MESSAGING_EVENT" />
    </intent-filter>
</service>
```

- [ ] **Step 4: Firebase config handling**

`google-services.json` is required for FCM builds but must not be committed.

Document local setup in:

```text
android/pixel/README.md
```

- [ ] **Step 5: Verify**

Run:

```bash
cd android/pixel
./gradlew test assembleDebug
```

Expected:

```text
BUILD SUCCESSFUL when google-services.json is present or Firebase plugin is disabled for local non-FCM builds.
```

Commit:

```bash
git add android/pixel
git commit -m "feat: trigger sync from fcm"
```

## Part 8: Polling Fallback And Status UI

**Worker:** Android UI/polling worker.

**Depends on:** Parts 3, 4, and 6.

**Files:**

- Create: `android/pixel/app/src/main/java/com/nexusrelay/pixel/sync/PollWorker.kt`
- Create: `android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/StatusScreen.kt`
- Modify: `android/pixel/app/src/main/java/com/nexusrelay/pixel/NexusRelayApp.kt`
- Modify: `android/pixel/app/src/main/java/com/nexusrelay/pixel/MainActivity.kt`

- [ ] **Step 1: Add periodic worker**

Schedule:

```text
Every 15 minutes
Unique work name: nexus-relay-pixel-poll
Policy: UPDATE
```

The poll worker should enqueue the same one-time sync path used by FCM.

- [ ] **Step 2: Start polling after registration**

After successful device registration:

```text
Schedule periodic polling.
Run one immediate sync.
```

- [ ] **Step 3: Add status screen**

Show:

```text
Backend URL
Device name
Registration status
Last successful sync time
Recent confirmed count
Recent failed count
Sync now button
Wi-Fi only toggle
```

- [ ] **Step 4: Verify**

Run:

```bash
cd android/pixel
./gradlew test assembleDebug
```

Expected:

```text
BUILD SUCCESSFUL
```

Commit:

```bash
git add android/pixel
git commit -m "feat: add polling fallback and status ui"
```

## Part 9: Integration Verification And Release Notes

**Worker:** Integration worker.

**Depends on:** Parts 1 through 8.

**Files:**

- Create: `android/pixel/README.md`
- Create: `docs/implementation/pixel-manual-verification.md`

- [ ] **Step 1: Build APK**

Run:

```bash
cd android/pixel
./gradlew test assembleDebug
```

Expected:

```text
BUILD SUCCESSFUL
```

- [ ] **Step 2: Install on Pixel**

Run:

```bash
adb install -r android/pixel/app/build/outputs/apk/debug/app-debug.apk
```

Expected:

```text
Success
```

- [ ] **Step 3: Register device**

Manual steps:

```text
Open app.
Enter backend URL.
Enter device name Pixel XL.
Register device.
Confirm app shows registered status.
```

- [ ] **Step 4: Manual sync test without FCM**

Manual steps:

```text
Upload a small image to NexusRelay.
Wait until backend marks media Completed and creates DeviceSyncJob.
Tap Sync now in Pixel app.
Confirm image appears in Pictures/NexusRelay.
Confirm backend job becomes ImportedConfirmed.
```

- [ ] **Step 5: FCM wake-up test**

Manual steps:

```text
Configure Firebase.
Put app in background.
Upload a small image.
Confirm FCM triggers WorkManager sync.
Confirm backend job becomes ImportedConfirmed.
```

- [ ] **Step 6: Polling fallback test**

Manual steps:

```text
Disable FCM config or remove FCM token.
Upload a small image.
Wait for polling or use Sync now.
Confirm media imports successfully.
```

- [ ] **Step 7: Retry test**

Manual steps:

```text
Start a video sync.
Disable network during download.
Re-enable network.
Run Sync now.
Confirm the app does not create duplicate imported media for the same job.
```

- [ ] **Step 8: Document results**

Record:

```text
Backend commit tested
Mobile commit tested
Pixel Android version
FCM enabled or disabled
Image test result
Video test result
Retry test result
Known issues
```

Commit:

```bash
git add android/pixel docs
git commit -m "docs: add pixel app verification guide"
```

## Completion Criteria

The Pixel app MVP is complete when:

- It builds a debug APK.
- It registers a Pixel target with NexusRelay.
- It stores the device token securely.
- It lists pending backend jobs.
- It downloads media only through NexusRelay.
- It imports images and videos into MediaStore.
- It confirms `ImportedConfirmed` after import.
- FCM can trigger sync when configured.
- Polling fallback can sync without FCM.
- Manual `Sync now` works.
- Retry avoids duplicate imports for the same job.
