# Pixel Modern UI and Cleanup Space Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the Android Pixel companion app into the approved modern mockup flow and add an on-demand "Clean up space" action for Android 10 Pixel devices.

**Architecture:** Keep the existing single-activity Jetpack Compose app and avoid a large navigation rewrite. Split reusable UI into small Compose components, keep screen state derived from `AppSettingsStore` and `LocalSyncLedger`, and add cleanup behavior inside `DeviceSyncRepository` so auto-delete and manual cleanup share one deletion path. Android 10 support means using MediaStore URIs already inserted by this app, with no broad storage-management permission.

**Tech Stack:** Kotlin, Jetpack Compose Material 3, WorkManager, DataStore, Android MediaStore on API 29+, Retrofit/Moshi, JUnit, Mockito Kotlin, Android Gradle Plugin.

---

## Scope Decisions

- The Sync tab will not contain a separate "Sync health" section. It will show the top status panel, metrics, Sync Now action, and recent ledger only.
- Background sync health belongs in Settings only: push wake-up, FCM token state if locally known, and fallback polling copy.
- The UI copy will be English for this pass to remove the current mojibake text in `StatusScreen.kt`.
- Android 10 is the target physical device, so do not request `MANAGE_EXTERNAL_STORAGE`, `READ_MEDIA_*`, or Android 11+ storage APIs.
- "Clean up space" means manually deleting locally imported media rows that are already `Confirmed` and not yet marked `isLocalDeleted`. It ignores the auto-delete delay because the user explicitly requested cleanup now.
- Manual cleanup must be guarded by a confirmation dialog because it deletes local copies from the device.

## Mockup Reference

- Updated mockup: `docs/implementation/pixel-modern-ui-mockup.html`
- Important reference screens:
  - First-run setup: compact pair/register form.
  - Sync home: status, metrics, Sync Now, recent ledger.
  - Settings: device target, Wi-Fi, auto-delete, cleanup, background sync health, unregister.

## File Structure

- Modify: `android/pixel/gradle/libs.versions.toml`
  - Add Compose Material Icons Extended dependency alias.
- Modify: `android/pixel/app/build.gradle.kts`
  - Add icons dependency for standard Material symbols.
- Create: `android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/PixelUiModels.kt`
  - UI-only state models and formatting helpers for status, ledger, cleanup, and settings.
- Create: `android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/PixelUiComponents.kt`
  - Reusable Material 3 components: app header, status panel, metric card, ledger row, settings row, cleanup dialog.
- Modify: `android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/SetupScreen.kt`
  - Replace current dark card layout with the modern Pair your Pixel layout.
- Modify: `android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/StatusScreen.kt`
  - Replace current dense screen with internal tabs: Sync, Ledger, Settings.
  - Remove Sync health from Sync tab.
  - Add Clean up space UI in Settings.
- Modify: `android/pixel/app/src/main/java/com/nexusrelay/pixel/sync/DeviceSyncRepository.kt`
  - Add manual cleanup APIs and extract shared deletion logic.
- Create: `android/pixel/app/src/main/java/com/nexusrelay/pixel/sync/CleanupSpaceResult.kt`
  - Result data class for manual cleanup counts and estimated freed bytes.
- Modify: `android/pixel/app/src/test/java/com/nexusrelay/pixel/sync/DeviceSyncRepositoryTest.kt`
  - Add cleanup-now tests.
- Create: `android/pixel/app/src/test/java/com/nexusrelay/pixel/ui/PixelUiModelsTest.kt`
  - Add formatting/model tests.
- Optional after core pass: `android/pixel/app/src/androidTest/java/com/nexusrelay/pixel/ui/StatusScreenTest.kt`
  - Compose smoke test if emulator/device time allows.

---

### Task 1: Add UI Model Helpers and Icon Dependency

**Files:**
- Modify: `android/pixel/gradle/libs.versions.toml`
- Modify: `android/pixel/app/build.gradle.kts`
- Create: `android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/PixelUiModels.kt`
- Create: `android/pixel/app/src/test/java/com/nexusrelay/pixel/ui/PixelUiModelsTest.kt`

- [ ] **Step 1: Add failing UI model tests**

Create `android/pixel/app/src/test/java/com/nexusrelay/pixel/ui/PixelUiModelsTest.kt`:

```kotlin
package com.nexusrelay.pixel.ui

import com.nexusrelay.pixel.storage.LocalSyncRecord
import com.nexusrelay.pixel.storage.LocalSyncStatus
import org.junit.Assert.assertEquals
import org.junit.Test

class PixelUiModelsTest {
    @Test
    fun formatBytesUsesMbForLargeFiles() {
        assertEquals("4.80 MB", formatBytes(5_033_165L))
    }

    @Test
    fun formatLastSyncShowsNeverForZero() {
        assertEquals("Never", formatLastSyncTime(0L))
    }

    @Test
    fun buildSyncMetricsCountsConfirmedPendingAndFailed() {
        val records = listOf(
            record("confirmed", LocalSyncStatus.Confirmed),
            record("cleaned", LocalSyncStatus.Confirmed, isLocalDeleted = true),
            record("downloading", LocalSyncStatus.Downloading),
            record("queued", LocalSyncStatus.Queued),
            record("failed", LocalSyncStatus.Failed)
        )

        val metrics = buildSyncMetrics(records)

        assertEquals(2, metrics.confirmed)
        assertEquals(2, metrics.pending)
        assertEquals(1, metrics.failed)
        assertEquals(1, metrics.cleaned)
    }

    @Test
    fun buildCleanupPreviewIncludesOnlyConfirmedNotDeletedLocalFiles() {
        val records = listOf(
            record("ready", LocalSyncStatus.Confirmed, localUri = "content://ready", sizeBytes = 100L),
            record("deleted", LocalSyncStatus.Confirmed, localUri = "content://deleted", sizeBytes = 200L, isLocalDeleted = true),
            record("failed", LocalSyncStatus.Failed, localUri = "content://failed", sizeBytes = 300L),
            record("missing-uri", LocalSyncStatus.Confirmed, localUri = null, sizeBytes = 400L)
        )

        val preview = buildCleanupPreview(records)

        assertEquals(1, preview.cleanableCount)
        assertEquals(100L, preview.cleanableBytes)
        assertEquals("100 B", preview.cleanableBytesLabel)
    }

    private fun record(
        id: String,
        status: LocalSyncStatus,
        localUri: String? = "content://$id",
        sizeBytes: Long = 1024L,
        isLocalDeleted: Boolean = false
    ): LocalSyncRecord {
        return LocalSyncRecord(
            jobId = id,
            mediaId = "media-$id",
            fileName = "$id.jpg",
            mimeType = "image/jpeg",
            sizeBytes = sizeBytes,
            sha256 = null,
            status = status,
            localUri = localUri,
            lastAttemptAt = 0L,
            lastError = null,
            isLocalDeleted = isLocalDeleted
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
cd G:\workspace\nexus-relay-mobile\android\pixel
.\gradlew.bat :app:testDebugUnitTest --tests "com.nexusrelay.pixel.ui.PixelUiModelsTest"
```

Expected: fails because `PixelUiModels.kt`, `formatBytes`, `formatLastSyncTime`, `buildSyncMetrics`, and `buildCleanupPreview` do not exist.

- [ ] **Step 3: Add UI model implementation**

Create `android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/PixelUiModels.kt`:

```kotlin
package com.nexusrelay.pixel.ui

import com.nexusrelay.pixel.storage.LocalSyncRecord
import com.nexusrelay.pixel.storage.LocalSyncStatus
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

enum class PixelTab {
    Sync,
    Ledger,
    Settings
}

data class SyncMetrics(
    val confirmed: Int,
    val pending: Int,
    val failed: Int,
    val cleaned: Int
)

data class CleanupPreview(
    val cleanableCount: Int,
    val cleanableBytes: Long,
    val cleanableBytesLabel: String
)

fun buildSyncMetrics(records: List<LocalSyncRecord>): SyncMetrics {
    val confirmed = records.count { it.status == LocalSyncStatus.Confirmed }
    val pending = records.count {
        it.status == LocalSyncStatus.Queued ||
            it.status == LocalSyncStatus.Downloading ||
            it.status == LocalSyncStatus.Imported ||
            it.status == LocalSyncStatus.ConfirmPending
    }
    val failed = records.count { it.status == LocalSyncStatus.Failed }
    val cleaned = records.count { it.status == LocalSyncStatus.Confirmed && it.isLocalDeleted }
    return SyncMetrics(
        confirmed = confirmed,
        pending = pending,
        failed = failed,
        cleaned = cleaned
    )
}

fun buildCleanupPreview(records: List<LocalSyncRecord>): CleanupPreview {
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

fun ledgerStatusLabel(record: LocalSyncRecord): String {
    if (record.status == LocalSyncStatus.Confirmed && record.isLocalDeleted) {
        return "Cleaned"
    }
    return when (record.status) {
        LocalSyncStatus.Queued -> "Queued"
        LocalSyncStatus.Downloading -> "Downloading"
        LocalSyncStatus.Imported -> "Imported"
        LocalSyncStatus.ConfirmPending -> "Confirming"
        LocalSyncStatus.Confirmed -> "Confirmed"
        LocalSyncStatus.Failed -> "Failed"
    }
}
```

