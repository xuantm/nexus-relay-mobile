# Shared Status Contracts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose shared user-facing status enums for Pixel receive sync and iPhone upload-to-Drive flow while preserving existing internal recovery states.

**Architecture:** Keep backend `DeviceSyncJobStatus` and `MediaItemStatus`, Pixel `LocalSyncStatus`, and iPhone ledger checkpoints as internal state machines. Add projection enums and mapping helpers at DTO/UI boundaries so contracts and user-facing screens show only `Pending/Syncing/Synced/Failed` for Pixel and `Pending/Uploading/Uploaded/Failed` for iPhone uploads.

**Tech Stack:** .NET 10 Minimal APIs, MediatR, EF Core/PostgreSQL, xUnit, NSubstitute, Android Kotlin, Jetpack Compose, Moshi, WorkManager, Swift, SwiftUI, SQLite, XCTest.

---

## File Structure

Backend repo: `G:/workspace/nexus-relay`

- Create: `backend/src/NexusRelay.Backend.Application/DTOs/StatusDtos.cs`
  - Owns public `SyncStatus`, public `UploadStatus`, and projection helpers from internal domain statuses.
- Modify: `backend/src/NexusRelay.Backend.Application/DTOs/DeviceSyncDtos.cs`
  - Add `SyncStatus Status` to `DeviceSyncJobDto`.
- Modify: `backend/src/NexusRelay.Backend.Application/DTOs/Contracts.cs`
  - Add `UploadStatus UploadStatus` to `MediaItemDto`.
- Modify: `backend/src/NexusRelay.Backend.Infrastructure/Services/DeviceSyncService.cs`
  - Populate `DeviceSyncJobDto.Status` for pending-job polling.
- Modify: `backend/src/NexusRelay.Backend.Application/Features/DeviceSync/Queries/GetJobs.cs`
  - Populate `DeviceSyncJobDto.Status` for admin job listing.
- Modify: `backend/src/NexusRelay.Backend.Application/Features/Folders/Queries/GetFolderMediaHandler.cs`
  - Populate `MediaItemDto.UploadStatus`.
- Modify any other `new MediaItemDto(...)` call sites found by build errors.
- Create: `backend/tests/NexusRelay.Backend.Application.Tests/DTOs/StatusProjectionTests.cs`
  - Tests internal-to-shared status mapping.
- Modify or create backend DTO/query tests as needed when constructor signatures change.

Mobile repo: `G:/workspace/nexus-relay-mobile`

- Modify: `docs/contracts/device-sync-api.md`
  - Document `SyncStatus` and the mapping from internal backend and Pixel local states.
- Modify: `docs/contracts/iphone-upload-api.md`
  - Document `UploadStatus` and the mapping from backend media and iPhone ledger states.
- Modify: `android/pixel/app/src/main/java/com/nexusrelay/pixel/api/DeviceSyncDtos.kt`
  - Add `SyncStatus` and decode `DeviceSyncJobDto.status`.
- Modify: `android/pixel/app/src/main/java/com/nexusrelay/pixel/storage/LocalSyncLedger.kt`
  - Keep `LocalSyncStatus`, add projection to `SyncStatus`.
- Modify: `android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/PixelUiModels.kt`
  - Use projected `SyncStatus` for metrics and labels.
- Modify: `android/pixel/app/src/test/java/com/nexusrelay/pixel/api/DeviceSyncDtoTest.kt`
  - Decode `status: "Pending"` from pending-job JSON.
- Modify: `android/pixel/app/src/test/java/com/nexusrelay/pixel/storage/LocalSyncLedgerTest.kt`
  - Assert local states project to shared statuses.
- Modify: `android/pixel/app/src/test/java/com/nexusrelay/pixel/ui/PixelUiModelsTest.kt`
  - Assert user-facing labels say `Synced` and `Syncing`.
