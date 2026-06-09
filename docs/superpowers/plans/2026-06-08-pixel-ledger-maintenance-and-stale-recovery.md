# Pixel Ledger Maintenance And Stale Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Pixel-only ledger maintenance actions and bounded stale-state recovery so local sync records do not live forever in `Queued`, `Downloading`, `Imported`, or `ConfirmPending`.

**Architecture:** Keep `LocalSyncLedger` as the Pixel-side recovery source of truth and preserve the current confirm-first behavior that avoids duplicate imports. Extend ledger records with backward-compatible retry metadata, add repository policies that only fail truly stale jobs, and expose safe maintenance actions in the Settings tab without touching pairing, backend settings, or already imported local media.

**Tech Stack:** Android Kotlin, Jetpack Compose, DataStore Preferences, Moshi, WorkManager, JUnit, Mockito Kotlin.

---

## File Structure

Mobile repo: `G:/workspace/nexus-relay-mobile`

- Modify: `android/pixel/app/src/main/java/com/nexusrelay/pixel/storage/LocalSyncLedger.kt`
  - Add backward-compatible retry metadata, active/history helpers, and selective ledger cleanup APIs.
- Modify: `android/pixel/app/src/main/java/com/nexusrelay/pixel/sync/DeviceSyncRepository.kt`
  - Add stale-state timeout and retry-budget policy while preserving the current import/confirm flow.
- Modify: `android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/PixelUiModels.kt`
  - Add maintenance preview helpers for the Settings screen.
- Modify: `android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/PixelUiComponents.kt`
  - Add confirmation dialogs for clearing history and resetting the local ledger.
- Modify: `android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/StatusScreen.kt`
  - Wire Settings actions to the repository and show maintenance state safely.
- Modify: `android/pixel/app/src/test/java/com/nexusrelay/pixel/storage/LocalSyncLedgerTest.kt`
  - Cover metadata defaults, retry bookkeeping, selective cleanup, and reset behavior.
- Modify: `android/pixel/app/src/test/java/com/nexusrelay/pixel/sync/DeviceSyncRepositoryTest.kt`
  - Cover stale `Downloading`, orphaned `Queued`, bounded `ConfirmPending` / `Imported` retries, and reset safety.
- Create: `android/pixel/app/src/test/java/com/nexusrelay/pixel/ui/PixelUiModelsTest.kt`
  - Cover maintenance preview counts and button enablement state.

---

## Task 1: Ledger Contract Tests

**Files:**
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/test/java/com/nexusrelay/pixel/storage/LocalSyncLedgerTest.kt`

- [ ] **Step 1: Add failing tests for retry metadata and selective cleanup**

Add these tests to `LocalSyncLedgerTest.kt`:

```kotlin
@OptIn(ExperimentalCoroutinesApi::class)
@Test
fun clearHistoryRemovesOnlyConfirmedAndFailedRecords() = runTest {
    val tempFile = File(tempFolder.root, "clear_history.preferences_pb")
    val dataStore = PreferenceDataStoreFactory.create { tempFile }
    val ledger = LocalSyncLedger(TestContext(), dataStore)

    ledger.upsert(
        LocalSyncRecord(
            jobId = "confirmed",
            mediaId = "media-confirmed",
            fileName = "confirmed.jpg",
            mimeType = "image/jpeg",
            sizeBytes = 1L,
            sha256 = null,
            status = LocalSyncStatus.Confirmed,
            localUri = "content://confirmed",
            lastAttemptAt = 10L,
            lastError = null,
            isLocalDeleted = false,
            statusEnteredAt = 10L,
            retryCount = 0
        )
    )
    ledger.upsert(
        LocalSyncRecord(
            jobId = "failed",
            mediaId = "media-failed",
            fileName = "failed.jpg",
            mimeType = "image/jpeg",
            sizeBytes = 1L,
            sha256 = null,
            status = LocalSyncStatus.Failed,
            localUri = null,
            lastAttemptAt = 20L,
            lastError = "timeout",
            isLocalDeleted = false,
            statusEnteredAt = 20L,
            retryCount = 2
        )
    )
    ledger.upsert(
        LocalSyncRecord(
            jobId = "confirm-pending",
            mediaId = "media-confirm-pending",
            fileName = "pending.jpg",
            mimeType = "image/jpeg",
            sizeBytes = 1L,
            sha256 = null,
            status = LocalSyncStatus.ConfirmPending,
            localUri = "content://pending",
            lastAttemptAt = 30L,
            lastError = null,
            isLocalDeleted = false,
            statusEnteredAt = 30L,
            retryCount = 1
        )
    )

    ledger.clearHistory()

    assertNull(ledger.get("confirmed"))
    assertNull(ledger.get("failed"))
    assertEquals(LocalSyncStatus.ConfirmPending, ledger.get("confirm-pending")?.status)
}