- [ ] **Step 4: Add icon dependency**

Modify `android/pixel/gradle/libs.versions.toml` in `[libraries]`:

```toml
androidx-compose-material-icons-extended = { group = "androidx.compose.material", name = "material-icons-extended" }
```

Modify `android/pixel/app/build.gradle.kts` under Compose dependencies:

```kotlin
implementation(libs.androidx.compose.material.icons.extended)
```

- [ ] **Step 5: Run tests**

Run:

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests "com.nexusrelay.pixel.ui.PixelUiModelsTest"
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 6: Commit**

```powershell
git add android/pixel/gradle/libs.versions.toml android/pixel/app/build.gradle.kts android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/PixelUiModels.kt android/pixel/app/src/test/java/com/nexusrelay/pixel/ui/PixelUiModelsTest.kt
git commit -m "feat: add pixel ui model helpers"
```

---

### Task 2: Add Manual Cleanup Space Behavior

**Files:**
- Create: `android/pixel/app/src/main/java/com/nexusrelay/pixel/sync/CleanupSpaceResult.kt`
- Modify: `android/pixel/app/src/main/java/com/nexusrelay/pixel/sync/DeviceSyncRepository.kt`
- Modify: `android/pixel/app/src/test/java/com/nexusrelay/pixel/sync/DeviceSyncRepositoryTest.kt`

- [ ] **Step 1: Add failing cleanup-now tests**

Append to `DeviceSyncRepositoryTest.kt`:

```kotlin
@Test
fun testCleanUpSpaceNow_DeletesConfirmedLocalFilesEvenWhenAutoDeleteDisabled() = runTest {
    whenever(mockSettingsStore.autoDeleteEnabledFlow).thenReturn(flowOf(false))
    val record = LocalSyncRecord(
        jobId = "job-clean-now",
        mediaId = "media-clean-now",
        fileName = "clean-now.jpg",
        mimeType = "image/jpeg",
        sizeBytes = 4096L,
        sha256 = null,
        status = LocalSyncStatus.Confirmed,
        localUri = "content://media/external/images/media/clean-now",
        lastAttemptAt = System.currentTimeMillis(),
        lastError = null,
        isLocalDeleted = false
    )
    whenever(mockLedger.listByStatuses(LocalSyncStatus.Confirmed)).thenReturn(listOf(record))
    val mockContentResolver = mock(android.content.ContentResolver::class.java)
    whenever(mockContext.contentResolver).thenReturn(mockContentResolver)
    whenever(mockContentResolver.delete(any(), any(), any())).thenReturn(1)

    val repository = createRepository()
    val result = repository.cleanUpSpaceNow()

    assertTrue(result.deletedCount == 1)
    assertTrue(result.freedBytes == 4096L)
    verify(mockLedger).markLocalDeleted("job-clean-now")
}

@Test
fun testCleanUpSpaceNow_SkipsAlreadyDeletedAndMissingUri() = runTest {
    val deleted = LocalSyncRecord(
        jobId = "job-deleted",
        mediaId = "media-deleted",
        fileName = "deleted.jpg",
        mimeType = "image/jpeg",
        sizeBytes = 100L,
        sha256 = null,
        status = LocalSyncStatus.Confirmed,
        localUri = "content://media/external/images/media/deleted",
        lastAttemptAt = 0L,
        lastError = null,
        isLocalDeleted = true
    )
    val missingUri = deleted.copy(
        jobId = "job-missing-uri",
        mediaId = "media-missing-uri",
        fileName = "missing-uri.jpg",
        localUri = null,
        isLocalDeleted = false
    )
    whenever(mockLedger.listByStatuses(LocalSyncStatus.Confirmed)).thenReturn(listOf(deleted, missingUri))

    val repository = createRepository()
    val result = repository.cleanUpSpaceNow()

    assertTrue(result.scannedCount == 2)
    assertTrue(result.deletedCount == 0)
    assertTrue(result.skippedCount == 2)
    verify(mockLedger, never()).markLocalDeleted(any())
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests "com.nexusrelay.pixel.sync.DeviceSyncRepositoryTest.testCleanUpSpaceNow_*"
```

Expected: fails because `cleanUpSpaceNow` and `CleanupSpaceResult` do not exist.

- [ ] **Step 3: Add cleanup result type**

