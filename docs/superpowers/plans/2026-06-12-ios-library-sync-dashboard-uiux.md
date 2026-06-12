# iOS Library Sync Dashboard UI/UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current image-preview-based Library Sync screen with a data-rich dashboard matching the approved mockup, backed by real local sync, ledger, and upload telemetry data.

**Architecture:** Keep this as an iOS-only change. Derive dashboard metrics from the existing SQLite upload ledger, sync runtime state, settings, auth/session repair state, and existing HTTP upload progress callbacks. Do not add backend endpoints for v1 because the mockup data can be computed locally and adding server health APIs would widen the contract without a product need.

**Tech Stack:** Swift 5.10, SwiftUI, Combine, XCTest, SQLite via `SQLiteUploadLedger`, PhotoKit upload pipeline, existing `HTTPUploadProgressHandler`, XcodeGen project source globs.

---

## Brainstorming Decision Record

The chosen approach is **local truthful dashboard state**.

Rejected approach: render the mockup with static or optimistic values. This would look polished but would mislead users about upload speed, remaining bytes, ETA, and queue health.

Rejected approach: add backend dashboard/health endpoints immediately. The backend is not the source of truth for iPhone local queue state, staged exports, PhotoKit scan count, or active upload bytes. A backend endpoint may be useful later for account-wide health, but it is unnecessary for this screen.

Recommended approach: create a small iOS dashboard domain around the existing ledger and upload pipeline. The SwiftUI screen consumes one view-model state object, while ledger and telemetry services provide accurate metrics.

## Current Code Findings

- `ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncView.swift` currently shows `PhotoMosaicView`, preview selection, a preview sheet, the existing progress block, and one primary sync/pause button.
- `ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncViewModel.swift` currently exposes `LibrarySyncSummary`, `previewItems`, `selectedPreviewItem`, `loadPreviewItems()`, and maps `SyncStatusSnapshot` into basic counts.
- `ios/iphone/NexusRelayIPhone/Features/SyncStatus/SyncStatusViewModel.swift` owns sync state, ledger references, polling, last sync date, auth repair flags, and publishes `SyncStatusSnapshot`.
- `ios/iphone/NexusRelayIPhone/Core/Ledger/SQLiteUploadLedger.swift` already stores `resource_kind`, `size_bytes`, and `status`, which are enough to compute remaining bytes and next-batch photo/video counts without a schema migration.
- `ios/iphone/NexusRelayIPhone/Core/API/NexusRelayAPIClient.swift` and `ios/iphone/NexusRelayIPhone/Core/API/HTTPClient.swift` already expose `HTTPUploadProgressHandler`; `SystemUploadEngine` currently does not pass a handler.
- `nexus-relay` backend requires no code change for this phase.

## Mockup Mapping

| Mockup element | Current source | Missing work |
|---|---|---|
| `68% Uploaded` | `LibrarySyncSummary.progressFraction` | Keep, but move into dashboard model. |
| `Uploading` pill | `ActiveSyncStatus` | Add display metadata and color mapping. |
| Progress bar | `displayedProgress` | Keep smooth progress. |
| `18 min left` | None | Add speed + remaining bytes telemetry. |
| `12 MB/s` | Existing upload progress callback unused by engine | Pass progress into `SystemUploadEngine` and track rolling speed. |
| `1.8 GB Remaining` | Ledger `size_bytes` | Add ledger dashboard summary query. |
| `Scanned 1,164 assets found` | Scan count is logged only | Publish latest scan count from orchestrator into sync status. |
| `Exporting 2` | `SyncStatusSnapshot.exportingCount` | Keep. |
| `Uploading 2` | `SyncStatusSnapshot.uploadingCount` | Keep. |
| Uploaded/waiting/active/failed cards | Existing counts | Restyle. |
| `Next batch: 42 photos | 7 videos` | Ledger records have `resource_kind` | Add next-batch summary query. |
| `Est. 18 min - 195 MB` | None | Compute from next batch bytes and speed. |
| `Session healthy` | `requiresSignInRepair`, errors | Add explicit `SessionHealth` presentation model. |
| `Safe to close app: Yes` | Background support exists, state implicit | Add conservative presentation rule. |
| `Pause Sync`, `View Queue` | `pauseSync()`, `onOpenQueue` | Restyle as two-button action bar. |
| No image content | Current screen loads thumbnails | Remove preview loading and preview sheet from Sync screen. |

## File Structure

Create:

- `ios/iphone/NexusRelayIPhone/Core/Upload/UploadProgressTracker.swift` owns rolling upload speed, active upload bytes, ETA inputs, reset behavior, and testable snapshots.
- `ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncDashboardModels.swift` owns pure dashboard presentation models and formatting.
- `ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncDashboardComponents.swift` owns SwiftUI card components for the redesigned screen.
- `ios/iphone/NexusRelayIPhoneTests/Upload/UploadProgressTrackerTests.swift` verifies speed, reset, active bytes, and ETA-safe behavior.

Modify:

- `ios/iphone/NexusRelayIPhone/Core/Ledger/UploadLedger.swift` adds dashboard summary models and protocol method.
- `ios/iphone/NexusRelayIPhone/Core/Ledger/SQLiteUploadLedger.swift` implements the dashboard summary query.
- `ios/iphone/NexusRelayIPhone/Core/Upload/UploadEngine.swift` accepts an optional progress reporter and forwards progress to API calls.
- `ios/iphone/NexusRelayIPhone/Core/Upload/SyncOrchestrator.swift` reports scan count and resets upload telemetry per sync session.
- `ios/iphone/NexusRelayIPhone/Features/SyncStatus/SyncStatusViewModel.swift` wires ledger dashboard summary and upload tracker into a richer published dashboard snapshot.
- `ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncViewModel.swift` removes image preview state and exposes dashboard state.
- `ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncView.swift` renders the new dashboard UI without `PhotoMosaicView`.
- `ios/iphone/NexusRelayIPhoneTests/Ledger/SQLiteUploadLedgerTests.swift` adds dashboard summary coverage.
- `ios/iphone/NexusRelayIPhoneTests/Upload/UploadEngineTests.swift` verifies progress forwarding.
- `ios/iphone/NexusRelayIPhoneTests/SyncStatus/SyncStatusViewModelTests.swift` verifies dashboard snapshot mapping.
- `ios/iphone/NexusRelayIPhoneTests/LibrarySync/LibrarySyncViewModelTests.swift` verifies presentation model mapping.

Do not modify:

- `G:/workspace/nexus-relay/backend` for this UI phase.
- `ios/iphone/NexusRelayIPhone.xcodeproj`; XcodeGen regenerates it from `project.yml`.
- Android Pixel app.

---

### Task 1: Add Ledger Dashboard Summary

**Files:**

- Modify: `ios/iphone/NexusRelayIPhone/Core/Ledger/UploadLedger.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Core/Ledger/SQLiteUploadLedger.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/Ledger/SQLiteUploadLedgerTests.swift`

- [ ] **Step 1: Add failing ledger summary test**

Append this test to `SQLiteUploadLedgerTests`.

```swift
func testDashboardSummaryIncludesRemainingBytesAndNextBatchKinds() async throws {
    let folderId = UUID()
    let candidates = [
        PhotoAssetCandidate(
            assetLocalIdentifier: "photo-1",
            resourceKind: .image,
            originalFilename: "IMG_0001.JPG",
            uniformTypeIdentifier: "public.jpeg",
            mimeType: "image/jpeg",
            creationDate: Date(timeIntervalSince1970: 1),
            modificationDate: nil,
            pixelWidth: 4032,
            pixelHeight: 3024,
            durationSeconds: nil,
            resourceFileSize: 100
        ),
        PhotoAssetCandidate(
            assetLocalIdentifier: "video-1",
            resourceKind: .video,
            originalFilename: "VID_0001.MOV",
            uniformTypeIdentifier: "com.apple.quicktime-movie",
            mimeType: "video/quicktime",
            creationDate: Date(timeIntervalSince1970: 2),
            modificationDate: nil,
            pixelWidth: 1920,
            pixelHeight: 1080,
            durationSeconds: 12,
            resourceFileSize: 400
        ),
        PhotoAssetCandidate(
            assetLocalIdentifier: "live-1",
            resourceKind: .livePhotoVideo,
            originalFilename: "IMG_0002.MOV",
            uniformTypeIdentifier: "com.apple.quicktime-movie",
            mimeType: "video/quicktime",
            creationDate: Date(timeIntervalSince1970: 3),
            modificationDate: nil,
            pixelWidth: 1920,
            pixelHeight: 1080,
            durationSeconds: 3,
            resourceFileSize: 300
        )
    ]

    try await ledger.upsertDiscovered(candidates, folderId: folderId)
    let records = try await ledger.nextUploadBatch(limit: 10)
    try await ledger.markExporting(id: records[0].id)
    try await ledger.markReady(id: records[0].id, stagedFileURL: URL(fileURLWithPath: "/tmp/photo"), sizeBytes: 120)
    try await ledger.markUploaded(id: records[0].id, backendUploadId: UUID())

    let summary = try await ledger.getDashboardSummary(nextBatchLimit: 10)

    XCTAssertEqual(summary.counts.uploaded, 1)
    XCTAssertEqual(summary.counts.queued, 2)
    XCTAssertEqual(summary.remainingBytes, 700)
    XCTAssertEqual(summary.nextBatch.photoCount, 0)
    XCTAssertEqual(summary.nextBatch.videoCount, 2)
    XCTAssertEqual(summary.nextBatch.totalBytes, 700)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd ios/iphone
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/SQLiteUploadLedgerTests/testDashboardSummaryIncludesRemainingBytesAndNextBatchKinds
```

Expected: FAIL because `getDashboardSummary(nextBatchLimit:)`, `LedgerDashboardSummary`, and `LedgerNextBatchSummary` do not exist.

- [ ] **Step 3: Add protocol models**

Add these definitions above `protocol UploadLedger` in `UploadLedger.swift`.

```swift
struct LedgerNextBatchSummary: Equatable {
    let photoCount: Int
    let videoCount: Int
    let totalBytes: Int64
}

struct LedgerDashboardSummary: Equatable {
    let counts: LedgerCounts
    let remainingBytes: Int64
    let nextBatch: LedgerNextBatchSummary
}
```

Add this requirement to `UploadLedger`.

```swift
func getDashboardSummary(nextBatchLimit: Int) async throws -> LedgerDashboardSummary
```

- [ ] **Step 4: Implement SQLite dashboard summary**

Add this method to `SQLiteUploadLedger`.

```swift
func getDashboardSummary(nextBatchLimit: Int) async throws -> LedgerDashboardSummary {
    let counts = try await getLedgerCounts()
    let remainingBytes = try await sumBytes(
        whereClause: "status IN ('discovered', 'exporting', 'readyToUpload', 'uploading', 'failed')"
    )
    let nextBatch = try await nextBatchSummary(limit: nextBatchLimit)

    return LedgerDashboardSummary(
        counts: counts,
        remainingBytes: remainingBytes,
        nextBatch: nextBatch
    )
}
```

Add helper methods in the same class.