- Modify: `ios/iphone/NexusRelayIPhone/Core/Ledger/UploadLedgerModels.swift`
  - Rename the persistent enum to `UploadLedgerStatus`.
  - Add the shared `UploadStatus` enum with the four requested cases.
  - Add `UploadLedgerRecord.uploadStatus`.
- Modify: `ios/iphone/NexusRelayIPhone/Core/Ledger/UploadLedger.swift`
  - Keep ledger methods named by internal transitions.
- Modify: `ios/iphone/NexusRelayIPhone/Core/Ledger/SQLiteUploadLedger.swift`
  - Continue storing the current raw values while decoding them as `UploadLedgerStatus`.
- Modify: `ios/iphone/NexusRelayIPhone/Core/API/APIModels.swift`
  - Add shared upload DTO status if backend media DTOs expose `uploadStatus`.
- Modify: `ios/iphone/NexusRelayIPhone/Features/Queue/UploadQueueModels.swift`
  - Expose `UploadQueueItem.status` as shared `UploadStatus` and retain internal `ledgerStatus` for detail/progress.
- Modify Swift tests under `ios/iphone/NexusRelayIPhoneTests`.

---

## Task 1: Backend Status Projection Tests

**Files:**
- Create: `G:/workspace/nexus-relay/backend/tests/NexusRelay.Backend.Application.Tests/DTOs/StatusProjectionTests.cs`

- [ ] **Step 1: Write failing projection tests**

```csharp
using NexusRelay.Backend.Application.DTOs;
using NexusRelay.Backend.Domain.Entities;
using NexusRelay.Backend.Domain.Enums;
using Xunit;

namespace NexusRelay.Backend.Application.Tests.DTOs;

public sealed class StatusProjectionTests
{
    [Theory]
    [InlineData(DeviceSyncJobStatus.Pending, SyncStatus.Pending)]
    [InlineData(DeviceSyncJobStatus.Notified, SyncStatus.Pending)]
    [InlineData(DeviceSyncJobStatus.Downloading, SyncStatus.Syncing)]
    [InlineData(DeviceSyncJobStatus.ImportedConfirmed, SyncStatus.Synced)]
    [InlineData(DeviceSyncJobStatus.Failed, SyncStatus.Failed)]
    [InlineData(DeviceSyncJobStatus.Skipped, SyncStatus.Failed)]
    [InlineData(DeviceSyncJobStatus.Cancelled, SyncStatus.Failed)]
    public void ToSyncStatus_MapsInternalDeviceSyncStatus(DeviceSyncJobStatus internalStatus, SyncStatus expected)
    {
        Assert.Equal(expected, internalStatus.ToSyncStatus());
    }

    [Theory]
    [InlineData(MediaItemStatus.Pending, UploadStatus.Pending)]
    [InlineData(MediaItemStatus.Buffering, UploadStatus.Uploading)]
    [InlineData(MediaItemStatus.Relaying, UploadStatus.Uploading)]
    [InlineData(MediaItemStatus.Completed, UploadStatus.Uploaded)]
    [InlineData(MediaItemStatus.Failed, UploadStatus.Failed)]
    public void ToUploadStatus_MapsInternalMediaStatus(MediaItemStatus internalStatus, UploadStatus expected)
    {
        Assert.Equal(expected, internalStatus.ToUploadStatus());
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
Set-Location G:/workspace/nexus-relay
dotnet test backend/tests/NexusRelay.Backend.Application.Tests/NexusRelay.Backend.Application.Tests.csproj --filter StatusProjectionTests
```

Expected: fails because `SyncStatus`, `UploadStatus`, `ToSyncStatus`, and `ToUploadStatus` do not exist.

---

## Task 2: Backend Projection Enums And Helpers

**Files:**
- Create: `G:/workspace/nexus-relay/backend/src/NexusRelay.Backend.Application/DTOs/StatusDtos.cs`

- [ ] **Step 1: Add shared status enums and projection helpers**