Create `android/pixel/app/src/main/java/com/nexusrelay/pixel/sync/CleanupSpaceResult.kt`:

```kotlin
package com.nexusrelay.pixel.sync

data class CleanupSpaceResult(
    val scannedCount: Int,
    val deletedCount: Int,
    val skippedCount: Int,
    val failedCount: Int,
    val freedBytes: Long
)
```

- [ ] **Step 4: Extract shared cleanup logic**

Modify `DeviceSyncRepository.kt`.

Replace the body of `cleanUpLocalFiles()` with:

```kotlin
suspend fun cleanUpLocalFiles() {
    val autoDeleteEnabled = appSettingsStore.autoDeleteEnabledFlow.first()
    if (!autoDeleteEnabled) {
        return
    }

    val delayMinutes = appSettingsStore.autoDeleteDelayMinutesFlow.first()
    val delayMillis = delayMinutes * 60L * 1000L
    val thresholdTime = System.currentTimeMillis() - delayMillis

    val confirmedRecords = ledger.listByStatuses(LocalSyncStatus.Confirmed)
        .filter { it.lastAttemptAt <= thresholdTime }

    deleteLocalFiles(confirmedRecords)
}
```

Add below it:

```kotlin
suspend fun cleanUpSpaceNow(): CleanupSpaceResult {
    val confirmedRecords = ledger.listByStatuses(LocalSyncStatus.Confirmed)
    return deleteLocalFiles(confirmedRecords)
}

private suspend fun deleteLocalFiles(records: List<LocalSyncRecord>): CleanupSpaceResult {
    val resolver = context.contentResolver
    var deletedCount = 0
    var skippedCount = 0
    var failedCount = 0
    var freedBytes = 0L

    for (record in records) {
        if (record.isLocalDeleted || record.localUri.isNullOrBlank()) {
            skippedCount++
            continue
        }

        try {
            val uri = Uri.parse(record.localUri)
            Log.d(tag, "Deleting local file: ${record.fileName} (URI: ${record.localUri})")
            val deletedRows = resolver.delete(uri, null, null)
            if (deletedRows > 0) {
                deletedCount++
                freedBytes += record.sizeBytes
                ledger.markLocalDeleted(record.jobId)
            } else {
                skippedCount++
                Log.w(tag, "Local file not deleted or already missing: ${record.fileName}")
            }
        } catch (e: SecurityException) {
            failedCount++
            Log.e(tag, "SecurityException deleting local file ${record.fileName}: ${e.message}", e)
        } catch (e: Exception) {
            if (e.message?.contains("does not exist") == true || e is java.io.FileNotFoundException) {
                skippedCount++
                ledger.markLocalDeleted(record.jobId)
            } else {
                failedCount++
                Log.e(tag, "Error deleting local file ${record.fileName}: ${e.message}", e)
            }
        }
    }

    return CleanupSpaceResult(
        scannedCount = records.size,
        deletedCount = deletedCount,
        skippedCount = skippedCount,
        failedCount = failedCount,
        freedBytes = freedBytes
    )
}
```

- [ ] **Step 5: Run cleanup tests**

Run:

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests "com.nexusrelay.pixel.sync.DeviceSyncRepositoryTest"
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 6: Commit**

```powershell
git add android/pixel/app/src/main/java/com/nexusrelay/pixel/sync/CleanupSpaceResult.kt android/pixel/app/src/main/java/com/nexusrelay/pixel/sync/DeviceSyncRepository.kt android/pixel/app/src/test/java/com/nexusrelay/pixel/sync/DeviceSyncRepositoryTest.kt
git commit -m "feat: add manual pixel storage cleanup"
```

---

### Task 3: Build Reusable Modern Compose Components

**Files:**
- Create: `android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/PixelUiComponents.kt`

- [ ] **Step 1: Create shared components**

Create `PixelUiComponents.kt`:

```kotlin
package com.nexusrelay.pixel.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.DeleteSweep
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material.icons.outlined.Wifi
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.nexusrelay.pixel.storage.LocalSyncRecord
import com.nexusrelay.pixel.storage.LocalSyncStatus

private val PanelShape = RoundedCornerShape(8.dp)

@Composable
fun PixelScreenHeader(
    title: String,
    subtitle: String,
    trailing: @Composable (() -> Unit)? = null
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (trailing != null) {
            trailing()
        }
    }
}

@Composable
fun ReadyStatusPanel(lastSyncLabel: String, scopeLabel: String) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = PanelShape,
        colors = CardDefaults.cardColors(containerColor = Color(0xFFE9F8F1))
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Icon(Icons.Outlined.CheckCircle, contentDescription = null, tint = Color(0xFF16856A))
                Column {
                    Text("Ready to receive", fontWeight = FontWeight.Bold, color = Color(0xFF24313F))
                    Text("Push wake-up is active. Polling checks every 15 minutes.", color = Color(0xFF627083), style = MaterialTheme.typography.bodySmall)
                }
            }
            Text("Scope: $scopeLabel", style = MaterialTheme.typography.bodySmall, color = Color(0xFF627083))
            Text("Last sync: $lastSyncLabel", style = MaterialTheme.typography.bodySmall, color = Color(0xFF627083))
        }
    }
}

@Composable
fun MetricCard(label: String, value: String, icon: ImageVector, tint: Color, modifier: Modifier = Modifier) {
    Card(modifier = modifier, shape = PanelShape, colors = CardDefaults.cardColors(containerColor = Color.White)) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(20.dp))
            Text(value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
fun LedgerRecordRow(record: LocalSyncRecord) {
    val statusLabel = ledgerStatusLabel(record)
    val color = when {
        record.status == LocalSyncStatus.Confirmed && record.isLocalDeleted -> Color(0xFF16856A)
        record.status == LocalSyncStatus.Confirmed -> Color(0xFF276EF1)
        record.status == LocalSyncStatus.Failed -> Color(0xFFBA2F45)
        record.status == LocalSyncStatus.Downloading || record.status == LocalSyncStatus.ConfirmPending -> Color(0xFFA76613)
        else -> Color(0xFF627083)
    }

    Surface(modifier = Modifier.fillMaxWidth(), shape = PanelShape, color = Color(0xFFF1F5F8)) {
        Row(
            modifier = Modifier.padding(12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(record.fileName, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text("${record.mimeType} · ${formatBytes(record.sizeBytes)}", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
                if (record.status == LocalSyncStatus.Failed && !record.lastError.isNullOrBlank()) {
                    Text(record.lastError, color = Color(0xFFBA2F45), style = MaterialTheme.typography.bodySmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }
            StatusChip(statusLabel, color)
        }
    }
}

@Composable
fun StatusChip(text: String, color: Color) {
    Surface(shape = RoundedCornerShape(999.dp), color = color.copy(alpha = 0.12f)) {
        Text(
            text = text,
            color = color,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
        )
    }
}

@Composable
fun SettingsRow(title: String, subtitle: String, icon: ImageVector, trailing: @Composable () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        Column(modifier = Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.SemiBold)
            Text(subtitle, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
        }
        trailing()
    }
}

@Composable
fun CleanupConfirmDialog(
    preview: CleanupPreview,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = { Icon(Icons.Outlined.DeleteSweep, contentDescription = null) },
        title = { Text("Clean up space?") },
        text = { Text("This will remove ${preview.cleanableCount} local files from this Pixel and free about ${preview.cleanableBytesLabel}. Files already confirmed by NexusRelay stay in the backend.") },
        confirmButton = { Button(onClick = onConfirm) { Text("Clean up") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } }
    )
}
```

- [ ] **Step 2: Compile components**

Run:

```powershell
.\gradlew.bat :app:compileDebugKotlin
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 3: Commit**

```powershell
git add android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/PixelUiComponents.kt
git commit -m "feat: add pixel ui components"
```

---

### Task 4: Redesign Setup Screen

**Files:**
- Modify: `android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/SetupScreen.kt`

- [ ] **Step 1: Preserve behavior checklist before editing**

Confirm `SetupScreen.kt` still performs these behaviors after redesign:

- Uses `BuildConfig.DEFAULT_BACKEND_BASE_URL`.
- Shows backend URL field only when `BuildConfig.SHOW_BACKEND_URL_FIELD` is true.
- Requires backend URL, username, password, and device name.
- Requires folder ID when `DeviceSyncScope.Folder` is selected.
- Logs in through `api.login(LoginRequest(...))`.
- Resolves current FCM token through `resolveFcmTokenForRegistration`.
- Calls `api.registerDevice(...)` with scope, folder, Wi-Fi, and FCM token.
- Saves backend URL, device name, Wi-Fi only, target ID, scope, folder ID, and device token.
- Schedules `PollWorker` and enqueues `SyncWorker`.

- [ ] **Step 2: Replace visual layout only**

Modify `SetupScreen.kt` so the visual structure matches the mockup:

```kotlin
Box(
    modifier = Modifier
        .fillMaxSize()
        .background(MaterialTheme.colorScheme.background)
        .systemBarsPadding()
        .padding(20.dp)
) {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        PixelScreenHeader(
            title = "NexusRelay Pixel",
            subtitle = "Connect this device"
        )

        ReadyStatusPanel(
            lastSyncLabel = "Not registered",
            scopeLabel = "Choose during setup"
        )

        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(8.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text("Pair your Pixel", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Text("Use your NexusRelay account once. This app stores a device token for future sync.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                // Move existing fields here without changing registration logic.
            }
        }
    }
}
```

Use Material 3 defaults for `OutlinedTextField`, `SingleChoiceSegmentedButtonRow`, `Switch`, and `Button`. Do not use the old dark gradient/card colors.

- [ ] **Step 3: Fix copy**

Use these labels:

- Title: `Pair your Pixel`
- Subtitle: `Use your NexusRelay account once. This app stores a device token for future sync.`
- Fields: `Server`, `Username`, `Password`, `Device name`, `Folder ID`
- Switch: `Wi-Fi only`
- Button: `Register Pixel`
- Error required fields: `Server, account, and device name are required`
- Error folder: `Folder ID is required for folder sync`
- Success: `Pixel registered`

- [ ] **Step 4: Compile**

Run:

```powershell
.\gradlew.bat :app:compileDebugKotlin
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: Commit**