```swift
private func sumBytes(whereClause: String) async throws -> Int64 {
    lock.lock()
    defer { lock.unlock() }

    let sql = "SELECT COALESCE(SUM(COALESCE(size_bytes, 0)), 0) FROM upload_ledger WHERE \(whereClause);"
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw DatabaseError.prepareFailed(errorMessage())
    }
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_step(stmt) == SQLITE_ROW else {
        return 0
    }

    return sqlite3_column_int64(stmt, 0)
}

private func nextBatchSummary(limit: Int) async throws -> LedgerNextBatchSummary {
    let records = try await nextUploadBatch(limit: limit)
    let photoCount = records.filter { $0.resourceKind == .image }.count
    let videoCount = records.filter { $0.resourceKind == .video || $0.resourceKind == .livePhotoVideo }.count
    let totalBytes = records.reduce(Int64(0)) { partial, record in
        partial + (record.sizeBytes ?? 0)
    }

    return LedgerNextBatchSummary(
        photoCount: photoCount,
        videoCount: videoCount,
        totalBytes: totalBytes
    )
}
```

- [ ] **Step 5: Run ledger test**

Run:

```bash
cd ios/iphone
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/SQLiteUploadLedgerTests/testDashboardSummaryIncludesRemainingBytesAndNextBatchKinds
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Core/Ledger/UploadLedger.swift ios/iphone/NexusRelayIPhone/Core/Ledger/SQLiteUploadLedger.swift ios/iphone/NexusRelayIPhoneTests/Ledger/SQLiteUploadLedgerTests.swift
git commit -m "feat(ios): add sync dashboard ledger summary"
```

---

### Task 2: Add Upload Progress Tracker

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Core/Upload/UploadProgressTracker.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/Upload/UploadProgressTrackerTests.swift`

- [ ] **Step 1: Add failing tracker tests**

Create `UploadProgressTrackerTests.swift`.

```swift
import XCTest
@testable import NexusRelayIPhone

final class UploadProgressTrackerTests: XCTestCase {
    func testRecordsRollingSpeedAndActiveBytes() async {
        let tracker = UploadProgressTracker()

        await tracker.resetSession()
        await tracker.recordUploadProgress(recordId: "a", bytesSent: 100, totalBytes: 1_000, at: Date(timeIntervalSince1970: 10))
        await tracker.recordUploadProgress(recordId: "a", bytesSent: 700, totalBytes: 1_000, at: Date(timeIntervalSince1970: 13))

        let snapshot = await tracker.snapshot(remainingBytes: 3_000)

        XCTAssertEqual(snapshot.activeUploadedBytes, 700)
        XCTAssertEqual(snapshot.activeTotalBytes, 1_000)
        XCTAssertEqual(snapshot.bytesPerSecond, 200, accuracy: 0.1)
        XCTAssertEqual(snapshot.estimatedSecondsRemaining, 15, accuracy: 0.1)
    }