```csharp
using NexusRelay.Backend.Domain.Entities;
using NexusRelay.Backend.Domain.Enums;

namespace NexusRelay.Backend.Application.DTOs;

public enum SyncStatus
{
    Pending,
    Syncing,
    Synced,
    Failed
}

public enum UploadStatus
{
    Pending,
    Uploading,
    Uploaded,
    Failed
}

public static class StatusDtoMappings
{
    public static SyncStatus ToSyncStatus(this DeviceSyncJobStatus status) =>
        status switch
        {
            DeviceSyncJobStatus.Pending => SyncStatus.Pending,
            DeviceSyncJobStatus.Notified => SyncStatus.Pending,
            DeviceSyncJobStatus.Downloading => SyncStatus.Syncing,
            DeviceSyncJobStatus.ImportedConfirmed => SyncStatus.Synced,
            DeviceSyncJobStatus.Failed => SyncStatus.Failed,
            DeviceSyncJobStatus.Skipped => SyncStatus.Failed,
            DeviceSyncJobStatus.Cancelled => SyncStatus.Failed,
            _ => SyncStatus.Failed
        };

    public static UploadStatus ToUploadStatus(this MediaItemStatus status) =>
        status switch
        {
            MediaItemStatus.Pending => UploadStatus.Pending,
            MediaItemStatus.Buffering => UploadStatus.Uploading,
            MediaItemStatus.Relaying => UploadStatus.Uploading,
            MediaItemStatus.Completed => UploadStatus.Uploaded,
            MediaItemStatus.Failed => UploadStatus.Failed,
            _ => UploadStatus.Failed
        };
}
```

- [ ] **Step 2: Run projection tests**

Run:

```powershell
Set-Location G:/workspace/nexus-relay
dotnet test backend/tests/NexusRelay.Backend.Application.Tests/NexusRelay.Backend.Application.Tests.csproj --filter StatusProjectionTests
```

Expected: PASS.

---

## Task 3: Backend Device Sync DTO Status

**Files:**
- Modify: `G:/workspace/nexus-relay/backend/src/NexusRelay.Backend.Application/DTOs/DeviceSyncDtos.cs`
- Modify: `G:/workspace/nexus-relay/backend/src/NexusRelay.Backend.Infrastructure/Services/DeviceSyncService.cs`
- Modify: `G:/workspace/nexus-relay/backend/src/NexusRelay.Backend.Application/Features/DeviceSync/Queries/GetJobs.cs`

- [ ] **Step 1: Add `Status` to `DeviceSyncJobDto`**

Replace the record with:

```csharp
public record DeviceSyncJobDto(
    Guid JobId,
    Guid MediaId,
    string FileName,
    string MimeType,
    string MediaType,
    long SizeBytes,
    string? Sha256,
    string DownloadUrl,
    DateTimeOffset CreatedAt,
    SyncStatus Status);
```

- [ ] **Step 2: Populate status in pending-job polling**

In `DeviceSyncService.GetPendingJobsAsync`, update the constructor call:

```csharp
dtos.Add(new DeviceSyncJobDto(
    job.Id,
    job.MediaId,
    media.FileName,
    media.MimeType,
    media.MediaType.ToString(),
    media.Size,
    media.FileHash,
    downloadUrl,
    job.CreatedAt,
    job.Status.ToSyncStatus()));
```

- [ ] **Step 3: Populate status in admin job listing**

In `GetJobsHandler.Handle`, update the constructor call:

```csharp
dtos.Add(new DeviceSyncJobDto(
    job.Id,
    job.MediaId,
    media.FileName,
    media.MimeType,
    media.MediaType.ToString(),
    media.Size,
    media.FileHash,
    downloadUrl,
    job.CreatedAt,
    job.Status.ToSyncStatus()));
```

- [ ] **Step 4: Build to find any missed constructor call sites**

Run:

```powershell
Set-Location G:/workspace/nexus-relay
dotnet build backend/NexusRelay.Backend.slnx
```

Expected: build succeeds. If it fails on a `DeviceSyncJobDto` constructor, update that call with `job.Status.ToSyncStatus()`.