@OptIn(ExperimentalCoroutinesApi::class)
@Test
fun recordRetriableFailurePreservesStatusAndIncrementsRetryCount() = runTest {
    val tempFile = File(tempFolder.root, "retriable.preferences_pb")
    val dataStore = PreferenceDataStoreFactory.create { tempFile }
    val ledger = LocalSyncLedger(TestContext(), dataStore)

    ledger.upsert(
        LocalSyncRecord(
            jobId = "job-1",
            mediaId = "media-1",
            fileName = "image.jpg",
            mimeType = "image/jpeg",
            sizeBytes = 100L,
            sha256 = null,
            status = LocalSyncStatus.ConfirmPending,
            localUri = "content://media/1",
            lastAttemptAt = 100L,
            lastError = null,
            isLocalDeleted = false,
            statusEnteredAt = 80L,
            retryCount = 0
        )
    )

    ledger.recordRetriableFailure("job-1", "Confirm timeout", now = 200L)

    val updated = ledger.get("job-1")!!
    assertEquals(LocalSyncStatus.ConfirmPending, updated.status)
    assertEquals("Confirm timeout", updated.lastError)
    assertEquals(200L, updated.lastAttemptAt)
    assertEquals(80L, updated.statusEnteredAt)
    assertEquals(1, updated.retryCount)
}

@OptIn(ExperimentalCoroutinesApi::class)
@Test
fun hasActiveRecordsIgnoresConfirmedAndFailedHistory() = runTest {
    val tempFile = File(tempFolder.root, "active.preferences_pb")
    val dataStore = PreferenceDataStoreFactory.create { tempFile }
    val ledger = LocalSyncLedger(TestContext(), dataStore)

    ledger.upsert(
        LocalSyncRecord(
            jobId = "history",
            mediaId = "media-history",
            fileName = "history.jpg",
            mimeType = "image/jpeg",
            sizeBytes = 1L,
            sha256 = null,
            status = LocalSyncStatus.Failed,
            localUri = null,
            lastAttemptAt = 1L,
            lastError = "fail",
            isLocalDeleted = false,
            statusEnteredAt = 1L,
            retryCount = 1
        )
    )
    assertFalse(ledger.hasActiveRecords())

    ledger.upsert(
        LocalSyncRecord(
            jobId = "active",
            mediaId = "media-active",
            fileName = "active.jpg",
            mimeType = "image/jpeg",
            sizeBytes = 1L,
            sha256 = null,
            status = LocalSyncStatus.Queued,
            localUri = null,
            lastAttemptAt = 2L,
            lastError = null,
            isLocalDeleted = false,
            statusEnteredAt = 2L,
            retryCount = 0
        )
    )
    assertTrue(ledger.hasActiveRecords())
}
```

- [ ] **Step 2: Run the ledger tests to confirm they fail**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/android/pixel
./gradlew.bat testDebugUnitTest --tests "com.nexusrelay.pixel.storage.LocalSyncLedgerTest"
```

Expected: FAIL because `statusEnteredAt`, `retryCount`, `recordRetriableFailure`, `clearHistory`, and `hasActiveRecords` do not exist yet.

- [ ] **Step 3: Commit the failing test baseline**

```bash
git add android/pixel/app/src/test/java/com/nexusrelay/pixel/storage/LocalSyncLedgerTest.kt
git commit -m "test: cover pixel ledger maintenance contract"
```