    func testResetClearsSessionState() async {
        let tracker = UploadProgressTracker()

        await tracker.recordUploadProgress(recordId: "a", bytesSent: 250, totalBytes: 500, at: Date(timeIntervalSince1970: 1))
        await tracker.resetSession()
        let snapshot = await tracker.snapshot(remainingBytes: 500)

        XCTAssertEqual(snapshot.activeUploadedBytes, 0)
        XCTAssertEqual(snapshot.activeTotalBytes, 0)
        XCTAssertNil(snapshot.bytesPerSecond)
        XCTAssertNil(snapshot.estimatedSecondsRemaining)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd ios/iphone
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/UploadProgressTrackerTests
```

Expected: FAIL because `UploadProgressTracker` does not exist.

- [ ] **Step 3: Create tracker implementation**

Create `UploadProgressTracker.swift`.

```swift
import Foundation

struct UploadProgressTelemetrySnapshot: Equatable {
    let activeUploadedBytes: Int64
    let activeTotalBytes: Int64
    let bytesPerSecond: Double?
    let estimatedSecondsRemaining: Double?
}

actor UploadProgressTracker {
    private struct Sample {
        let bytesSent: Int64
        let totalBytes: Int64
        let date: Date
    }

    private var latestByRecord: [String: Sample] = [:]
    private var previousSample: Sample?
    private var latestSample: Sample?

    func resetSession() {
        latestByRecord.removeAll()
        previousSample = nil
        latestSample = nil
    }

    func recordUploadProgress(recordId: String, bytesSent: Int64, totalBytes: Int64, at date: Date = Date()) {
        let sample = Sample(bytesSent: bytesSent, totalBytes: totalBytes, date: date)
        latestByRecord[recordId] = sample

        if let latestSample, date.timeIntervalSince(latestSample.date) > 0 {
            previousSample = latestSample
        }
        latestSample = sample
    }

    func snapshot(remainingBytes: Int64) -> UploadProgressTelemetrySnapshot {
        let activeUploadedBytes = latestByRecord.values.reduce(Int64(0)) { $0 + $1.bytesSent }
        let activeTotalBytes = latestByRecord.values.reduce(Int64(0)) { $0 + $1.totalBytes }
        let speed = currentBytesPerSecond()
        let eta = speed.flatMap { $0 > 0 ? Double(max(remainingBytes, 0)) / $0 : nil }

        return UploadProgressTelemetrySnapshot(
            activeUploadedBytes: activeUploadedBytes,
            activeTotalBytes: activeTotalBytes,
            bytesPerSecond: speed,
            estimatedSecondsRemaining: eta
        )
    }

    private func currentBytesPerSecond() -> Double? {
        guard let previousSample, let latestSample else {
            return nil
        }

        let elapsed = latestSample.date.timeIntervalSince(previousSample.date)
        guard elapsed > 0 else {
            return nil
        }

        let deltaBytes = latestSample.bytesSent - previousSample.bytesSent
        guard deltaBytes >= 0 else {
            return nil
        }

        return Double(deltaBytes) / elapsed
    }
}
```

- [ ] **Step 4: Run tracker tests**

Run:

```bash
cd ios/iphone
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/UploadProgressTrackerTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Core/Upload/UploadProgressTracker.swift ios/iphone/NexusRelayIPhoneTests/Upload/UploadProgressTrackerTests.swift
git commit -m "feat(ios): track upload progress telemetry"
```

---

### Task 3: Forward Upload Progress From Upload Engine

**Files:**

- Modify: `ios/iphone/NexusRelayIPhone/Core/Upload/UploadEngine.swift`
- Modify: `ios/iphone/NexusRelayIPhoneTests/Upload/UploadEngineTests.swift`

- [ ] **Step 1: Add failing stream progress forwarding test**

Append this test to `UploadEngineTests`.

```swift
func testStreamUploadForwardsProgressToTracker() async throws {
    api.onStreamUpload = { progress in
        await progress?(HTTPUploadProgress(bytesSent: 50, totalBytes: 100))
    }

    let tracker = UploadProgressTracker()
    let engine = SystemUploadEngine(
        apiClient: api,
        chunkFileBuilder: chunkBuilder,
        policy: policy,
        progressTracker: tracker
    )

    let record = UploadLedgerRecord(
        id: "progress-stream",
        assetLocalIdentifier: "asset-progress",
        resourceKind: .image,
        fingerprintSuffix: "progresssuffix",
        originalFilename: "progress.jpg",
        uploadedFileName: "progress__nr-progresssuffix.jpg",
        mimeType: "image/jpeg",
        sizeBytes: 80,
        status: .readyToUpload,
        backendFolderId: nil,
        backendUploadId: nil,
        localStagedFileURL: tempFileURL,
        attemptCount: 0,
        lastAttemptAt: nil,
        lastError: nil
    )

    _ = try await engine.upload(record: record, folderId: UUID())
    let snapshot = await tracker.snapshot(remainingBytes: 80)

    XCTAssertEqual(snapshot.activeUploadedBytes, 50)
    XCTAssertEqual(snapshot.activeTotalBytes, 100)
}
```

Modify `MockNexusRelayAPI` to support this test.

```swift
var onStreamUpload: ((HTTPUploadProgressHandler?) async -> Void)?
var onUploadChunk: ((HTTPUploadProgressHandler?) async -> Void)?
```

In `streamUpload(...)`, call:

```swift
await onStreamUpload?(progress)
```

In `uploadChunk(...)`, call:

```swift
await onUploadChunk?(progress)
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd ios/iphone
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/UploadEngineTests/testStreamUploadForwardsProgressToTracker
```

Expected: FAIL because `SystemUploadEngine` does not accept `progressTracker`.

- [ ] **Step 3: Add tracker dependency to upload engine**

Update `SystemUploadEngine`.

```swift
final class SystemUploadEngine: UploadEngine {
    private let apiClient: NexusRelayAPI
    private let chunkFileBuilder: ChunkFileBuilder
    private let policy: UploadPolicy
    private let progressTracker: UploadProgressTracker?

    init(
        apiClient: NexusRelayAPI,
        chunkFileBuilder: ChunkFileBuilder = SystemChunkFileBuilder(),
        policy: UploadPolicy = .nexusRelayDefault,
        progressTracker: UploadProgressTracker? = nil
    ) {
        self.apiClient = apiClient
        self.chunkFileBuilder = chunkFileBuilder
        self.policy = policy
        self.progressTracker = progressTracker
    }
}
```

Add this helper in `SystemUploadEngine`.

```swift
private func progressHandler(for record: UploadLedgerRecord) -> HTTPUploadProgressHandler? {
    guard let progressTracker else {
        return nil
    }

    return { progress in
        await progressTracker.recordUploadProgress(
            recordId: record.id,
            bytesSent: progress.bytesSent,
            totalBytes: progress.totalBytes ?? record.sizeBytes ?? progress.bytesSent
        )
    }
}
```

- [ ] **Step 4: Pass progress into stream and chunk uploads**

In the stream upload branch, pass:

```swift
progress: progressHandler(for: record)
```

In the chunk upload branch, pass:

```swift
progress: progressHandler(for: record)
```

The resulting stream call should have this shape:

```swift
let response = try await apiClient.streamUpload(
    fileURL: localURL,
    fileName: record.uploadedFileName,
    folderId: folderId,
    mimeType: record.mimeType,
    fileSize: fileSize,
    progress: progressHandler(for: record)
)
```

The resulting chunk call should have this shape:

```swift
try await apiClient.uploadChunk(
    uploadId: uploadId,
    chunkIndex: chunkIndex,
    chunkSize: actualChunkSize,
    chunkFileURL: chunkURL,
    progress: progressHandler(for: record)
)
```

- [ ] **Step 5: Run upload engine tests**

Run:

```bash
cd ios/iphone
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/UploadEngineTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Core/Upload/UploadEngine.swift ios/iphone/NexusRelayIPhoneTests/Upload/UploadEngineTests.swift
git commit -m "feat(ios): forward upload progress telemetry"
```

---

### Task 4: Publish Sync Dashboard Runtime State

**Files:**

- Modify: `ios/iphone/NexusRelayIPhone/Core/Upload/SyncOrchestrator.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Features/SyncStatus/SyncStatusViewModel.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/SyncStatus/SyncStatusViewModelTests.swift`

- [ ] **Step 1: Add dashboard snapshot model**

Add this near `SyncStatusSnapshot` in `SyncStatusViewModel.swift`.

```swift
struct SyncDashboardRuntimeSnapshot: Equatable {
    let ledgerSummary: LedgerDashboardSummary
    let telemetry: UploadProgressTelemetrySnapshot
    let scannedAssetCount: Int?

    static let empty = SyncDashboardRuntimeSnapshot(
        ledgerSummary: LedgerDashboardSummary(
            counts: LedgerCounts(queued: 0, uploaded: 0, failed: 0, exporting: 0, uploading: 0),
            remainingBytes: 0,
            nextBatch: LedgerNextBatchSummary(photoCount: 0, videoCount: 0, totalBytes: 0)
        ),
        telemetry: UploadProgressTelemetrySnapshot(
            activeUploadedBytes: 0,
            activeTotalBytes: 0,
            bytesPerSecond: nil,
            estimatedSecondsRemaining: nil
        ),
        scannedAssetCount: nil
    )
}
```

- [ ] **Step 2: Add failing dashboard default test**

Append this test to `SyncStatusViewModelTests`.

```swift
func testDashboardRuntimeSnapshotStartsEmpty() {
    let viewModel = SyncStatusViewModel(settingsStore: settingsStore)

    XCTAssertEqual(viewModel.dashboardRuntimeSnapshot, .empty)
}
```

- [ ] **Step 3: Run test to verify it fails**

Run:

```bash
cd ios/iphone
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/SyncStatusViewModelTests/testDashboardRuntimeSnapshotStartsEmpty
```

Expected: FAIL because `dashboardRuntimeSnapshot` does not exist.

- [ ] **Step 4: Add tracker and published runtime snapshot**

In `SyncStatusViewModel`, add:

```swift
@Published private(set) var dashboardRuntimeSnapshot: SyncDashboardRuntimeSnapshot = .empty
private let uploadProgressTracker = UploadProgressTracker()
private var latestScannedAssetCount: Int?
```

When creating `SystemUploadEngine`, pass:

```swift
let engine = SystemUploadEngine(apiClient: apiClient, progressTracker: uploadProgressTracker)
```

After `let counts = try await ledger.getLedgerCounts()` in `refreshCounts()`, add:

```swift
let dashboardSummary = try await ledger.getDashboardSummary(nextBatchLimit: 50)
let telemetry = await uploadProgressTracker.snapshot(remainingBytes: dashboardSummary.remainingBytes)
dashboardRuntimeSnapshot = SyncDashboardRuntimeSnapshot(
    ledgerSummary: dashboardSummary,
    telemetry: telemetry,
    scannedAssetCount: latestScannedAssetCount
)
```

- [ ] **Step 5: Reset telemetry when a sync session starts**

At the start of `syncNow()`, before setting `activeStatus = .scanning`, add:

```swift
await uploadProgressTracker.resetSession()
latestScannedAssetCount = nil
```

- [ ] **Step 6: Publish scan count from orchestrator**

Add a lightweight callback to `SystemSyncOrchestrator`.

```swift
private let onScanCompleted: (@Sendable (Int) async -> Void)?
```

Update its initializer with default `nil`.

```swift
onScanCompleted: (@Sendable (Int) async -> Void)? = nil
```

Assign it in the initializer:

```swift
self.onScanCompleted = onScanCompleted
```

After candidates are fetched in `startSync()`, call:

```swift
await onScanCompleted?(candidates.count)
```

When constructing `SystemSyncOrchestrator` in `SyncStatusViewModel.initializeServices()`, pass:

```swift
onScanCompleted: { [weak self] count in
    await MainActor.run {
        self?.latestScannedAssetCount = count
    }
}
```

- [ ] **Step 7: Run sync status tests**

Run:

```bash
cd ios/iphone
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/SyncStatusViewModelTests
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Core/Upload/SyncOrchestrator.swift ios/iphone/NexusRelayIPhone/Features/SyncStatus/SyncStatusViewModel.swift ios/iphone/NexusRelayIPhoneTests/SyncStatus/SyncStatusViewModelTests.swift
git commit -m "feat(ios): publish sync dashboard runtime state"
```

---

### Task 5: Add Library Sync Dashboard Presentation Models

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncDashboardModels.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncViewModel.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/LibrarySync/LibrarySyncViewModelTests.swift`

- [ ] **Step 1: Add pure model tests**

Append these tests to `LibrarySyncViewModelTests`.

```swift
final class LibrarySyncDashboardStateTests: XCTestCase {
    func testDashboardStateFormatsMockupMetrics() {
        let state = LibrarySyncDashboardState(
            progressPercentText: "68%",
            progressLabelText: "Uploaded",
            statusText: "Uploading",
            progressFraction: 0.68,
            etaText: "18 min left",
            speedText: "12 MB/s",
            remainingText: "1.8 GB",
            scannedText: "1,164",
            exportingText: "2",
            uploadingText: "2",
            uploadedText: "842",
            waitingText: "319",
            activeText: "2",
            failedText: "1",
            nextBatchText: "Next batch: 42 photos | 7 videos",
            nextBatchDetailText: "Est. 18 min - 195 MB",
            lastSyncedText: "Last synced: Today, 8:32 AM | Session healthy",
            safeToCloseTitle: "Safe to close app: Yes",
            safeToCloseSubtitle: "Sync will continue in the background",
            canPause: true,
            primaryActionTitle: "Pause Sync"
        )

        XCTAssertEqual(state.statusText, "Uploading")
        XCTAssertEqual(state.nextBatchText, "Next batch: 42 photos | 7 videos")
        XCTAssertTrue(state.canPause)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd ios/iphone
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/LibrarySyncDashboardStateTests
```

Expected: FAIL because `LibrarySyncDashboardState` does not exist.

- [ ] **Step 3: Create dashboard presentation models**

Create `LibrarySyncDashboardModels.swift`.

```swift
import Foundation

struct LibrarySyncDashboardState: Equatable {
    let progressPercentText: String
    let progressLabelText: String
    let statusText: String
    let progressFraction: Double
    let etaText: String
    let speedText: String
    let remainingText: String
    let scannedText: String
    let exportingText: String
    let uploadingText: String
    let uploadedText: String
    let waitingText: String
    let activeText: String
    let failedText: String
    let nextBatchText: String
    let nextBatchDetailText: String
    let lastSyncedText: String
    let safeToCloseTitle: String
    let safeToCloseSubtitle: String
    let canPause: Bool
    let primaryActionTitle: String

    static let empty = LibrarySyncDashboardState(
        progressPercentText: "0%",
        progressLabelText: "Uploaded",
        statusText: "Ready",
        progressFraction: 0,
        etaText: "Estimating",
        speedText: "-- MB/s",
        remainingText: "0 MB",
        scannedText: "0",
        exportingText: "0",
        uploadingText: "0",
        uploadedText: "0",
        waitingText: "0",
        activeText: "0",
        failedText: "0",
        nextBatchText: "Next batch: Nothing waiting",
        nextBatchDetailText: "Est. -- - 0 MB",
        lastSyncedText: "Last synced: Not yet | Session healthy",
        safeToCloseTitle: "Safe to close app: Yes",
        safeToCloseSubtitle: "Sync will continue in the background",
        canPause: false,
        primaryActionTitle: "Start Sync"
    )
}
```

Add formatter helpers in the same file.

```swift
enum LibrarySyncDashboardFormatter {
    static func count(_ value: Int) -> String {
        value.formatted(.number)
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func speed(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond else {
            return "-- MB/s"
        }

        let megabytes = bytesPerSecond / 1_000_000
        return "\(Int(megabytes.rounded())) MB/s"
    }

    static func eta(_ seconds: Double?) -> String {
        guard let seconds else {
            return "Estimating"
        }

        let minutes = max(Int((seconds / 60).rounded()), 1)
        return "\(minutes) min left"
    }
}
```

- [ ] **Step 4: Add dashboard state to view model**

In `LibrarySyncViewModel`, add:

```swift
@Published var dashboard = LibrarySyncDashboardState.empty
```

Subscribe to `dashboardRuntimeSnapshot`.

```swift
svm.$dashboardRuntimeSnapshot
    .sink { [weak self] runtime in self?.refreshDashboard(runtime: runtime) }
    .store(in: &cancellables)
```

Add this method.

```swift
private func refreshDashboard(runtime: SyncDashboardRuntimeSnapshot) {
    let counts = runtime.ledgerSummary.counts
    let total = counts.queued + counts.uploaded + counts.failed + counts.exporting + counts.uploading
    let progressFraction = total > 0 ? Double(counts.uploaded) / Double(total) : 0
    let nextBatch = runtime.ledgerSummary.nextBatch
    let nextBatchText = nextBatch.photoCount == 0 && nextBatch.videoCount == 0
        ? "Next batch: Nothing waiting"
        : "Next batch: \(nextBatch.photoCount) photos | \(nextBatch.videoCount) videos"
    let sessionText = requiresSignInRepair ? "Session needs repair" : "Session healthy"
    let lastSynced = lastSyncDate.map { "Last synced: \($0.formatted(date: .abbreviated, time: .shortened)) | \(sessionText)" }
        ?? "Last synced: Not yet | \(sessionText)"

    dashboard = LibrarySyncDashboardState(
        progressPercentText: "\(Int((progressFraction * 100).rounded()))%",
        progressLabelText: "Uploaded",
        statusText: activeStatus.rawValue,
        progressFraction: progressFraction,
        etaText: LibrarySyncDashboardFormatter.eta(runtime.telemetry.estimatedSecondsRemaining),
        speedText: LibrarySyncDashboardFormatter.speed(runtime.telemetry.bytesPerSecond),
        remainingText: LibrarySyncDashboardFormatter.bytes(runtime.ledgerSummary.remainingBytes),
        scannedText: LibrarySyncDashboardFormatter.count(runtime.scannedAssetCount ?? total),
        exportingText: LibrarySyncDashboardFormatter.count(counts.exporting),
        uploadingText: LibrarySyncDashboardFormatter.count(counts.uploading),
        uploadedText: LibrarySyncDashboardFormatter.count(counts.uploaded),
        waitingText: LibrarySyncDashboardFormatter.count(counts.queued),
        activeText: LibrarySyncDashboardFormatter.count(counts.exporting + counts.uploading),
        failedText: LibrarySyncDashboardFormatter.count(counts.failed),
        nextBatchText: nextBatchText,
        nextBatchDetailText: "Est. \(LibrarySyncDashboardFormatter.eta(runtime.telemetry.estimatedSecondsRemaining).replacingOccurrences(of: " left", with: "")) - \(LibrarySyncDashboardFormatter.bytes(nextBatch.totalBytes))",
        lastSyncedText: lastSynced,
        safeToCloseTitle: requiresSignInRepair ? "Safe to close app: No" : "Safe to close app: Yes",
        safeToCloseSubtitle: requiresSignInRepair ? "Repair sign-in before background sync can continue" : "Sync will continue in the background",
        canPause: activeStatus == .scanning || activeStatus == .exporting || activeStatus == .uploading,
        primaryActionTitle: activeStatus == .scanning || activeStatus == .exporting || activeStatus == .uploading ? "Pause Sync" : "Start Sync"
    )
}
```

- [ ] **Step 5: Remove preview loading from sync actions**

Delete these published properties from `LibrarySyncViewModel`.

```swift
@Published var previewItems: [LibraryPreviewItem] = []
@Published var selectedPreviewItem: LibraryPreviewItem?
```

Delete `loadPreviewItems()` and remove these calls.

```swift
await loadPreviewItems()
```

Keep `PhotoThumbnailProvider`, `LibraryPreviewItem`, and `LibraryPreviewMediaType` only if another screen still consumes them. If only `LibrarySyncView` consumes them, delete those definitions too.

- [ ] **Step 6: Run library sync tests**

Run:

```bash
cd ios/iphone
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/LibrarySync
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncDashboardModels.swift ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncViewModel.swift ios/iphone/NexusRelayIPhoneTests/LibrarySync/LibrarySyncViewModelTests.swift
git commit -m "feat(ios): expose library sync dashboard state"
```

---

### Task 6: Build SwiftUI Dashboard Components

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncDashboardComponents.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncView.swift`

- [ ] **Step 1: Create reusable component file**

Create `LibrarySyncDashboardComponents.swift`.

```swift
import SwiftUI

struct SyncProgressHeroCard: View {
    let dashboard: LibrarySyncDashboardState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(dashboard.progressPercentText)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(NRDesign.ColorToken.primaryText)

                    Text(dashboard.progressLabelText)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(NRDesign.ColorToken.primaryText)
                }

                Spacer()

                Label(dashboard.statusText, systemImage: "icloud.and.arrow.up.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .foregroundStyle(NRDesign.ColorToken.accent)
                    .background(NRDesign.ColorToken.accent.opacity(0.12), in: Capsule())
            }

            ProgressView(value: dashboard.progressFraction)
                .tint(NRDesign.ColorToken.accent)

            HStack(spacing: 0) {
                SyncHeroMetric(icon: "clock", value: dashboard.etaText, label: "Est. remaining")
                Divider().frame(height: 38)
                SyncHeroMetric(icon: "gauge.with.dots.needle.67percent", value: dashboard.speedText, label: "Upload speed")
                Divider().frame(height: 38)
                SyncHeroMetric(icon: "externaldrive", value: dashboard.remainingText, label: "Remaining")
            }
        }
        .padding(18)
        .background(NRDesign.ColorToken.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(NRDesign.ColorToken.hairline, lineWidth: 1)
        )
    }
}