---

## Task 4: Backend Media Upload DTO Status

**Files:**
- Modify: `G:/workspace/nexus-relay/backend/src/NexusRelay.Backend.Application/DTOs/Contracts.cs`
- Modify: `G:/workspace/nexus-relay/backend/src/NexusRelay.Backend.Application/Features/Folders/Queries/GetFolderMediaHandler.cs`
- Modify any additional `MediaItemDto` constructor call sites identified by the build.

- [ ] **Step 1: Add `UploadStatus` to `MediaItemDto`**

Change the record in `Contracts.cs` to include a new property after the existing internal `Status`:

```csharp
public record MediaItemDto(
    Guid Id,
    Guid? FolderId,
    string FileName,
    long Size,
    string MimeType,
    int? Width,
    int? Height,
    MediaItemStatus Status,
    UploadStatus UploadStatus,
    MediaType MediaType,
    double? DurationSeconds,
    bool ThumbnailGenerated,
    string? VideoCodec,
    DateTimeOffset CreatedAt,
    DateTimeOffset? CompletedAt
);
```

- [ ] **Step 2: Populate `UploadStatus` in folder media mapping**

In `GetFolderMediaHandler.MapMediaDto`, pass both values:

```csharp
return new MediaItemDto(
    m.Id,
    m.FolderId,
    m.FileName,
    m.Size,
    m.MimeType,
    m.Width,
    m.Height,
    m.Status,
    m.Status.ToUploadStatus(),
    m.MediaType,
    m.DurationSeconds,
    m.ThumbnailGenerated,
    m.VideoCodec,
    m.CreatedAt,
    m.CompletedAt);
```

- [ ] **Step 3: Build to find any missed media DTO call sites**

Run:

```powershell
Set-Location G:/workspace/nexus-relay
dotnet build backend/NexusRelay.Backend.slnx
```

Expected: build succeeds. If any `MediaItemDto` call site fails, add `mediaItem.Status.ToUploadStatus()` immediately after the existing `Status` argument.

---

## Task 5: Pixel Shared Sync Status DTO

**Files:**
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/main/java/com/nexusrelay/pixel/api/DeviceSyncDtos.kt`
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/test/java/com/nexusrelay/pixel/api/DeviceSyncDtoTest.kt`

- [ ] **Step 1: Add failing DTO decode assertion**

In `testPendingJobsJsonDeserialization`, add the status field to JSON:

```json
"createdAt": "2026-06-02T00:00:00Z",
"status": "Pending"
```

Then assert:

```kotlin
assertEquals(SyncStatus.Pending, job.status)
```

- [ ] **Step 2: Run Pixel DTO test to verify failure**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/android/pixel
./gradlew.bat testDebugUnitTest --tests "com.nexusrelay.pixel.api.DeviceSyncDtoTest.testPendingJobsJsonDeserialization"
```

Expected: fails because `SyncStatus` and `DeviceSyncJobDto.status` do not exist.

- [ ] **Step 3: Add shared `SyncStatus` and DTO field**

In `DeviceSyncDtos.kt`, add:

```kotlin
enum class SyncStatus {
    Pending,
    Syncing,
    Synced,
    Failed
}
```

Then update `DeviceSyncJobDto`:

```kotlin
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
```

- [ ] **Step 4: Run Pixel DTO test**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/android/pixel
./gradlew.bat testDebugUnitTest --tests "com.nexusrelay.pixel.api.DeviceSyncDtoTest.testPendingJobsJsonDeserialization"
```

Expected: PASS.

---

## Task 6: Pixel Local Status Projection

**Files:**
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/main/java/com/nexusrelay/pixel/storage/LocalSyncLedger.kt`
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/test/java/com/nexusrelay/pixel/storage/LocalSyncLedgerTest.kt`

- [ ] **Step 1: Add failing projection test**

Add this test to `LocalSyncLedgerTest`:

```kotlin
@Test
fun localSyncStatusProjectsToSharedSyncStatus() {
    assertEquals(SyncStatus.Pending, LocalSyncStatus.Queued.toSyncStatus())
    assertEquals(SyncStatus.Syncing, LocalSyncStatus.Downloading.toSyncStatus())
    assertEquals(SyncStatus.Syncing, LocalSyncStatus.Imported.toSyncStatus())
    assertEquals(SyncStatus.Syncing, LocalSyncStatus.ConfirmPending.toSyncStatus())
    assertEquals(SyncStatus.Synced, LocalSyncStatus.Confirmed.toSyncStatus())
    assertEquals(SyncStatus.Failed, LocalSyncStatus.Failed.toSyncStatus())
}
```

Add import:

```kotlin
import com.nexusrelay.pixel.api.SyncStatus
```

- [ ] **Step 2: Run test to verify failure**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/android/pixel
./gradlew.bat testDebugUnitTest --tests "com.nexusrelay.pixel.storage.LocalSyncLedgerTest.localSyncStatusProjectsToSharedSyncStatus"
```

Expected: fails because `toSyncStatus` does not exist.

- [ ] **Step 3: Add projection helper**

In `LocalSyncLedger.kt`, import `SyncStatus` and add:

```kotlin
import com.nexusrelay.pixel.api.SyncStatus

fun LocalSyncStatus.toSyncStatus(): SyncStatus =
    when (this) {
        LocalSyncStatus.Queued -> SyncStatus.Pending
        LocalSyncStatus.Downloading,
        LocalSyncStatus.Imported,
        LocalSyncStatus.ConfirmPending -> SyncStatus.Syncing
        LocalSyncStatus.Confirmed -> SyncStatus.Synced
        LocalSyncStatus.Failed -> SyncStatus.Failed
    }
```

- [ ] **Step 4: Run local ledger projection test**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/android/pixel
./gradlew.bat testDebugUnitTest --tests "com.nexusrelay.pixel.storage.LocalSyncLedgerTest.localSyncStatusProjectsToSharedSyncStatus"
```

Expected: PASS.

---

## Task 7: Pixel UI Uses Shared Status Labels

**Files:**
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/PixelUiModels.kt`
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/StatusScreen.kt`
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/test/java/com/nexusrelay/pixel/ui/PixelUiModelsTest.kt`

- [ ] **Step 1: Update expected UI labels in tests**

In `PixelUiModelsTest`, update confirmed expectations from `Confirmed` to `Synced`, and add a case for syncing:

```kotlin
assertEquals("Synced", ledgerStatusLabel(record("confirmed", LocalSyncStatus.Confirmed)))
assertEquals("Syncing", ledgerStatusLabel(record("downloading", LocalSyncStatus.Downloading)))
assertEquals("Syncing", ledgerStatusLabel(record("confirming", LocalSyncStatus.ConfirmPending)))
```

- [ ] **Step 2: Run UI model tests to verify failure**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/android/pixel
./gradlew.bat testDebugUnitTest --tests "com.nexusrelay.pixel.ui.PixelUiModelsTest"
```

Expected: fails while labels still say `Confirmed`, `Downloading`, or `Confirming`.

- [ ] **Step 3: Update label projection**

In `PixelUiModels.kt`, use `toSyncStatus()`:

```kotlin
fun ledgerStatusLabel(record: LocalSyncRecord): String {
    if (record.status == LocalSyncStatus.Confirmed && record.isLocalDeleted) {
        return "Synced, local copy removed"
    }

    return when (record.status.toSyncStatus()) {
        SyncStatus.Pending -> "Pending"
        SyncStatus.Syncing -> "Syncing"
        SyncStatus.Synced -> "Synced"
        SyncStatus.Failed -> "Failed"
    }
}
```

Keep any detailed internal wording only in secondary/debug text, not the primary status label.

- [ ] **Step 4: Rename visible metric labels**

In `StatusScreen.kt`, change the metric label:

```kotlin
MetricCard("Synced", metrics.confirmed.toString(), Icons.Outlined.CheckCircle, Color(0xFF16856A), Modifier.weight(1f))
```

Keep the property name `confirmed` unless you also rename all internal model tests in the same task. The user-facing label is the requirement.

- [ ] **Step 5: Run Pixel UI tests**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/android/pixel
./gradlew.bat testDebugUnitTest --tests "com.nexusrelay.pixel.ui.PixelUiModelsTest"
```

Expected: PASS.

---

## Task 8: iPhone Ledger Keeps Internal Status And Adds Shared UploadStatus

**Files:**
- Modify: `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhone/Core/Ledger/UploadLedgerModels.swift`
- Modify: `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhone/Core/Ledger/SQLiteUploadLedger.swift`
- Modify: `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhoneTests/Ledger/SQLiteUploadLedgerTests.swift`

- [ ] **Step 1: Add failing shared-status assertions**

In `SQLiteUploadLedgerTests.testLedgerTransitions`, add these exact assertions next to the existing internal status assertions:

```swift
// after initial discovered
XCTAssertEqual(batch.first?.uploadStatus, .Pending)

// after exporting
XCTAssertEqual(batch.first?.uploadStatus, .Uploading)

// after readyToUpload
XCTAssertEqual(batch.first?.uploadStatus, .Pending)

// after uploading
XCTAssertEqual(batch.first?.uploadStatus, .Uploading)
```

Add a separate test for direct projection on every internal iPhone ledger status:

```swift
func testUploadLedgerStatusProjectsToSharedUploadStatus() {
    XCTAssertEqual(UploadLedgerStatus.discovered.uploadStatus, .Pending)
    XCTAssertEqual(UploadLedgerStatus.readyToUpload.uploadStatus, .Pending)
    XCTAssertEqual(UploadLedgerStatus.skipped.uploadStatus, .Pending)
    XCTAssertEqual(UploadLedgerStatus.exporting.uploadStatus, .Uploading)
    XCTAssertEqual(UploadLedgerStatus.uploading.uploadStatus, .Uploading)
    XCTAssertEqual(UploadLedgerStatus.uploaded.uploadStatus, .Uploaded)
    XCTAssertEqual(UploadLedgerStatus.synced.uploadStatus, .Uploaded)
    XCTAssertEqual(UploadLedgerStatus.failed.uploadStatus, .Failed)
}
```

- [ ] **Step 2: Run iPhone ledger test to verify failure**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/ios/iphone
xcodegen generate
xcodebuild -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/SQLiteUploadLedgerTests
```

Expected: fails because `uploadStatus` and the new enum cases do not exist.

- [ ] **Step 3: Rename internal enum and add public projection enum**

In `UploadLedgerModels.swift`, replace the current enum with:

```swift
enum UploadLedgerStatus: String, Codable, Equatable {
    case discovered
    case exporting
    case readyToUpload
    case uploading
    case uploaded
    case synced
    case failed
    case skipped
}

enum UploadStatus: String, Codable, Equatable {
    case Pending
    case Uploading
    case Uploaded
    case Failed
}

extension UploadLedgerStatus {
    var uploadStatus: UploadStatus {
        switch self {
        case .discovered, .readyToUpload, .skipped:
            return .Pending
        case .exporting, .uploading:
            return .Uploading
        case .uploaded, .synced:
            return .Uploaded
        case .failed:
            return .Failed
        }
    }
}
```

Update `UploadLedgerRecord`:

```swift
let status: UploadLedgerStatus

var uploadStatus: UploadStatus {
    status.uploadStatus
}
```

- [ ] **Step 4: Update SQLite decoder**

In `SQLiteUploadLedger.readRecord`, change:

```swift
status: UploadLedgerStatus(rawValue: statusRaw) ?? .discovered,
```

Do not change the stored SQLite raw values. Existing rows such as `discovered`, `readyToUpload`, and `uploaded` remain valid.