---

## Task 2: Ledger Metadata And Cleanup APIs

**Files:**
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/main/java/com/nexusrelay/pixel/storage/LocalSyncLedger.kt`
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/test/java/com/nexusrelay/pixel/storage/LocalSyncLedgerTest.kt`

- [ ] **Step 1: Extend `LocalSyncRecord` with backward-compatible metadata**

Update the record and add status groups near the top of `LocalSyncLedger.kt`:

```kotlin
internal data class LocalSyncRecord(
    val jobId: String,
    val mediaId: String,
    val fileName: String,
    val mimeType: String,
    val sizeBytes: Long,
    val sha256: String?,
    val status: LocalSyncStatus,
    val localUri: String?,
    val lastAttemptAt: Long,
    val lastError: String?,
    val isLocalDeleted: Boolean = false,
    val statusEnteredAt: Long = lastAttemptAt,
    val retryCount: Int = 0
)

private val activeStatuses = setOf(
    LocalSyncStatus.Queued,
    LocalSyncStatus.Downloading,
    LocalSyncStatus.Imported,
    LocalSyncStatus.ConfirmPending
)

private val historyStatuses = setOf(
    LocalSyncStatus.Confirmed,
    LocalSyncStatus.Failed
)
```

Why this shape:
- `statusEnteredAt` measures how long the record has been in its current state.
- `retryCount` lets the repository stop infinite retries.
- Defaults keep old JSON records readable through Moshi without a destructive migration.

- [ ] **Step 2: Add cleanup and retry-bookkeeping methods**

Add these methods to `LocalSyncLedger.kt`:

```kotlin
    suspend fun recordRetriableFailure(jobId: String, error: String, now: Long = System.currentTimeMillis()) {
        val record = get(jobId) ?: return
        upsert(
            record.copy(
                lastError = error,
                lastAttemptAt = now,
                retryCount = record.retryCount + 1
            )
        )
    }

    suspend fun markQueued(jobId: String, now: Long = System.currentTimeMillis()) {
        val record = get(jobId) ?: return
        upsert(
            record.copy(
                status = LocalSyncStatus.Queued,
                lastError = null,
                lastAttemptAt = now,
                statusEnteredAt = now,
                retryCount = 0
            )
        )
    }

    suspend fun clearHistory() {
        removeByStatuses(*historyStatuses.toTypedArray())
    }

    suspend fun removeByStatuses(vararg statuses: LocalSyncStatus) {
        val statusSet = statuses.toSet()
        val updated = getRecordsMap().filterValues { it.status !in statusSet }
        saveRecordsMap(updated)
    }

    suspend fun hasActiveRecords(): Boolean {
        return getRecordsMap().values.any { it.status in activeStatuses }
    }
```

Also update the existing transition methods so status changes reset retry state and refresh `statusEnteredAt`:

```kotlin
    suspend fun markDownloading(jobId: String) {
        val record = get(jobId) ?: return
        val now = System.currentTimeMillis()
        upsert(record.copy(
            status = LocalSyncStatus.Downloading,
            lastError = null,
            lastAttemptAt = now,
            statusEnteredAt = now,
            retryCount = 0
        ))
    }
```

Apply the same `now/statusEnteredAt/retryCount = 0` pattern to `markImported`, `markConfirmPending`, `markConfirmed`, and `markFailed`.

- [ ] **Step 3: Re-run the ledger tests**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/android/pixel
./gradlew.bat testDebugUnitTest --tests "com.nexusrelay.pixel.storage.LocalSyncLedgerTest"
```

Expected: PASS.

- [ ] **Step 4: Commit the ledger implementation**

```bash
git add android/pixel/app/src/main/java/com/nexusrelay/pixel/storage/LocalSyncLedger.kt android/pixel/app/src/test/java/com/nexusrelay/pixel/storage/LocalSyncLedgerTest.kt
git commit -m "feat: add pixel ledger maintenance metadata"
```

---

## Task 3: Repository Stale-Recovery Tests

**Files:**
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/test/java/com/nexusrelay/pixel/sync/DeviceSyncRepositoryTest.kt`