```powershell
git add android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/SetupScreen.kt
git commit -m "feat: redesign pixel registration"
```

---

### Task 5: Redesign Status Screen With Sync, Ledger, Settings Tabs

**Files:**
- Modify: `android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/StatusScreen.kt`

- [ ] **Step 1: Replace dense single screen with tab shell**

In `StatusScreen.kt`, keep the public function signature:

```kotlin
@Composable
fun StatusScreen(
    onUnregister: () -> Unit
)
```

Inside it, derive these values:

```kotlin
val backendUrl by appSettingsStore.backendBaseUrlFlow.collectAsState(initial = "")
val deviceName by appSettingsStore.deviceNameFlow.collectAsState(initial = "")
val targetId by appSettingsStore.targetIdFlow.collectAsState(initial = "")
val wifiOnly by appSettingsStore.wifiOnlyFlow.collectAsState(initial = true)
val lastSyncAt by appSettingsStore.lastSuccessfulSyncAtFlow.collectAsState(initial = 0L)
val syncScope by appSettingsStore.syncScopeFlow.collectAsState(initial = "")
val scopedFolderId by appSettingsStore.scopedFolderIdFlow.collectAsState(initial = "")
val autoDeleteEnabled by appSettingsStore.autoDeleteEnabledFlow.collectAsState(initial = false)
val autoDeleteDelayMinutes by appSettingsStore.autoDeleteDelayMinutesFlow.collectAsState(initial = 24 * 60)
val recentJobs by ledger.recentRecordsFlow.collectAsState(initial = emptyList())
var selectedTab by rememberSaveable { mutableStateOf(PixelTab.Sync) }
```

Use:

```kotlin
Scaffold(
    topBar = { PixelScreenHeader(title = deviceName ?: "Pixel Client", subtitle = scopeLabel) },
    bottomBar = { NavigationBar { /* Sync, Ledger, Settings */ } },
    snackbarHost = { SnackbarHost(snackbarHostState) }
) { padding ->
    when (selectedTab) {
        PixelTab.Sync -> SyncTab(...)
        PixelTab.Ledger -> LedgerTab(...)
        PixelTab.Settings -> SettingsTab(...)
    }
}
```

- [ ] **Step 2: Implement Sync tab without Sync health**

Create private composable in `StatusScreen.kt`:

```kotlin
@Composable
private fun SyncTab(
    recentJobs: List<LocalSyncRecord>,
    lastSyncAt: Long,
    scopeLabel: String,
    onSyncNow: () -> Unit
) {
    val metrics = buildSyncMetrics(recentJobs)
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            ReadyStatusPanel(
                lastSyncLabel = formatLastSyncTime(lastSyncAt),
                scopeLabel = scopeLabel
            )
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                MetricCard("Confirmed", metrics.confirmed.toString(), Icons.Outlined.CheckCircle, Color(0xFF16856A), Modifier.weight(1f))
                MetricCard("Pending", metrics.pending.toString(), Icons.Outlined.Sync, Color(0xFFA76613), Modifier.weight(1f))
                MetricCard("Failed", metrics.failed.toString(), Icons.Outlined.ErrorOutline, Color(0xFFBA2F45), Modifier.weight(1f))
            }
        }
        item {
            Button(
                onClick = onSyncNow,
                modifier = Modifier.fillMaxWidth().height(52.dp),
                shape = RoundedCornerShape(8.dp)
            ) {
                Icon(Icons.Outlined.Sync, contentDescription = null)
                Spacer(Modifier.size(8.dp))
                Text("Sync now", fontWeight = FontWeight.Bold)
            }
        }
        item {
            Text("Recent ledger", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        }
        if (recentJobs.isEmpty()) {
            item {
                Text("No sync records yet.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            items(recentJobs.take(5), key = { it.jobId }) { record ->
                LedgerRecordRow(record)
            }
        }
    }
}
```