- [ ] **Step 5: Update compile errors from enum rename**

Replace type references that mean internal ledger state:

```swift
UploadStatus
```

with:

```swift
UploadLedgerStatus
```

Do this in test helpers and ledger-facing fake types where the status value is `.discovered`, `.exporting`, `.readyToUpload`, `.uploading`, `.uploaded`, `.synced`, `.failed`, or `.skipped`.

- [ ] **Step 6: Run iPhone ledger tests**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/ios/iphone
xcodegen generate
xcodebuild -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/SQLiteUploadLedgerTests
```

Expected: PASS.

---

## Task 9: iPhone Queue UI Uses Shared UploadStatus

**Files:**
- Modify: `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhone/Features/Queue/UploadQueueModels.swift`
- Modify: `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhoneTests/Queue/UploadQueueViewModelTests.swift`

- [ ] **Step 1: Update queue model tests**

In `UploadQueueViewModelTests`, keep record creation using internal `UploadLedgerStatus`, and add assertions for shared status:

```swift
let uploading = UploadQueueItem(record: makeRecord(status: .uploading, lastError: nil))
let waiting = UploadQueueItem(record: makeRecord(status: .discovered, lastError: nil))

XCTAssertEqual(uploading.status, .Uploading)
XCTAssertEqual(waiting.status, .Pending)
```

Update helper signatures:

```swift
private func makeRecord(status: UploadLedgerStatus, lastError: String?) -> UploadLedgerRecord
private func makeRecord(id: String, status: UploadLedgerStatus) -> UploadLedgerRecord
```

- [ ] **Step 2: Run queue tests to verify failure**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/ios/iphone
xcodegen generate
xcodebuild -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/UploadQueueViewModelTests
```

Expected: fails while `UploadQueueItem.status` still uses the internal ledger enum.

- [ ] **Step 3: Update `UploadQueueItem`**

In `UploadQueueModels.swift`, change fields:

```swift
let ledgerStatus: UploadLedgerStatus
let status: UploadStatus
```

Update initializer:

```swift
self.ledgerStatus = record.status
self.status = record.uploadStatus
self.canRetry = record.status == .failed
```

Keep detailed labels and progress based on internal state:

```swift
self.statusText = Self.statusText(for: record)
self.progressFraction = Self.progressFraction(for: record.status)
```

Update helper signatures:

```swift
private static func progressFraction(for status: UploadLedgerStatus) -> Double
```

- [ ] **Step 4: Run queue tests**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/ios/iphone
xcodegen generate
xcodebuild -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/UploadQueueViewModelTests
```

Expected: PASS.

---

## Task 10: iPhone API Models Accept Backend `uploadStatus`

**Files:**
- Modify: `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhone/Core/API/APIModels.swift`
- Modify: `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhoneTests/API/NexusRelayAPIClientTests.swift`

- [ ] **Step 1: Add API decode assertion**

In the folder media decode test JSON, add:

```json
"status": "Completed",
"uploadStatus": "Uploaded"
```

Assert:

```swift
XCTAssertEqual(item.status, .completed)
XCTAssertEqual(item.uploadStatus, .Uploaded)
```

- [ ] **Step 2: Run API client test to verify failure**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/ios/iphone
xcodegen generate
xcodebuild -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/NexusRelayAPIClientTests
```

Expected: fails because `MediaItemDTO.uploadStatus` does not exist.

- [ ] **Step 3: Add `uploadStatus` to `MediaItemDTO`**

In `APIModels.swift`, add:

```swift
let uploadStatus: UploadStatus?
```

Keep it optional so the app can still decode older backend responses during rollout.