- [ ] **Step 1: Add failing tests for stale-state policy**

Add these tests to `DeviceSyncRepositoryTest.kt`:

```kotlin
@Test
fun testSyncPendingJobs_StaleQueuedRecordMissingFromBackend_MarksFailed() = runTest {
    setupConfiguredMocks()
    whenever(mockApi.pendingJobs("token-123")).thenReturn(emptyList())
    whenever(mockLedger.listByStatuses(LocalSyncStatus.ConfirmPending, LocalSyncStatus.Imported)).thenReturn(emptyList())

    val staleQueued = LocalSyncRecord(
        jobId = "job-queued-stale",
        mediaId = "media-queued-stale",
        fileName = "queued.jpg",
        mimeType = "image/jpeg",
        sizeBytes = 10L,
        sha256 = null,
        status = LocalSyncStatus.Queued,
        localUri = null,
        lastAttemptAt = 0L,
        lastError = null,
        isLocalDeleted = false,
        statusEnteredAt = 0L,
        retryCount = 0
    )
    whenever(mockLedger.listByStatuses(LocalSyncStatus.Queued)).thenReturn(listOf(staleQueued))

    val repository = createRepository()
    val result = repository.syncPendingJobs()

    assertTrue(result)
    verify(mockLedger).markFailed(eq("job-queued-stale"), eq("Sync timed out before download started"))
}

@Test
fun testSyncPendingJobs_ConfirmPendingRetriableFailureBeforeTimeout_PreservesStateAndIncrementsRetryCount() = runTest {
    setupConfiguredMocks()
    whenever(mockApi.pendingJobs("token-123")).thenReturn(emptyList())

    val now = System.currentTimeMillis()
    val record = LocalSyncRecord(
        jobId = "job-confirm-retry",
        mediaId = "media-confirm-retry",
        fileName = "confirm.jpg",
        mimeType = "image/jpeg",
        sizeBytes = 100L,
        sha256 = null,
        status = LocalSyncStatus.ConfirmPending,
        localUri = "content://media/external/images/media/confirm-retry",
        lastAttemptAt = now,
        lastError = null,
        isLocalDeleted = false,
        statusEnteredAt = now,
        retryCount = 1
    )
    whenever(mockLedger.listByStatuses(LocalSyncStatus.ConfirmPending, LocalSyncStatus.Imported)).thenReturn(listOf(record))
    whenever(mockApi.confirm(eq("token-123"), eq("job-confirm-retry"), any())).thenAnswer { throw IOException("Confirm timeout") }

    val repository = createRepository()
    try {
        repository.syncPendingJobs()
    } catch (_: IOException) {
    }

    verify(mockLedger).recordRetriableFailure(eq("job-confirm-retry"), eq("Confirm timeout"), any())
    verify(mockLedger, never()).markFailed(eq("job-confirm-retry"), any())
    verify(mockApi, never()).fail(any(), eq("job-confirm-retry"), any())
}

@Test
fun testSyncPendingJobs_ConfirmPendingTimedOut_MarksFailedAndReportsBackend() = runTest {
    setupConfiguredMocks()
    whenever(mockApi.pendingJobs("token-123")).thenReturn(emptyList())
    whenever(mockApi.fail(any(), any(), any())).thenAnswer {}

    val record = LocalSyncRecord(
        jobId = "job-confirm-stale",
        mediaId = "media-confirm-stale",
        fileName = "stale-confirm.jpg",
        mimeType = "image/jpeg",
        sizeBytes = 100L,
        sha256 = null,
        status = LocalSyncStatus.ConfirmPending,
        localUri = "content://media/external/images/media/confirm-stale",
        lastAttemptAt = 0L,
        lastError = "Confirm timeout",
        isLocalDeleted = false,
        statusEnteredAt = 0L,
        retryCount = 4
    )
    whenever(mockLedger.listByStatuses(LocalSyncStatus.ConfirmPending, LocalSyncStatus.Imported)).thenReturn(listOf(record))
    whenever(mockApi.confirm(eq("token-123"), eq("job-confirm-stale"), any())).thenAnswer { throw IOException("Confirm timeout") }

    val repository = createRepository()
    val result = repository.syncPendingJobs()

    assertFalse(result)
    verify(mockLedger).markFailed(eq("job-confirm-stale"), eq("Sync confirmation timed out after 1 hour"))
    verify(mockApi).fail(eq("token-123"), eq("job-confirm-stale"), eq(FailDeviceSyncJobRequest("Sync confirmation timed out after 1 hour")))
}
```