private struct SyncHeroMetric: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(NRDesign.ColorToken.secondaryText)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(NRDesign.ColorToken.primaryText)
            Text(label)
                .font(.caption)
                .foregroundStyle(NRDesign.ColorToken.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}
```

- [ ] **Step 2: Add stage and metric card components**

Append these components to `LibrarySyncDashboardComponents.swift`.

```swift
struct SyncStageCards: View {
    let dashboard: LibrarySyncDashboardState

    var body: some View {
        HStack(spacing: 12) {
            SyncStageCard(icon: "checkmark.circle", title: "Scanned", value: dashboard.scannedText, subtitle: "assets found", tint: .green)
            SyncStageCard(icon: "arrow.up.circle", title: "Exporting", value: dashboard.exportingText, subtitle: "readying files", tint: .orange)
            SyncStageCard(icon: "icloud.and.arrow.up", title: "Uploading", value: dashboard.uploadingText, subtitle: "active transfers", tint: .blue)
        }
    }
}

private struct SyncStageCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(NRDesign.ColorToken.primaryText)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(NRDesign.ColorToken.primaryText)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(NRDesign.ColorToken.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

struct SyncMetricGrid: View {
    let dashboard: LibrarySyncDashboardState

    var body: some View {
        HStack(spacing: 0) {
            SyncMetricCard(title: "Uploaded", value: dashboard.uploadedText, tint: .green)
            SyncMetricCard(title: "Waiting", value: dashboard.waitingText, tint: .blue)
            SyncMetricCard(title: "Active", value: dashboard.activeText, tint: .blue)
            SyncMetricCard(title: "Failed", value: dashboard.failedText, tint: .gray)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(NRDesign.ColorToken.hairline, lineWidth: 1)
        )
    }
}

private struct SyncMetricCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(NRDesign.ColorToken.secondaryText)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(NRDesign.ColorToken.primaryText)
            Capsule()
                .fill(tint)
                .frame(width: 36, height: 3)
                .opacity(0.9)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(NRDesign.ColorToken.surface)
    }
}
```

- [ ] **Step 3: Add queue health and action components**

Append these components.

```swift
struct SyncQueueHealthCard: View {
    let dashboard: LibrarySyncDashboardState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Queue Health")
                .font(.caption.weight(.bold))
                .foregroundStyle(NRDesign.ColorToken.secondaryText)
                .textCase(.uppercase)

            HStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.green, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(dashboard.nextBatchText)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(NRDesign.ColorToken.primaryText)
                    Text(dashboard.nextBatchDetailText)
                        .font(.subheadline)
                        .foregroundStyle(NRDesign.ColorToken.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(NRDesign.ColorToken.secondaryText)
            }

            Text(dashboard.lastSyncedText)
                .font(.subheadline)
                .foregroundStyle(NRDesign.ColorToken.secondaryText)

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Circle().fill(Color.green).frame(width: 10, height: 10)
                    Circle().fill(Color.green).frame(width: 10, height: 10)
                    Circle().fill(Color.green.opacity(0.25)).frame(width: 10, height: 10)
                    Circle().fill(Color.gray.opacity(0.2)).frame(width: 10, height: 10)
                }

                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dashboard.safeToCloseTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(NRDesign.ColorToken.primaryText)
                        Text(dashboard.safeToCloseSubtitle)
                            .font(.caption)
                            .foregroundStyle(NRDesign.ColorToken.secondaryText)
                    }
                } icon: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Color.green)
                }
            }
        }
        .padding(18)
        .background(NRDesign.ColorToken.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(NRDesign.ColorToken.hairline, lineWidth: 1)
        )
    }
}

struct SyncDashboardActionBar: View {
    let dashboard: LibrarySyncDashboardState
    let onPrimaryAction: () -> Void
    let onOpenQueue: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPrimaryAction) {
                Label(dashboard.primaryActionTitle, systemImage: dashboard.canPause ? "pause.circle" : "icloud.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(NRDesign.ColorToken.accent)

            Button(action: onOpenQueue) {
                Label("View Queue", systemImage: "list.bullet")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(NRDesign.ColorToken.accent)
        }
    }
}
```

- [ ] **Step 4: Replace LibrarySyncView body content**

In `LibrarySyncView.swift`, replace the `PhotoMosaicView`, `statusBlock`, and old `actionBlock` usage with:

```swift
SyncProgressHeroCard(dashboard: viewModel.dashboard)
SyncStageCards(dashboard: viewModel.dashboard)
SyncMetricGrid(dashboard: viewModel.dashboard)
SyncQueueHealthCard(dashboard: viewModel.dashboard)
SyncDashboardActionBar(
    dashboard: viewModel.dashboard,
    onPrimaryAction: {
        if viewModel.dashboard.canPause {
            viewModel.pauseSync()
        } else {
            Task { await viewModel.syncNow() }
        }
    },
    onOpenQueue: onOpenQueue
)
supportBlock
```

Remove the `.sheet(item: $viewModel.selectedPreviewItem)` block because this screen no longer displays image previews.

Change the `.task` block to:

```swift
.task {
    viewModel.refreshFromSyncViewModel()
}
```

- [ ] **Step 5: Delete obsolete view code**

Delete these private members from `LibrarySyncView.swift`.

```swift
private var statusBlock: some View
private func statChip(title: String, value: String) -> some View
private var actionBlock: some View
private var primaryActionTitle: String
private struct LibraryPreviewDetailView: View
```

Keep `emptyStateBlock` only if the final dashboard should still show an empty-state before first scan. If kept, show it above the action bar only when all dashboard counts are zero and `activeStatus == .idle`.

- [ ] **Step 6: Build**

Run:

```bash
cd ios/iphone
xcodegen generate --spec project.yml
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncDashboardComponents.swift ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncView.swift
git commit -m "feat(ios): redesign library sync dashboard"
```

---

### Task 7: Full Focused Verification

**Files:**

- Verify only. No source changes expected.

- [ ] **Step 1: Run focused ledger tests**

```bash
cd ios/iphone
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/SQLiteUploadLedgerTests
```

Expected: PASS.

- [ ] **Step 2: Run focused upload tests**

```bash
cd ios/iphone
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/UploadEngineTests -only-testing:NexusRelayIPhoneTests/UploadProgressTrackerTests
```

Expected: PASS.

- [ ] **Step 3: Run focused sync UI model tests**

```bash
cd ios/iphone
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/SyncStatusViewModelTests -only-testing:NexusRelayIPhoneTests/LibrarySync
```

Expected: PASS.

- [ ] **Step 4: Run full iOS build**

```bash
cd ios/iphone
xcodegen generate --spec project.yml
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Manual QA on simulator or device**