- [ ] **Step 4: Run API client tests**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/ios/iphone
xcodegen generate
xcodebuild -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/NexusRelayAPIClientTests
```

Expected: PASS.

---

## Task 11: Contract Documentation

**Files:**
- Modify: `G:/workspace/nexus-relay-mobile/docs/contracts/device-sync-api.md`
- Modify: `G:/workspace/nexus-relay-mobile/docs/contracts/iphone-upload-api.md`

- [ ] **Step 1: Update device sync pending-job response**

Add `status` to the example:

```json
{
  "jobId": "8af63b26-f7af-4fe0-8cb5-5dc43edcc9ef",
  "mediaId": "94aa00ac-219a-4d65-8ff4-11ffc7a042e1",
  "fileName": "IMG_1001.HEIC",
  "mimeType": "image/heic",
  "mediaType": "Image",
  "sizeBytes": 4820131,
  "sha256": "3a6eb0790f39ac87c94f3856b2dd2c5d110e6811602261a9a923d3bb23adc8b7",
  "downloadUrl": "/api/device-sync/jobs/8af63b26-f7af-4fe0-8cb5-5dc43edcc9ef/download",
  "createdAt": "2026-06-02T00:00:00Z",
  "status": "Pending"
}
```

Replace the status vocabulary section with:

```text
Shared user-facing SyncStatus:
- Pending
- Syncing
- Synced
- Failed

Backend internal mapping:
- Pending, Notified -> Pending
- Downloading -> Syncing
- ImportedConfirmed -> Synced
- Failed, Skipped, Cancelled -> Failed

Pixel local mapping:
- Queued -> Pending
- Downloading, Imported, ConfirmPending -> Syncing
- Confirmed -> Synced
- Failed -> Failed
```

- [ ] **Step 2: Update iPhone upload contract**

In media item response examples, keep `status` and add:

```json
"uploadStatus": "Uploaded"
```

Add:

```text
Shared user-facing UploadStatus:
- Pending
- Uploading
- Uploaded
- Failed

Backend media mapping:
- Pending -> Pending
- Buffering, Relaying -> Uploading
- Completed -> Uploaded
- Failed -> Failed

iPhone local ledger mapping:
- discovered, readyToUpload, skipped -> Pending
- exporting, uploading -> Uploading
- uploaded, synced -> Uploaded
- failed -> Failed
```

- [ ] **Step 3: Review docs for old primary labels**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile
rg -n "ImportedConfirmed|Confirmed|Downloading|readyToUpload|relaying" docs/contracts
```

Expected: old internal terms may appear only in mapping sections or endpoint names. They should not appear as the primary user-facing status contract.

---

## Task 12: Full Verification

**Files:**
- No code edits unless verification exposes a concrete compile or test failure.

- [ ] **Step 1: Run backend test suite**

Run:

```powershell
Set-Location G:/workspace/nexus-relay
dotnet test backend/tests/NexusRelay.Backend.Application.Tests/NexusRelay.Backend.Application.Tests.csproj
```

Expected: PASS.

- [ ] **Step 2: Run backend build**

Run:

```powershell
Set-Location G:/workspace/nexus-relay
dotnet build backend/NexusRelay.Backend.slnx
```

Expected: PASS.

- [ ] **Step 3: Run Pixel unit tests**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/android/pixel
./gradlew.bat testDebugUnitTest
```

Expected: PASS.

- [ ] **Step 4: Run iPhone unit tests**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/ios/iphone
xcodegen generate
xcodebuild -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Expected: PASS.

- [ ] **Step 5: Manual behavior check**

Verify the status display through one end-to-end cycle:

```text
iPhone uploads an item:
Pending -> Uploading -> Uploaded

Backend creates Pixel job:
Pending

Pixel receives/downloads/imports:
Pending -> Syncing -> Synced

Any terminal device/import error:
Failed
```

Confirm that internal resume behavior still works:

```text
Pixel ConfirmPending records retry confirmation without redownloading.
iPhone failed retryable records remain retryable until attempt_count reaches 3.
Existing iPhone SQLite rows with discovered/exporting/readyToUpload/uploading/uploaded/synced/failed decode successfully.
Existing Pixel DataStore rows with Queued/Downloading/Imported/ConfirmPending/Confirmed/Failed decode successfully.
```