- [ ] **Step 2: Run the repository tests to confirm they fail**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/android/pixel
./gradlew.bat testDebugUnitTest --tests "com.nexusrelay.pixel.sync.DeviceSyncRepositoryTest"
```

Expected: FAIL because `Queued` is not inspected, retriable confirm failures do not increment retry state, and timed-out confirmation still never flips to `Failed`.

- [ ] **Step 3: Commit the failing stale-policy tests**

```bash
git add android/pixel/app/src/test/java/com/nexusrelay/pixel/sync/DeviceSyncRepositoryTest.kt
git commit -m "test: define pixel stale sync recovery policy"
```

---

## Task 4: Repository Timeout And Retry Policy

**Files:**
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/main/java/com/nexusrelay/pixel/sync/DeviceSyncRepository.kt`
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/test/java/com/nexusrelay/pixel/sync/DeviceSyncRepositoryTest.kt`

- [ ] **Step 1: Add explicit timeout constants and stale helpers**

At the top of `DeviceSyncRepository.kt`, add:

```kotlin
    companion object {
        private const val STALE_STATUS_TIMEOUT_MS = 60L * 60L * 1000L
        private const val MAX_CONFIRMATION_RETRIES = 4
        private const val DOWNLOADING_TIMEOUT_MESSAGE = "Sync interrupted before import completed"
        private const val QUEUED_TIMEOUT_MESSAGE = "Sync timed out before download started"
        private const val CONFIRMATION_TIMEOUT_MESSAGE = "Sync confirmation timed out after 1 hour"
    }

    private fun hasTimedOut(record: LocalSyncRecord, now: Long): Boolean {
        return now - record.statusEnteredAt >= STALE_STATUS_TIMEOUT_MS
    }

    private fun hasConfirmationBudget(record: LocalSyncRecord, now: Long): Boolean {
        return !hasTimedOut(record, now) && record.retryCount < MAX_CONFIRMATION_RETRIES
    }
```

- [ ] **Step 2: Replace `recoverInterruptedDownloads()` with state-aware recovery**

Add these methods:

```kotlin
    private suspend fun recoverInterruptedDownloads(now: Long) {
        val interruptedRecords = ledger.listByStatuses(LocalSyncStatus.Downloading)
        for (record in interruptedRecords) {
            if (hasTimedOut(record, now)) {
                ledger.markFailed(record.jobId, DOWNLOADING_TIMEOUT_MESSAGE)
            }
        }
    }

    private suspend fun failOrphanedQueuedRecords(pendingJobIds: Set<String>, now: Long) {
        val queuedRecords = ledger.listByStatuses(LocalSyncStatus.Queued)
        for (record in queuedRecords) {
            if (record.jobId !in pendingJobIds && hasTimedOut(record, now)) {
                ledger.markFailed(record.jobId, QUEUED_TIMEOUT_MESSAGE)
            }
        }
    }
```

Use them in `syncPendingJobs()`:

```kotlin
        val now = System.currentTimeMillis()
        recoverInterruptedDownloads(now)
        val pendingJobs = try {
            api.pendingJobs(deviceToken)
        } catch (e: Exception) {
            Log.e(tag, "Failed to fetch pending jobs", e)
            throwOrPropagateIfRetriable(e)
            throw e
        }
        failOrphanedQueuedRecords(pendingJobs.map { it.jobId }.toSet(), now)