Do not add a `Sync health` card to this tab.

- [ ] **Step 3: Implement Ledger tab**

Create:

```kotlin
@Composable
private fun LedgerTab(recentJobs: List<LocalSyncRecord>) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            Text("Sync ledger", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        }
        if (recentJobs.isEmpty()) {
            item {
                Text("No sync records found.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            items(recentJobs, key = { it.jobId }) { record ->
                LedgerRecordRow(record)
            }
        }
    }
}
```

- [ ] **Step 4: Implement Settings tab with Clean up space**

Create:

```kotlin
@Composable
private fun SettingsTab(
    backendUrl: String?,
    targetId: String?,
    syncScopeLabel: String,
    wifiOnly: Boolean,
    autoDeleteEnabled: Boolean,
    autoDeleteDelayMinutes: Int,
    cleanupPreview: CleanupPreview,
    onWifiOnlyChanged: (Boolean) -> Unit,
    onAutoDeleteChanged: (Boolean) -> Unit,
    onAutoDeleteDelayChanged: (Int) -> Unit,
    onCleanUpSpace: () -> Unit,
    onUnregister: () -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Card(shape = RoundedCornerShape(8.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Device target", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Text("Server: ${backendUrl ?: "Not set"}")
                    Text("Target: ${targetId?.take(8) ?: "None"}")
                    Text("Scope: $syncScopeLabel")
                }
            }
        }
        item {
            Card(shape = RoundedCornerShape(8.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Column(Modifier.padding(16.dp)) {
                    SettingsRow("Wi-Fi only", "Avoid mobile data downloads", Icons.Outlined.Wifi) {
                        Switch(checked = wifiOnly, onCheckedChange = onWifiOnlyChanged)
                    }
                    SettingsRow("Auto-delete after sync", "Clean local copies after a delay", Icons.Outlined.DeleteSweep) {
                        Switch(checked = autoDeleteEnabled, onCheckedChange = onAutoDeleteChanged)
                    }
                    if (autoDeleteEnabled) {
                        DelaySelector(autoDeleteDelayMinutes, onAutoDeleteDelayChanged)
                    }
                    OutlinedButton(
                        onClick = onCleanUpSpace,
                        enabled = cleanupPreview.cleanableCount > 0,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(Icons.Outlined.DeleteSweep, contentDescription = null)
                        Spacer(Modifier.size(8.dp))
                        Text("Clean up ${cleanupPreview.cleanableBytesLabel}")
                    }
                }
            }
        }
        item {
            Card(shape = RoundedCornerShape(8.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Background sync", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Text("Push wake-up: Firebase Cloud Messaging")
                    Text("Fallback polling: every 15 minutes")
                }
            }
        }
        item {
            OutlinedButton(onClick = onUnregister, modifier = Modifier.fillMaxWidth()) {
                Text("Unregister device")
            }
        }
    }
}
```

Also create:

```kotlin
@Composable
private fun DelaySelector(selectedMinutes: Int, onSelected: (Int) -> Unit) {
    val options = listOf(120, 360, 1440)
    SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
        options.forEachIndexed { index, minutes ->
            SegmentedButton(
                selected = selectedMinutes == minutes,
                onClick = { onSelected(minutes) },
                shape = SegmentedButtonDefaults.itemShape(index = index, count = options.size)
            ) {
                Text(
                    when (minutes) {
                        120 -> "2h"
                        360 -> "6h"
                        else -> "24h"
                    }
                )
            }
        }
    }
}
```

- [ ] **Step 5: Wire actions**

In `StatusScreen`, create:

```kotlin
val snackbarHostState = remember { SnackbarHostState() }
var showCleanupDialog by remember { mutableStateOf(false) }
val cleanupPreview = buildCleanupPreview(recentJobs)
val repository = remember { DeviceSyncRepository(context) }
```

Wire handlers:

```kotlin
onSyncNow = {
    coroutineScope.launch {
        SyncWorker.enqueueOneTimeSync(context)
        snackbarHostState.showSnackbar("Sync queued")
    }
}
onCleanUpSpace = {
    showCleanupDialog = true
}
```

Dialog:

```kotlin
if (showCleanupDialog) {
    CleanupConfirmDialog(
        preview = cleanupPreview,
        onConfirm = {
            showCleanupDialog = false
            coroutineScope.launch {
                val result = repository.cleanUpSpaceNow()
                snackbarHostState.showSnackbar(
                    "Cleaned ${result.deletedCount} files, freed ${formatBytes(result.freedBytes)}"
                )
            }
        },
        onDismiss = { showCleanupDialog = false }
    )
}
```

Keep existing unregister behavior:

```kotlin
deviceTokenStore.clear()
appSettingsStore.clear()
onUnregister()
```

- [ ] **Step 6: Compile**

Run:

```powershell
.\gradlew.bat :app:compileDebugKotlin
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 7: Commit**

```powershell
git add android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/StatusScreen.kt
git commit -m "feat: redesign pixel sync dashboard"
```

---

### Task 6: Android 10 Manual Device QA

**Files:**
- Modify only if QA finds a defect.

- [ ] **Step 1: Build debug APK**

Run:

```powershell
cd G:\workspace\nexus-relay-mobile\android\pixel
.\gradlew.bat :app:assembleDebug
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 2: Install on Android 10 Pixel**

Run:

```powershell
adb install -r app\build\outputs\apk\debug\app-debug.apk
```

Expected: install succeeds.

- [ ] **Step 3: Verify setup screen**

On device:

- Open app.
- Confirm light modern Pair your Pixel screen.
- Confirm debug build shows server field.
- Register with NexusRelay account.
- Confirm successful transition to dashboard.

- [ ] **Step 4: Verify Sync tab**

On device:

- Confirm Sync tab has no "Sync health" section.
- Confirm status panel, metrics, Sync Now button, and recent ledger render without overlap.
- Tap Sync Now.
- Confirm snackbar `Sync queued` appears.

- [ ] **Step 5: Verify Ledger tab**

On device:

- Open Ledger tab.
- Confirm all recent records render.
- Confirm failed records show error text without overlapping the status chip.

- [ ] **Step 6: Verify Settings tab**

On device:

- Toggle Wi-Fi only.
- Toggle auto-delete.
- Select `2h`, `6h`, `24h`.
- Confirm Background sync appears only in Settings.
- Confirm Unregister still clears state and returns to setup.

- [ ] **Step 7: Verify Clean up space on Android 10**

On device:

- Sync at least one image/video so a confirmed local record exists.
- Open Settings.
- Tap Clean up space.
- Confirm dialog shows count and approximate size.
- Confirm cleanup.
- Confirm snackbar reports deleted count and freed size.
- Confirm ledger row changes to `Cleaned`.
- Confirm deleted media no longer appears in `Pictures/NexusRelay` or `Movies/NexusRelay`.

- [ ] **Step 8: Commit QA fixes if needed**

If code changed:

```powershell
git add android/pixel
git commit -m "fix: polish pixel android 10 ui qa"
```

---

### Task 7: Final Verification

**Files:**
- No planned file edits.

- [ ] **Step 1: Run full unit tests**

Run:

```powershell
cd G:\workspace\nexus-relay-mobile\android\pixel
.\gradlew.bat :app:testDebugUnitTest
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 2: Run debug compile**

Run:

```powershell
.\gradlew.bat :app:compileDebugKotlin
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 3: Run APK build**

Run:

```powershell
.\gradlew.bat :app:assembleDebug
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 4: Check changed files**

Run:

```powershell
git status --short
git diff --stat
```

Expected:

- Only `android/pixel` UI/sync/test/docs files changed.
- No unrelated generated files staged.

- [ ] **Step 5: Final commit**

If all verification passes and no QA fixes remain:

```powershell
git add android/pixel docs/implementation/pixel-modern-ui-mockup.html docs/superpowers/plans/2026-06-06-pixel-modern-ui-cleanup-space.md
git commit -m "feat: modernize pixel companion ui"
```

---

## Self-Review

- Spec coverage: The plan covers the mockup direction, removes Sync health from Sync tab, keeps background sync in Settings, adds Android 10-compatible manual cleanup, preserves registration/sync behavior, and adds tests.
- Placeholder scan: No task depends on vague deferred work. Each new API has concrete names and test expectations.
- Type consistency: `CleanupSpaceResult`, `CleanupPreview`, `PixelTab`, `buildSyncMetrics`, `buildCleanupPreview`, `formatBytes`, and `cleanUpSpaceNow` are introduced before use in UI tasks.
- Android 10 check: The plan uses existing MediaStore content URIs and `ContentResolver.delete`; it does not add broad storage permissions or Android 11+ APIs.