Open the iOS app and verify:

- Library Sync no longer displays photo thumbnails or image preview sheet.
- Empty/no-ledger state displays a useful dashboard with zeros and a primary Start Sync action.
- Active upload state displays Uploading pill, non-zero active counts, and Pause Sync.
- Failed item state displays failed count and does not claim full health if sign-in repair is required.
- View Queue button navigates to the existing Queue tab.
- Refresh button still calls reconciliation.
- Text remains readable on iPhone 16 size and does not clip in Dynamic Type accessibility sizes.

- [ ] **Step 6: Final commit if verification changes were needed**

If verification required only test or UI polishing fixes, commit them:

```bash
git add ios/iphone/NexusRelayIPhone ios/iphone/NexusRelayIPhoneTests
git commit -m "test(ios): verify sync dashboard redesign"
```

If no files changed during verification, do not create an empty commit.

---

## Risk Notes

- ETA and speed should show `Estimating` / `-- MB/s` until enough progress samples exist. Do not invent values.
- `Safe to close app: Yes` is a product claim. Keep the implementation conservative: show `No` when auth/session repair is required, and consider copy like `Background recovery enabled` if physical-device testing shows background continuation is not guaranteed.
- The current tracker speed sample uses a simple latest-delta calculation. If UI flickers, replace it with a rolling window in `UploadProgressTracker` before shipping.
- `nextUploadBatch(limit:)` currently includes failed records with `attempt_count < 3`. If product wants `Next batch` to exclude failed records, add a separate SQL query with `status IN ('discovered', 'readyToUpload')` instead of reusing `nextUploadBatch(limit:)`.
- Byte formatting uses `ByteCountFormatter` and may render `1.8 GB` or `1.8 GB` depending locale. Tests should assert stable formatter behavior only where needed.

## Backend Plan

No backend changes are planned for this UI/UX phase. The backend remains responsible for auth, upload, Google Drive streaming, and Pixel delivery. The iOS Sync screen remains responsible for presenting the local iPhone upload queue and runtime telemetry.

## Self-Review

- Spec coverage: The plan covers all visible mockup elements and explicitly removes image display from the Sync page.
- Placeholder scan: The plan contains no unresolved placeholders, no deferred requirements, and no ambiguous implementation slots.
- Type consistency: New names are consistently `LedgerDashboardSummary`, `LedgerNextBatchSummary`, `UploadProgressTracker`, `UploadProgressTelemetrySnapshot`, `SyncDashboardRuntimeSnapshot`, and `LibrarySyncDashboardState`.
- Scope check: The plan is intentionally iOS-only and does not modify backend or Android.