```

This is the key guardrail for existing logic:
- `Queued` is only failed if it is both old and no longer present on the backend.
- A job that is still pending server-side is left alone and will continue through the current download/import path.

- [ ] **Step 3: Bound confirmation retries without breaking duplicate-avoidance**

Update `retryLocalConfirmation(...)` to keep the current "do not re-download when local URI exists" behavior, but stop endless retries:

```kotlin
    private suspend fun retryLocalConfirmation(
        api: NexusRelayApi,
        deviceToken: String,
        record: LocalSyncRecord
    ): Boolean? {
        val localUri = record.localUri ?: return null
        val now = System.currentTimeMillis()

        return try {
            api.confirm(deviceToken, record.jobId, ConfirmDeviceSyncJobRequest(localUri, record.sizeBytes))
            ledger.markConfirmed(record.jobId)
            true
        } catch (e: Exception) {
            Log.e(tag, "Re-confirming job ${record.jobId} failed, will retry later", e)
            val errorMsg = e.localizedMessage ?: "Terminal confirmation error"

            if (isNetworkOrBackendFailure(e) && hasConfirmationBudget(record, now)) {
                ledger.recordRetriableFailure(record.jobId, errorMsg, now)
                throwOrPropagateIfRetriable(e)
            }

            val finalMessage = if (isNetworkOrBackendFailure(e) && hasTimedOut(record, now)) {
                CONFIRMATION_TIMEOUT_MESSAGE
            } else {
                errorMsg
            }
            ledger.markFailed(record.jobId, finalMessage)
            try {
                api.fail(deviceToken, record.jobId, FailDeviceSyncJobRequest(finalMessage))
            } catch (failEx: Exception) {
                Log.e(tag, "Failed to report job failure to backend for job ${record.jobId}", failEx)
            }
            false
        }
    }
```

Then update the main `syncPendingJobs()` catch so new jobs that fail after `markConfirmPending(...)` also record bounded retriable state instead of silently living forever, while keeping the current non-confirmation retry behavior:

```kotlin
                val now = System.currentTimeMillis()
                val currentRecord = ledger.get(job.jobId)
                val currentStatus = currentRecord?.status
                val inConfirmationRecovery = confirmationPending || shouldPreserveConfirmationState(currentStatus)

                if (!inConfirmationRecovery) {
                    ledger.markFailed(job.jobId, errorMsg)
                    throwOrPropagateIfRetriable(e)
                    try {
                        api.fail(deviceToken, job.jobId, FailDeviceSyncJobRequest(errorMsg))
                    } catch (failEx: Exception) {
                        Log.e(tag, "Failed to report job failure to backend for job ${job.jobId}", failEx)
                    }
                    allSucceeded = false
                    continue
                }

                if (isNetworkOrBackendFailure(e) && currentRecord != null && hasConfirmationBudget(currentRecord, now)) {
                    ledger.recordRetriableFailure(job.jobId, errorMsg, now)
                    throwOrPropagateIfRetriable(e)
                }

                val finalMessage = if (currentRecord != null && hasTimedOut(currentRecord, now)) {
                    CONFIRMATION_TIMEOUT_MESSAGE
                } else {
                    errorMsg
                }
                ledger.markFailed(job.jobId, finalMessage)
                try {
                    api.fail(deviceToken, job.jobId, FailDeviceSyncJobRequest(finalMessage))
                } catch (failEx: Exception) {
                    Log.e(tag, "Failed to report job failure to backend for job ${job.jobId}", failEx)
                }
                allSucceeded = false
                continue
```

The important invariant is unchanged:
- `ConfirmPending` / `Imported` still retry confirmation first and do not re-import.
- They now age out cleanly instead of sitting in `Syncing` forever.

- [ ] **Step 4: Add repository methods for Settings maintenance**

Add these methods near the bottom of `DeviceSyncRepository.kt`:

```kotlin
    suspend fun clearHistory() {
        ledger.clearHistory()
    }

    suspend fun resetLedgerIfSafe(): Boolean {
        if (ledger.hasActiveRecords()) {
            return false
        }
        ledger.clear()
        return true
    }
```

- [ ] **Step 5: Re-run the repository tests**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/android/pixel
./gradlew.bat testDebugUnitTest --tests "com.nexusrelay.pixel.sync.DeviceSyncRepositoryTest"
```

Expected: PASS.

- [ ] **Step 6: Commit the repository policy**

```bash
git add android/pixel/app/src/main/java/com/nexusrelay/pixel/sync/DeviceSyncRepository.kt android/pixel/app/src/test/java/com/nexusrelay/pixel/sync/DeviceSyncRepositoryTest.kt
git commit -m "feat: bound pixel stale sync recovery"
```

---

## Task 5: Settings Maintenance UI

**Files:**
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/PixelUiModels.kt`
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/PixelUiComponents.kt`
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/StatusScreen.kt`
- Create: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/test/java/com/nexusrelay/pixel/ui/PixelUiModelsTest.kt`

- [ ] **Step 1: Add a preview model and unit tests**

Create `PixelUiModelsTest.kt` with:

```kotlin
package com.nexusrelay.pixel.ui

import com.nexusrelay.pixel.storage.LocalSyncRecord
import com.nexusrelay.pixel.storage.LocalSyncStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PixelUiModelsTest {

    @Test
    fun buildLedgerMaintenancePreviewCountsHistoryAndActiveRecords() {
        val records = listOf(
            sampleRecord("confirmed", LocalSyncStatus.Confirmed),
            sampleRecord("failed", LocalSyncStatus.Failed),
            sampleRecord("queued", LocalSyncStatus.Queued),
            sampleRecord("confirm", LocalSyncStatus.ConfirmPending)
        )

        val preview = buildLedgerMaintenancePreview(records)

        assertEquals(2, preview.historyCount)
        assertEquals(2, preview.activeCount)
        assertTrue(preview.canClearHistory)
        assertFalse(preview.canResetLedger)
    }

    private fun sampleRecord(jobId: String, status: LocalSyncStatus): LocalSyncRecord =
        LocalSyncRecord(
            jobId = jobId,
            mediaId = "media-$jobId",
            fileName = "$jobId.jpg",
            mimeType = "image/jpeg",
            sizeBytes = 1L,
            sha256 = null,
            status = status,
            localUri = null,
            lastAttemptAt = 1L,
            lastError = null,
            isLocalDeleted = false,
            statusEnteredAt = 1L,
            retryCount = 0
        )
}
```

Add the model to `PixelUiModels.kt`:

```kotlin
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
```

- [ ] **Step 2: Run the new UI-model test and confirm it fails before implementation**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/android/pixel
./gradlew.bat testDebugUnitTest --tests "com.nexusrelay.pixel.ui.PixelUiModelsTest"
```

Expected: FAIL until `LedgerMaintenancePreview` and `buildLedgerMaintenancePreview(...)` are added.

- [ ] **Step 3: Add the dialogs and Settings wiring**

In `PixelUiComponents.kt`, add two dialogs:

```kotlin
@Composable
fun ClearLedgerHistoryDialog(
    historyCount: Int,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = { Icon(Icons.Outlined.DeleteSweep, contentDescription = null) },
        title = { Text("Clear sync history?") },
        text = { Text("This removes $historyCount completed and failed sync records from this Pixel. Imported media files stay on the device.") },
        confirmButton = { Button(onClick = onConfirm) { Text("Clear history") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } }
    )
}

@Composable
fun ResetLedgerDialog(
    activeCount: Int,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = { Icon(Icons.Outlined.DeleteSweep, contentDescription = null) },
        title = { Text("Reset local ledger?") },
        text = { Text("This removes all local sync status from this Pixel. It does not delete imported media files, but it is only safe when no jobs are still active. Active jobs: $activeCount.") },
        confirmButton = { Button(onClick = onConfirm) { Text("Reset ledger") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } }
    )
}
```

In `StatusScreen.kt`, add state and wire the repository methods:

```kotlin
    var showClearHistoryDialog by remember { mutableStateOf(false) }
    var showResetLedgerDialog by remember { mutableStateOf(false) }
    val maintenancePreview = remember(allJobs) { buildLedgerMaintenancePreview(allJobs) }

    if (showClearHistoryDialog) {
        ClearLedgerHistoryDialog(
            historyCount = maintenancePreview.historyCount,
            onConfirm = {
                showClearHistoryDialog = false
                coroutineScope.launch {
                    repository.clearHistory()
                    snackbarHostState.showSnackbar("Sync history cleared")
                }
            },
            onDismiss = { showClearHistoryDialog = false }
        )
    }

    if (showResetLedgerDialog) {
        ResetLedgerDialog(
            activeCount = maintenancePreview.activeCount,
            onConfirm = {
                showResetLedgerDialog = false
                coroutineScope.launch {
                    val reset = repository.resetLedgerIfSafe()
                    snackbarHostState.showSnackbar(
                        if (reset) "Local sync ledger reset" else "Finish or fail active sync jobs before resetting the ledger"
                    )
                }
            },
            onDismiss = { showResetLedgerDialog = false }
        )
    }
```

Then add a new Settings card:

```kotlin
        item {
            Card(
                shape = RoundedCornerShape(8.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
            ) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Sync ledger maintenance", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Text(
                        "Completed or failed history can be cleared anytime. Full ledger reset stays locked while ${maintenancePreview.activeCount} sync jobs are still active.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodySmall
                    )
                    OutlinedButton(
                        onClick = onClearHistory,
                        enabled = maintenancePreview.canClearHistory,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text("Clear sync history (${maintenancePreview.historyCount})")
                    }
                    OutlinedButton(
                        onClick = onResetLedger,
                        enabled = maintenancePreview.canResetLedger,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text("Reset local ledger")
                    }
                }
            }
        }
```

Pass `maintenancePreview`, `onClearHistory`, and `onResetLedger` through `SettingsTab(...)`.

- [ ] **Step 4: Re-run the UI-model test and the full Pixel unit suite**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/android/pixel
./gradlew.bat testDebugUnitTest --tests "com.nexusrelay.pixel.ui.PixelUiModelsTest"
./gradlew.bat testDebugUnitTest
```

Expected: PASS.

- [ ] **Step 5: Manual smoke-check**

Verify in the running Pixel app:

1. A device with only `Confirmed` / `Failed` history can clear history and then reset the ledger.
2. A device with any `Queued`, `Downloading`, `Imported`, or `ConfirmPending` record sees Reset disabled.
3. A stale `ConfirmPending` record eventually surfaces as `Failed` once timeout or retry budget is exhausted.

- [ ] **Step 6: Commit the Settings UI**

```bash
git add android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/PixelUiModels.kt android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/PixelUiComponents.kt android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/StatusScreen.kt android/pixel/app/src/test/java/com/nexusrelay/pixel/ui/PixelUiModelsTest.kt
git commit -m "feat: add pixel ledger maintenance controls"
```

---

## Final Verification

- [ ] **Step 1: Run the targeted Pixel suite**

```powershell
Set-Location G:/workspace/nexus-relay-mobile/android/pixel
./gradlew.bat testDebugUnitTest --tests "com.nexusrelay.pixel.storage.LocalSyncLedgerTest"
./gradlew.bat testDebugUnitTest --tests "com.nexusrelay.pixel.sync.DeviceSyncRepositoryTest"
./gradlew.bat testDebugUnitTest --tests "com.nexusrelay.pixel.ui.PixelUiModelsTest"
```

Expected: PASS.

- [ ] **Step 2: Run the full Pixel unit suite**

```powershell
Set-Location G:/workspace/nexus-relay-mobile/android/pixel
./gradlew.bat testDebugUnitTest
```

Expected: PASS.

- [ ] **Step 3: Review user-visible behavior**

Check these outcomes before closing the work:

1. `Downloading` no longer sits forever and now fails once it stays stale past the timeout window.
2. `Queued` only fails when it is stale and absent from the backend pending list.
3. `Imported` and `ConfirmPending` still retry confirm first, but age out to `Failed` after the bounded retry window.
4. Clearing history never touches active jobs or imported local files.
5. Resetting the ledger is blocked while active jobs remain.
