# iOS Sync Upload Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the iOS app sync experience so upload state is clear, upload throughput improves safely, progress is smooth and real, realtime updates are consistent, and UI styling is centralized.

**Architecture:** Introduce a single upload session state layer that receives progress events from the sync pipeline and exposes throttled SwiftUI snapshots. Keep the current backend API contract, but refactor iOS upload internals to support bounded concurrency, byte-level progress, smoother rendering, and a richer Sync dashboard.

**Tech Stack:** Swift 5.10, SwiftUI, Combine/Observation-compatible `ObservableObject`, PhotoKit, URLSession, SQLite3, XCTest, XcodeGen.

---

## Scope

This plan is primarily iOS under `ios/iphone/NexusRelayIPhone`. Backend and Pixel behavior should remain compatible. A small cross-repo upload contract alignment is in scope: web and iOS must send chunked uploads to the backend using 16MB chunks, while backend-to-Google-Drive resumable upload chunks must use 32MB.

## Current Architecture Summary

- `Features/AppShell/AppShellView.swift` creates one `SyncStatusViewModel` and passes it to Sync and Queue tabs.
- `Features/SyncStatus/SyncStatusViewModel.swift` builds services, owns sync UI state, polls ledger every 0.5s during sync, and exposes separate count properties.
- `Core/Upload/SyncOrchestrator.swift` scans Photos, upserts records into SQLite, then exports and uploads each item sequentially.
- `Core/Upload/UploadEngine.swift` currently has two client-side routes: `<= 90MB` uses `/api/upload/stream`, and `> 90MB` uses chunked upload. The web app has a richer routing model: `<= 5MB` multipart stream, `> 5MB && <= 90MB` resumable stream, and `> 90MB` chunked. iOS still benefits from the backend's internal `5MB` split when it calls `/api/upload/stream`, but iOS does not model that split for UI, scheduling, telemetry, or concurrency yet.
- Current client-to-backend chunk size is inconsistent with the target contract: web chunked worker uses 30MB, and iOS chunked upload uses 30MB. The target contract is 16MB for browser/iOS-to-backend chunked upload, and 32MB for backend-to-Google-Drive resumable upload.
- `Core/API/HTTPClient.swift` uses `URLSession.upload(for:fromFile:)`, which does not expose progress callbacks.
- `Features/LibrarySync/LibrarySyncViewModel.swift` computes overall progress as `uploaded / total`.
- `Features/Queue/UploadQueueModels.swift` maps item progress to fixed state values like `0.18`, `0.32`, and `0.72`.
- `Core/Design/NRDesignSystem.swift` has a small static token set and is missing tokens already referenced by Pixel Delivery UI.

## File Structure

Create:

- `ios/iphone/NexusRelayIPhone/Core/Upload/UploadProgressEvent.swift`
  - Defines sync stages, per-record progress events, upload telemetry, and event reporter protocol.
- `ios/iphone/NexusRelayIPhone/Core/Upload/UploadProgressThrottler.swift`
  - Coalesces high-frequency upload bytes into UI-safe updates.
- `ios/iphone/NexusRelayIPhone/Core/Upload/UploadRoutingPolicy.swift`
  - Mirrors web upload routing thresholds: multipart stream up to 5MB, resumable stream up to 90MB, and 16MB client chunked upload above 90MB.
- `ios/iphone/NexusRelayIPhone/Features/SyncStatus/UploadSessionSnapshot.swift`
  - Immutable view model data consumed by Sync and Queue UI.
- `ios/iphone/NexusRelayIPhone/Features/SyncStatus/UploadSessionStore.swift`
  - MainActor single source of truth for sync counts, active item, throughput, ETA, queue preview, and errors.
- `ios/iphone/NexusRelayIPhone/Features/SyncStatus/SmoothProgressModel.swift`
  - Small model that separates real progress from displayed progress.
- `ios/iphone/NexusRelayIPhone/Features/LibrarySync/SyncDashboardComponents.swift`
  - Focused SwiftUI components for metric cards, active file card, queue preview, and recent activity.
- `ios/iphone/NexusRelayIPhoneTests/SyncStatus/UploadSessionStoreTests.swift`
  - Tests snapshot reduction, throughput, throttling boundaries, and queue preview refresh behavior.
- `ios/iphone/NexusRelayIPhoneTests/SyncStatus/SmoothProgressModelTests.swift`
  - Tests progress clamping and monotonic displayed progress rules.

Modify:

- `ios/iphone/NexusRelayIPhone/Core/Upload/AssetExporter.swift`
  - Add optional progress reporter support without breaking tests.
- `ios/iphone/NexusRelayIPhone/Core/Upload/PhotoKitAssetExporter.swift`
  - Use `PHAssetResourceRequestOptions.progressHandler`.
- `ios/iphone/NexusRelayIPhone/Core/API/HTTPClient.swift`
  - Add progress-capable upload method.
- `ios/iphone/NexusRelayIPhone/Core/API/NexusRelayAPIClient.swift`
  - Pass progress reporter through stream and chunk upload methods.
- `ios/iphone/NexusRelayIPhone/Core/Upload/UploadEngine.swift`
  - Route uploads through multipart stream, resumable stream, or chunked mode; emit bytes progress and use safer chunk building.
- `ios/iphone/NexusRelayIPhone/Core/Upload/ChunkFileBuilder.swift`
  - Replace full chunk memory read with buffered copy.
- `ios/iphone/NexusRelayIPhone/Core/Upload/UploadPolicy.swift`
  - Add web-compatible routing thresholds, record concurrency, progress throttle interval, and chunk copy buffer size.
- `../nexus-relay/frontend/lib/workers/upload.worker.ts`
  - Change browser-to-backend chunk size from 30MB to 16MB.
- `../nexus-relay/frontend/lib/workers/upload-routing.ts`
  - Add/export the client chunk size constant so routing tests document the 16MB contract.
- `../nexus-relay/frontend/lib/workers/upload-routing.test.ts`
  - Assert web client chunked upload uses 16MB.
- `../nexus-relay/backend/src/NexusRelay.Backend.Application/Configuration/DirectUploadOptions.cs`
  - Change backend-to-Google-Drive direct/resumable chunk size to 32MB.
- `../nexus-relay/backend/src/NexusRelay.Backend.Infrastructure/Configuration/GoogleDriveOptions.cs`
  - Change default backend-to-Google-Drive resumable chunk size to 32MB for non-direct relay paths.
- `ios/iphone/NexusRelayIPhone/Core/Upload/SyncOrchestrator.swift`
  - Emit sync lifecycle events and process uploads with bounded concurrency.
- `ios/iphone/NexusRelayIPhone/Core/Ledger/UploadLedger.swift`
  - Add dashboard aggregate APIs.
- `ios/iphone/NexusRelayIPhone/Core/Ledger/SQLiteUploadLedger.swift`
  - Add aggregate queries and indexes.
- `ios/iphone/NexusRelayIPhone/Features/SyncStatus/SyncStatusViewModel.swift`
  - Convert to facade over `UploadSessionStore` or remove direct polling responsibilities.
- `ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncViewModel.swift`
  - Consume `UploadSessionStore.snapshot`.
- `ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncView.swift`
  - Replace current sparse layout with the dashboard components.
- `ios/iphone/NexusRelayIPhone/Features/Queue/UploadQueueViewModel.swift`
  - Load queue through shared store or shared ledger snapshot APIs.
- `ios/iphone/NexusRelayIPhone/Features/Queue/UploadQueueView.swift`
  - Remove four independent count subscriptions; subscribe to one snapshot.
- `ios/iphone/NexusRelayIPhone/Core/Design/NRDesignSystem.swift`
  - Expand color, spacing, typography, and reusable surface modifiers.
- `ios/iphone/NexusRelayIPhone/Features/FolderPicker/FolderPickerView.swift`
  - Replace hard-coded colors.
- `ios/iphone/NexusRelayIPhone/Features/PixelDelivery/PixelDeliveryView.swift`
  - Use the centralized `divider` token that will be added.
- `ios/iphone/project.yml`
  - Add every created Swift source/test file because Xcode project is generated by XcodeGen.

Verification commands:

```bash
cd ios/iphone
xcodegen generate --spec project.yml
xcodebuild test -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 15'
```

If running from Windows without Xcode, perform static checks only and mark device/simulator verification as requiring macOS.

---

## Phase 1: Clean Sync Page UI and Add Useful Information

### Task 1: Add Shared Sync Snapshot Models

**Files:**
- Create: `ios/iphone/NexusRelayIPhone/Features/SyncStatus/UploadSessionSnapshot.swift`
- Modify: `ios/iphone/project.yml`
- Test: `ios/iphone/NexusRelayIPhoneTests/SyncStatus/UploadSessionStoreTests.swift`

- [ ] **Step 1: Write snapshot model tests**

Add tests that prove derived text and byte formatting are stable:

```swift
import XCTest
@testable import NexusRelayIPhone

final class UploadSessionSnapshotTests: XCTestCase {
    func testSnapshotComputesOverallProgressFromCounts() {
        let counts = UploadSessionCounts(
            pending: 25,
            exporting: 1,
            uploading: 2,
            completed: 72,
            failed: 0
        )
        let snapshot = UploadSessionSnapshot(
            phase: .uploading,
            counts: counts,
            byteSummary: UploadByteSummary(
                pendingBytes: 50_000_000,
                uploadedBytesThisSession: 25_000_000,
                totalBytesThisSession: 100_000_000
            ),
            activeItem: nil,
            queuePreview: [],
            recentActivity: [],
            lastSyncDate: nil,
            lastErrorMessage: nil,
            isRepairSignInRequired: false
        )

        XCTAssertEqual(snapshot.overallCountProgress, 0.72, accuracy: 0.0001)
        XCTAssertEqual(snapshot.statusTitle, "Uploading")
        XCTAssertTrue(snapshot.summaryText.contains("25 pending"))
    }

    func testByteProgressIsNilWhenTotalIsUnknown() {
        let summary = UploadByteSummary(
            pendingBytes: nil,
            uploadedBytesThisSession: 10,
            totalBytesThisSession: nil
        )

        XCTAssertNil(summary.progressFraction)
    }
}
```

- [ ] **Step 2: Run the focused test and confirm it fails**

Run:

```bash
cd ios/iphone
xcodebuild test -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:NexusRelayIPhoneTests/UploadSessionSnapshotTests
```

Expected: fail because `UploadSessionSnapshot`, `UploadSessionCounts`, and `UploadByteSummary` do not exist.

- [ ] **Step 3: Create the snapshot models**

Create `UploadSessionSnapshot.swift`:

```swift
import Foundation

enum UploadSessionPhase: Equatable {
    case idle
    case scanning
    case exporting
    case uploading
    case pausing
    case error

    var title: String {
        switch self {
        case .idle: return "Ready"
        case .scanning: return "Scanning"
        case .exporting: return "Exporting"
        case .uploading: return "Uploading"
        case .pausing: return "Pausing"
        case .error: return "Needs Attention"
        }
    }
}

struct UploadSessionCounts: Equatable {
    let pending: Int
    let exporting: Int
    let uploading: Int
    let completed: Int
    let failed: Int

    var active: Int { exporting + uploading }
    var total: Int { pending + active + completed + failed }
}

struct UploadByteSummary: Equatable {
    let pendingBytes: Int64?
    let uploadedBytesThisSession: Int64
    let totalBytesThisSession: Int64?

    var progressFraction: Double? {
        guard let totalBytesThisSession, totalBytesThisSession > 0 else { return nil }
        return min(max(Double(uploadedBytesThisSession) / Double(totalBytesThisSession), 0), 1)
    }
}

struct UploadActiveItemSnapshot: Equatable, Identifiable {
    let id: String
    let filename: String
    let stageText: String
    let bytesSent: Int64
    let totalBytes: Int64?
    let speedBytesPerSecond: Double?
    let estimatedSecondsRemaining: TimeInterval?

    var progressFraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(max(Double(bytesSent) / Double(totalBytes), 0), 1)
    }
}

struct UploadActivityItem: Equatable, Identifiable {
    let id: String
    let filename: String
    let detail: String
    let date: Date
    let kind: UploadActivityKind
}

enum UploadActivityKind: Equatable {
    case uploaded
    case failed
    case retried
}

struct UploadSessionSnapshot: Equatable {
    let phase: UploadSessionPhase
    let counts: UploadSessionCounts
    let byteSummary: UploadByteSummary
    let activeItem: UploadActiveItemSnapshot?
    let queuePreview: [UploadQueueItem]
    let recentActivity: [UploadActivityItem]
    let lastSyncDate: Date?
    let lastErrorMessage: String?
    let isRepairSignInRequired: Bool

    static let empty = UploadSessionSnapshot(
        phase: .idle,
        counts: UploadSessionCounts(pending: 0, exporting: 0, uploading: 0, completed: 0, failed: 0),
        byteSummary: UploadByteSummary(pendingBytes: nil, uploadedBytesThisSession: 0, totalBytesThisSession: nil),
        activeItem: nil,
        queuePreview: [],
        recentActivity: [],
        lastSyncDate: nil,
        lastErrorMessage: nil,
        isRepairSignInRequired: false
    )

    var statusTitle: String { phase.title }

    var overallCountProgress: Double {
        guard counts.total > 0 else { return 0 }
        return min(max(Double(counts.completed) / Double(counts.total), 0), 1)
    }

    var summaryText: String {
        "\(counts.completed) completed | \(counts.pending) pending | \(counts.failed) failed"
    }
}
```

- [ ] **Step 4: Add files to XcodeGen**

In `ios/iphone/project.yml`, ensure created app/test files are under the existing target source globs or add explicit file paths if this project uses explicit includes.

- [ ] **Step 5: Run tests again**

Run:

```bash
cd ios/iphone
xcodegen generate --spec project.yml
xcodebuild test -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:NexusRelayIPhoneTests/UploadSessionSnapshotTests
```

Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Features/SyncStatus/UploadSessionSnapshot.swift ios/iphone/NexusRelayIPhoneTests/SyncStatus/UploadSessionStoreTests.swift ios/iphone/project.yml
git commit -m "feat: add upload session snapshot models"
```

### Task 2: Build Sync Dashboard Components

**Files:**
- Create: `ios/iphone/NexusRelayIPhone/Features/LibrarySync/SyncDashboardComponents.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncView.swift`
- Modify: `ios/iphone/project.yml`

- [ ] **Step 1: Create dashboard components**

Create focused SwiftUI pieces:

```swift
import SwiftUI

struct SyncDashboardHeader: View {
    let snapshot: UploadSessionSnapshot
    let onReconcile: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Library Sync")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(NRDesign.ColorToken.primaryText)
                Text(snapshot.statusTitle)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(NRDesign.ColorToken.secondaryText)
            }

            Spacer(minLength: 12)

            Button(action: onReconcile) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(NRDesign.ColorToken.accent)
            .background(NRDesign.ColorToken.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityLabel("Rebuild upload history")
        }
    }
}

struct SyncHeroCard: View {
    let snapshot: UploadSessionSnapshot
    let displayedProgress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.statusTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(NRDesign.ColorToken.primaryText)
                Spacer()
                Text("\(Int((displayedProgress * 100).rounded()))%")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(NRDesign.ColorToken.primaryText)
            }

            ProgressView(value: displayedProgress)
                .tint(NRDesign.ColorToken.accent)

            Text(snapshot.summaryText)
                .font(.footnote)
                .foregroundStyle(NRDesign.ColorToken.secondaryText)

            if let activeItem = snapshot.activeItem {
                ActiveUploadCard(item: activeItem)
            }
        }
        .nrCard()
    }
}

struct SyncMetricGrid: View {
    let counts: UploadSessionCounts

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            SyncMetricCard(title: "Pending", value: "\(counts.pending)", color: NRDesign.ColorToken.warning)
            SyncMetricCard(title: "Active", value: "\(counts.active)", color: NRDesign.ColorToken.accent)
            SyncMetricCard(title: "Completed", value: "\(counts.completed)", color: NRDesign.ColorToken.success)
            SyncMetricCard(title: "Failed", value: "\(counts.failed)", color: NRDesign.ColorToken.error)
        }
    }
}

struct SyncMetricCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(NRDesign.ColorToken.secondaryText)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(NRDesign.ColorToken.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: NRDesign.Radius.row, style: .continuous))
    }
}

struct ActiveUploadCard: View {
    let item: UploadActiveItemSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.filename)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NRDesign.ColorToken.primaryText)
                .lineLimit(1)
            Text(item.stageText)
                .font(.caption)
                .foregroundStyle(NRDesign.ColorToken.secondaryText)
            if let fraction = item.progressFraction {
                ProgressView(value: fraction)
                    .tint(NRDesign.ColorToken.accent)
            } else {
                ProgressView()
                    .tint(NRDesign.ColorToken.accent)
            }
        }
        .padding(12)
        .background(NRDesign.ColorToken.surfaceMuted, in: RoundedRectangle(cornerRadius: NRDesign.Radius.row, style: .continuous))
    }
}

struct QueuePreviewPanel: View {
    let items: [UploadQueueItem]
    let onOpenQueue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Queue Preview")
                    .font(.headline)
                    .foregroundStyle(NRDesign.ColorToken.primaryText)
                Spacer()
                Button("View All", action: onOpenQueue)
                    .font(.footnote.weight(.semibold))
            }

            if items.isEmpty {
                Text("New uploads appear here after scanning.")
                    .font(.footnote)
                    .foregroundStyle(NRDesign.ColorToken.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(items.prefix(6)) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.resourceKind == .video ? "video" : "photo")
                            .foregroundStyle(NRDesign.ColorToken.secondaryText)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.filename)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(item.statusText)
                                .font(.caption)
                                .foregroundStyle(NRDesign.ColorToken.secondaryText)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .nrCard()
    }
}
```

- [ ] **Step 2: Update `LibrarySyncView` layout**

Replace the central content with:

```swift
VStack(alignment: .leading, spacing: 14) {
    SyncDashboardHeader(
        snapshot: viewModel.snapshot,
        onReconcile: { Task { await viewModel.reconcile() } }
    )
    SyncHeroCard(
        snapshot: viewModel.snapshot,
        displayedProgress: viewModel.displayedOverallProgress
    )
    SyncMetricGrid(counts: viewModel.snapshot.counts)
    QueuePreviewPanel(
        items: viewModel.snapshot.queuePreview,
        onOpenQueue: onOpenQueue
    )
    actionBlock
    supportBlock
}
```

Keep `PhotoMosaicView` available only as a secondary preview below queue preview or remove it from the first viewport. The sync dashboard should prioritize actual queue state.

- [ ] **Step 3: Run build**

Run:

```bash
cd ios/iphone
xcodegen generate --spec project.yml
xcodebuild build -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 15'
```

Expected: build succeeds after view model fields are added in later tasks. If this task is executed before store tasks, commit components only and wire them after Task 5.

- [ ] **Step 4: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Features/LibrarySync/SyncDashboardComponents.swift ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncView.swift ios/iphone/project.yml
git commit -m "feat: add sync dashboard components"
```

---

## Phase 2: Refactor Sync and Upload State Management

### Task 3: Add Upload Progress Events

**Files:**
- Create: `ios/iphone/NexusRelayIPhone/Core/Upload/UploadProgressEvent.swift`
- Modify: `ios/iphone/project.yml`
- Test: `ios/iphone/NexusRelayIPhoneTests/SyncStatus/UploadSessionStoreTests.swift`

- [ ] **Step 1: Define event contract**

Create:

```swift
import Foundation

enum UploadPipelineStage: String, Equatable {
    case scanning = "Scanning"
    case exporting = "Exporting"
    case ready = "Ready"
    case uploading = "Uploading"
    case completing = "Completing"
    case completed = "Completed"
    case failed = "Failed"
}

struct UploadProgressPayload: Equatable {
    let recordId: String
    let filename: String
    let stage: UploadPipelineStage
    let bytesCompleted: Int64
    let totalBytes: Int64?
    let date: Date
}

enum UploadProgressEvent: Equatable {
    case syncStarted(date: Date)
    case scanCompleted(discoveredCount: Int, date: Date)
    case recordStarted(recordId: String, filename: String, totalBytes: Int64?, date: Date)
    case recordProgress(UploadProgressPayload)
    case recordCompleted(recordId: String, filename: String, bytes: Int64?, date: Date)
    case recordFailed(recordId: String, filename: String, message: String, date: Date)
    case syncCompleted(uploadedCount: Int, date: Date)
    case syncFailed(message: String, requiresSignInRepair: Bool, date: Date)
    case syncPaused(date: Date)
}

protocol UploadProgressReporting: Sendable {
    func report(_ event: UploadProgressEvent) async
}

struct NoopUploadProgressReporter: UploadProgressReporting {
    func report(_ event: UploadProgressEvent) async {}
}
```

- [ ] **Step 2: Add a test reducer expectation**

Add a test that feeds `.recordProgress` into the store once Task 4 exists:

```swift
@MainActor
func testProgressEventUpdatesActiveItem() async {
    let store = UploadSessionStore(ledger: FakeDashboardLedger())
    await store.handle(.recordStarted(recordId: "1", filename: "IMG_1.HEIC", totalBytes: 100, date: Date()))
    await store.handle(.recordProgress(UploadProgressPayload(recordId: "1", filename: "IMG_1.HEIC", stage: .uploading, bytesCompleted: 40, totalBytes: 100, date: Date())))

    XCTAssertEqual(store.snapshot.activeItem?.id, "1")
    XCTAssertEqual(store.snapshot.activeItem?.progressFraction, 0.4, accuracy: 0.0001)
}
```

- [ ] **Step 3: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Core/Upload/UploadProgressEvent.swift ios/iphone/NexusRelayIPhoneTests/SyncStatus/UploadSessionStoreTests.swift ios/iphone/project.yml
git commit -m "feat: add upload progress event contract"
```

### Task 4: Add Ledger Dashboard Snapshot APIs

**Files:**
- Modify: `ios/iphone/NexusRelayIPhone/Core/Ledger/UploadLedger.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Core/Ledger/SQLiteUploadLedger.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/Ledger/SQLiteUploadLedgerTests.swift`

- [ ] **Step 1: Write ledger aggregate test**

Add:

```swift
func testDashboardSnapshotReturnsCountsBytesAndPreview() async throws {
    let folderId = UUID()
    let candidates = [
        makeCandidate(id: "asset-1", fileName: "IMG_1.HEIC", size: 1_000),
        makeCandidate(id: "asset-2", fileName: "IMG_2.HEIC", size: 2_000)
    ]
    try await ledger.upsertDiscovered(candidates, folderId: folderId)

    let snapshot = try await ledger.getDashboardSnapshot(previewLimit: 5)

    XCTAssertEqual(snapshot.counts.queued, 2)
    XCTAssertEqual(snapshot.pendingBytes, 3_000)
    XCTAssertEqual(snapshot.queuePreview.count, 2)
}
```

Use the existing candidate helper style in `SQLiteUploadLedgerTests.swift`; if no helper exists, add a local helper in the test file:

```swift
private func makeCandidate(id: String, fileName: String, size: Int64) -> PhotoAssetCandidate {
    PhotoAssetCandidate(
        assetLocalIdentifier: id,
        resourceKind: .image,
        originalFilename: fileName,
        uniformTypeIdentifier: "public.heic",
        mimeType: "image/heic",
        creationDate: Date(),
        modificationDate: nil,
        pixelWidth: 100,
        pixelHeight: 100,
        durationSeconds: nil,
        resourceFileSize: size
    )
}
```

- [ ] **Step 2: Add protocol models**

Add to `UploadLedger.swift`:

```swift
struct UploadLedgerDashboardSnapshot: Equatable {
    let counts: LedgerCounts
    let pendingBytes: Int64?
    let activeBytes: Int64?
    let completedBytes: Int64?
    let failedBytes: Int64?
    let queuePreview: [UploadLedgerRecord]
    let recentUploaded: [UploadLedgerRecord]
    let recentFailed: [UploadLedgerRecord]
}
```

Add to `UploadLedger`:

```swift
func getDashboardSnapshot(previewLimit: Int) async throws -> UploadLedgerDashboardSnapshot
```

- [ ] **Step 3: Implement SQLite aggregate query**

In `SQLiteUploadLedger.swift`, implement:

```swift
func getDashboardSnapshot(previewLimit: Int) async throws -> UploadLedgerDashboardSnapshot {
    lock.lock()
    defer { lock.unlock() }

    let counts = try getLedgerCountsLocked()
    let bytes = try getByteSummaryLocked()
    let preview = try queryRecords(
        sql: """
        SELECT id, asset_local_identifier, resource_kind, fingerprint_suffix,
               original_filename, uploaded_file_name, mime_type, size_bytes,
               status, backend_folder_id, backend_upload_id, local_staged_file_url,
               attempt_count, last_attempt_at, last_error
        FROM upload_ledger
        WHERE status IN ('discovered', 'exporting', 'readyToUpload', 'uploading', 'failed')
        ORDER BY
          CASE status
            WHEN 'uploading' THEN 0
            WHEN 'exporting' THEN 1
            WHEN 'failed' THEN 2
            WHEN 'readyToUpload' THEN 3
            ELSE 4
          END,
          last_attempt_at DESC,
          id ASC
        LIMIT ?;
        """,
        params: [previewLimit]
    )

    let recentUploaded = try queryRecentLocked(statuses: ["uploaded", "synced"], limit: 5)
    let recentFailed = try queryRecentLocked(statuses: ["failed"], limit: 5)

    return UploadLedgerDashboardSnapshot(
        counts: counts,
        pendingBytes: bytes.pending,
        activeBytes: bytes.active,
        completedBytes: bytes.completed,
        failedBytes: bytes.failed,
        queuePreview: preview,
        recentUploaded: recentUploaded,
        recentFailed: recentFailed
    )
}
```

Refactor current `getLedgerCounts()` so it calls a private `getLedgerCountsLocked()` after taking the lock. Do not call a public async locked method from inside another locked method.

- [ ] **Step 4: Add indexes**

In `createTables()`, after table creation, add:

```sql
CREATE INDEX IF NOT EXISTS idx_upload_ledger_status_attempt ON upload_ledger(status, attempt_count, last_attempt_at);
CREATE INDEX IF NOT EXISTS idx_upload_ledger_status_recent ON upload_ledger(status, last_attempt_at DESC, id ASC);
```

- [ ] **Step 5: Run ledger tests**

Run:

```bash
cd ios/iphone
xcodebuild test -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:NexusRelayIPhoneTests/SQLiteUploadLedgerTests
```

Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Core/Ledger/UploadLedger.swift ios/iphone/NexusRelayIPhone/Core/Ledger/SQLiteUploadLedger.swift ios/iphone/NexusRelayIPhoneTests/Ledger/SQLiteUploadLedgerTests.swift
git commit -m "feat: add upload ledger dashboard snapshot"
```

### Task 5: Add UploadSessionStore

**Files:**
- Create: `ios/iphone/NexusRelayIPhone/Features/SyncStatus/UploadSessionStore.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Features/SyncStatus/SyncStatusViewModel.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/SyncStatus/UploadSessionStoreTests.swift`

- [ ] **Step 1: Write store tests**

Use a fake ledger:

```swift
final class FakeDashboardLedger: UploadLedger {
    var dashboardSnapshot = UploadLedgerDashboardSnapshot(
        counts: LedgerCounts(queued: 3, uploaded: 7, failed: 1, exporting: 0, uploading: 0),
        pendingBytes: 3_000,
        activeBytes: 0,
        completedBytes: 7_000,
        failedBytes: 1_000,
        queuePreview: [],
        recentUploaded: [],
        recentFailed: []
    )

    func getDashboardSnapshot(previewLimit: Int) async throws -> UploadLedgerDashboardSnapshot {
        dashboardSnapshot
    }

    func upsertDiscovered(_ candidates: [PhotoAssetCandidate], folderId: UUID) async throws {}
    func nextUploadBatch(limit: Int) async throws -> [UploadLedgerRecord] { [] }
    func listQueueRecords(filter: UploadQueueFilter, limit: Int) async throws -> [UploadLedgerRecord] { [] }
    func retryFailed(ids: [String]) async throws {}
    func markExporting(id: String) async throws {}
    func markReady(id: String, stagedFileURL: URL, sizeBytes: Int64) async throws {}
    func markUploading(id: String) async throws {}
    func markUploaded(id: String, backendUploadId: UUID) async throws {}
    func markSyncedByUploadedFileNames(_ fileNames: Set<String>, folderId: UUID) async throws {}
    func markFailed(id: String, error: String, retryable: Bool) async throws {}
    func getLedgerCounts() async throws -> LedgerCounts {
        dashboardSnapshot.counts
    }
}
```

Test:

```swift
@MainActor
func testRefreshMapsLedgerDashboardToSnapshot() async {
    let store = UploadSessionStore(ledger: FakeDashboardLedger())

    await store.refreshFromLedger()

    XCTAssertEqual(store.snapshot.counts.pending, 3)
    XCTAssertEqual(store.snapshot.counts.completed, 7)
    XCTAssertEqual(store.snapshot.counts.failed, 1)
    XCTAssertEqual(store.snapshot.byteSummary.pendingBytes, 3_000)
}
```

- [ ] **Step 2: Implement store**

Create:

```swift
import Foundation

@MainActor
final class UploadSessionStore: ObservableObject, UploadProgressReporting {
    @Published private(set) var snapshot: UploadSessionSnapshot = .empty

    private let ledger: UploadLedger?
    private var sessionStartedAt: Date?
    private var lastByteSample: (date: Date, bytes: Int64)?

    init(ledger: UploadLedger? = nil) {
        self.ledger = ledger
    }

    func refreshFromLedger() async {
        guard let ledger else { return }
        do {
            let dashboard = try await ledger.getDashboardSnapshot(previewLimit: 6)
            let counts = UploadSessionCounts(
                pending: dashboard.counts.queued,
                exporting: dashboard.counts.exporting,
                uploading: dashboard.counts.uploading,
                completed: dashboard.counts.uploaded,
                failed: dashboard.counts.failed
            )
            snapshot = UploadSessionSnapshot(
                phase: inferredPhase(from: counts, current: snapshot.phase),
                counts: counts,
                byteSummary: UploadByteSummary(
                    pendingBytes: dashboard.pendingBytes,
                    uploadedBytesThisSession: snapshot.byteSummary.uploadedBytesThisSession,
                    totalBytesThisSession: snapshot.byteSummary.totalBytesThisSession
                ),
                activeItem: snapshot.activeItem,
                queuePreview: dashboard.queuePreview.map(UploadQueueItem.init(record:)),
                recentActivity: makeRecentActivity(uploaded: dashboard.recentUploaded, failed: dashboard.recentFailed),
                lastSyncDate: snapshot.lastSyncDate,
                lastErrorMessage: snapshot.lastErrorMessage,
                isRepairSignInRequired: snapshot.isRepairSignInRequired
            )
        } catch {
            snapshot = snapshot.withError(message: error.localizedDescription, requiresRepair: false)
        }
    }

    func report(_ event: UploadProgressEvent) async {
        await handle(event)
    }

    func handle(_ event: UploadProgressEvent) async {
        switch event {
        case .syncStarted(let date):
            sessionStartedAt = date
            snapshot = snapshot.withPhase(.scanning).clearingError()
        case .scanCompleted:
            snapshot = snapshot.withPhase(.exporting)
            await refreshFromLedger()
        case .recordStarted(let recordId, let filename, let totalBytes, let date):
            lastByteSample = (date, 0)
            snapshot = snapshot.withActiveItem(
                UploadActiveItemSnapshot(
                    id: recordId,
                    filename: filename,
                    stageText: UploadPipelineStage.exporting.rawValue,
                    bytesSent: 0,
                    totalBytes: totalBytes,
                    speedBytesPerSecond: nil,
                    estimatedSecondsRemaining: nil
                )
            )
        case .recordProgress(let payload):
            snapshot = snapshot.withActiveItem(makeActiveItem(from: payload))
        case .recordCompleted(_, let filename, let bytes, let date):
            let uploaded = snapshot.byteSummary.uploadedBytesThisSession + (bytes ?? 0)
            snapshot = snapshot
                .withByteProgress(uploadedBytes: uploaded)
                .withRecentActivity(UploadActivityItem(id: UUID().uuidString, filename: filename, detail: "Uploaded", date: date, kind: .uploaded))
            await refreshFromLedger()
        case .recordFailed(_, let filename, let message, let date):
            snapshot = snapshot
                .withError(message: message, requiresRepair: false)
                .withRecentActivity(UploadActivityItem(id: UUID().uuidString, filename: filename, detail: message, date: date, kind: .failed))
            await refreshFromLedger()
        case .syncCompleted(_, let date):
            snapshot = snapshot.withPhase(.idle).withLastSyncDate(date).withActiveItem(nil)
            await refreshFromLedger()
        case .syncFailed(let message, let requiresSignInRepair, _):
            snapshot = snapshot.withPhase(.error).withError(message: message, requiresRepair: requiresSignInRepair)
        case .syncPaused:
            snapshot = snapshot.withPhase(.idle).withActiveItem(nil)
            await refreshFromLedger()
        }
    }
}
```

Add private immutable helper methods in the same file:

```swift
private extension UploadSessionStore {
    func inferredPhase(from counts: UploadSessionCounts, current: UploadSessionPhase) -> UploadSessionPhase {
        if current == .error || current == .pausing { return current }
        if counts.uploading > 0 { return .uploading }
        if counts.exporting > 0 { return .exporting }
        return current == .scanning ? .scanning : .idle
    }

    func makeActiveItem(from payload: UploadProgressPayload) -> UploadActiveItemSnapshot {
        let speed = speedBytesPerSecond(date: payload.date, bytes: payload.bytesCompleted)
        let remaining: TimeInterval?
        if let total = payload.totalBytes, let speed, speed > 1 {
            remaining = TimeInterval(max(total - payload.bytesCompleted, 0)) / speed
        } else {
            remaining = nil
        }
        lastByteSample = (payload.date, payload.bytesCompleted)
        return UploadActiveItemSnapshot(
            id: payload.recordId,
            filename: payload.filename,
            stageText: payload.stage.rawValue,
            bytesSent: payload.bytesCompleted,
            totalBytes: payload.totalBytes,
            speedBytesPerSecond: speed,
            estimatedSecondsRemaining: remaining
        )
    }

    func speedBytesPerSecond(date: Date, bytes: Int64) -> Double? {
        guard let lastByteSample else { return nil }
        let elapsed = date.timeIntervalSince(lastByteSample.date)
        guard elapsed > 0.2 else { return nil }
        return Double(max(bytes - lastByteSample.bytes, 0)) / elapsed
    }

    func makeRecentActivity(uploaded: [UploadLedgerRecord], failed: [UploadLedgerRecord]) -> [UploadActivityItem] {
        let uploadedItems = uploaded.map {
            UploadActivityItem(id: "uploaded-\($0.id)", filename: $0.originalFilename, detail: "Uploaded", date: $0.lastAttemptAt ?? Date(), kind: .uploaded)
        }
        let failedItems = failed.map {
            UploadActivityItem(id: "failed-\($0.id)", filename: $0.originalFilename, detail: $0.lastError ?? "Failed", date: $0.lastAttemptAt ?? Date(), kind: .failed)
        }
        return (uploadedItems + failedItems).sorted { $0.date > $1.date }.prefix(5).map { $0 }
    }
}
```

Add `UploadSessionSnapshot` copy helpers:

```swift
extension UploadSessionSnapshot {
    func withPhase(_ phase: UploadSessionPhase) -> UploadSessionSnapshot {
        UploadSessionSnapshot(phase: phase, counts: counts, byteSummary: byteSummary, activeItem: activeItem, queuePreview: queuePreview, recentActivity: recentActivity, lastSyncDate: lastSyncDate, lastErrorMessage: lastErrorMessage, isRepairSignInRequired: isRepairSignInRequired)
    }

    func withActiveItem(_ item: UploadActiveItemSnapshot?) -> UploadSessionSnapshot {
        UploadSessionSnapshot(phase: phase, counts: counts, byteSummary: byteSummary, activeItem: item, queuePreview: queuePreview, recentActivity: recentActivity, lastSyncDate: lastSyncDate, lastErrorMessage: lastErrorMessage, isRepairSignInRequired: isRepairSignInRequired)
    }

    func withError(message: String, requiresRepair: Bool) -> UploadSessionSnapshot {
        UploadSessionSnapshot(phase: phase, counts: counts, byteSummary: byteSummary, activeItem: activeItem, queuePreview: queuePreview, recentActivity: recentActivity, lastSyncDate: lastSyncDate, lastErrorMessage: message, isRepairSignInRequired: requiresRepair)
    }

    func clearingError() -> UploadSessionSnapshot {
        UploadSessionSnapshot(phase: phase, counts: counts, byteSummary: byteSummary, activeItem: activeItem, queuePreview: queuePreview, recentActivity: recentActivity, lastSyncDate: lastSyncDate, lastErrorMessage: nil, isRepairSignInRequired: false)
    }

    func withLastSyncDate(_ date: Date) -> UploadSessionSnapshot {
        UploadSessionSnapshot(phase: phase, counts: counts, byteSummary: byteSummary, activeItem: activeItem, queuePreview: queuePreview, recentActivity: recentActivity, lastSyncDate: date, lastErrorMessage: lastErrorMessage, isRepairSignInRequired: isRepairSignInRequired)
    }

    func withByteProgress(uploadedBytes: Int64) -> UploadSessionSnapshot {
        UploadSessionSnapshot(phase: phase, counts: counts, byteSummary: UploadByteSummary(pendingBytes: byteSummary.pendingBytes, uploadedBytesThisSession: uploadedBytes, totalBytesThisSession: byteSummary.totalBytesThisSession), activeItem: activeItem, queuePreview: queuePreview, recentActivity: recentActivity, lastSyncDate: lastSyncDate, lastErrorMessage: lastErrorMessage, isRepairSignInRequired: isRepairSignInRequired)
    }

    func withRecentActivity(_ item: UploadActivityItem) -> UploadSessionSnapshot {
        var next = [item] + recentActivity.filter { $0.id != item.id }
        next = Array(next.prefix(5))
        return UploadSessionSnapshot(phase: phase, counts: counts, byteSummary: byteSummary, activeItem: activeItem, queuePreview: queuePreview, recentActivity: next, lastSyncDate: lastSyncDate, lastErrorMessage: lastErrorMessage, isRepairSignInRequired: isRepairSignInRequired)
    }
}
```

- [ ] **Step 3: Run store tests**

Run:

```bash
cd ios/iphone
xcodebuild test -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:NexusRelayIPhoneTests/UploadSessionStoreTests
```

Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Features/SyncStatus/UploadSessionStore.swift ios/iphone/NexusRelayIPhoneTests/SyncStatus/UploadSessionStoreTests.swift ios/iphone/project.yml
git commit -m "feat: add upload session store"
```

---

## Phase 3: Optimize Upload Performance

### Task 6: Add Web-Compatible Upload Routing Policy

**Files:**
- Create: `ios/iphone/NexusRelayIPhone/Core/Upload/UploadRoutingPolicy.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Core/Upload/UploadPolicy.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Core/Upload/UploadEngine.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Features/Queue/UploadQueueModels.swift`
- Modify: `ios/iphone/project.yml`
- Test: `ios/iphone/NexusRelayIPhoneTests/Upload/UploadRoutingPolicyTests.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/Upload/UploadEngineTests.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/Queue/UploadQueueViewModelTests.swift`

- [ ] **Step 1: Write routing tests that mirror web thresholds**

Create `UploadRoutingPolicyTests.swift`:

```swift
import XCTest
@testable import NexusRelayIPhone

final class UploadRoutingPolicyTests: XCTestCase {
    func testRoutesFilesUpToFiveMegabytesThroughMultipartStream() {
        let policy = UploadPolicy.nexusRelayDefault

        XCTAssertEqual(policy.route(forFileSize: 5 * 1024 * 1024), .multipartStream)
    }

    func testRoutesFilesAboveFiveAndUpToNinetyMegabytesThroughResumableStream() {
        let policy = UploadPolicy.nexusRelayDefault

        XCTAssertEqual(policy.route(forFileSize: (5 * 1024 * 1024) + 1), .resumableStream)
        XCTAssertEqual(policy.route(forFileSize: 90 * 1024 * 1024), .resumableStream)
    }

    func testRoutesFilesAboveNinetyMegabytesThroughChunkedUpload() {
        let policy = UploadPolicy.nexusRelayDefault

        XCTAssertEqual(policy.route(forFileSize: (90 * 1024 * 1024) + 1), .chunked)
    }

    func testClientChunkedUploadUsesSixteenMegabyteChunks() {
        XCTAssertEqual(UploadPolicy.nexusRelayDefault.chunkSizeBytes, 16 * 1024 * 1024)
    }
}
```

- [ ] **Step 2: Run the routing tests and confirm they fail**

Run:

```bash
cd ios/iphone
xcodebuild test -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:NexusRelayIPhoneTests/UploadRoutingPolicyTests
```

Expected: fail because `UploadRoutingPolicy` and the new `UploadPolicy` fields do not exist.

- [ ] **Step 3: Create upload routing types**

Create `UploadRoutingPolicy.swift`:

```swift
import Foundation

enum UploadRoute: String, Equatable {
    case multipartStream
    case resumableStream
    case chunked

    var displayName: String {
        switch self {
        case .multipartStream:
            return "Direct multipart upload"
        case .resumableStream:
            return "Direct resumable upload"
        case .chunked:
            return "Chunked upload"
        }
    }

    var usesStreamEndpoint: Bool {
        switch self {
        case .multipartStream, .resumableStream:
            return true
        case .chunked:
            return false
        }
    }
}
```

- [ ] **Step 4: Update `UploadPolicy` to match web and backend thresholds**

Replace the current policy fields with this expanded shape:

```swift
struct UploadPolicy: Equatable {
    let multipartStreamMaxBytes: Int64
    let directStreamMaxBytes: Int64
    let chunkSizeBytes: Int64
    let maxRetries: Int
    let foregroundChunkConcurrency: Int
    let backgroundChunkConcurrency: Int
    let recordUploadConcurrency: Int
    let progressThrottleMilliseconds: Int
    let chunkCopyBufferSize: Int

    static let nexusRelayDefault = UploadPolicy(
        multipartStreamMaxBytes: 5 * 1024 * 1024,
        directStreamMaxBytes: 90 * 1024 * 1024,
        chunkSizeBytes: 16 * 1024 * 1024,
        maxRetries: 3,
        foregroundChunkConcurrency: 2,
        backgroundChunkConcurrency: 1,
        recordUploadConcurrency: 2,
        progressThrottleMilliseconds: 300,
        chunkCopyBufferSize: 1024 * 1024
    )

    func route(forFileSize fileSize: Int64) -> UploadRoute {
        if fileSize > directStreamMaxBytes {
            return .chunked
        }

        return fileSize <= multipartStreamMaxBytes ? .multipartStream : .resumableStream
    }

    var streamThresholdBytes: Int64 {
        directStreamMaxBytes
    }
}
```

Keep `streamThresholdBytes` as a compatibility computed property so existing UI/tests that check direct-vs-chunked behavior keep compiling during the refactor.

- [ ] **Step 5: Update `UploadEngine` to use route names**

At the start of `upload(record:folderId:)`:

```swift
let fileSize = record.sizeBytes ?? 0
let route = policy.route(forFileSize: fileSize)

switch route {
case .multipartStream, .resumableStream:
    return try await retry {
        let response = try await apiClient.streamUpload(
            fileURL: localURL,
            fileName: record.uploadedFileName,
            folderId: folderId,
            mimeType: record.mimeType,
            fileSize: fileSize
        )
        return response.uploadId
    }
case .chunked:
    return try await uploadChunked(record: record, folderId: folderId, localURL: localURL, fileSize: fileSize)
}
```

Extract the existing chunked branch into:

```swift
private func uploadChunked(record: UploadLedgerRecord, folderId: UUID, localURL: URL, fileSize: Int64) async throws -> UUID {
    let chunkSize = policy.chunkSizeBytes
    let totalChunks = Int(ceil(Double(fileSize) / Double(chunkSize)))

    defer {
        chunkFileBuilder.cleanChunks(recordId: record.id)
    }

    let initResponse = try await retry {
        try await apiClient.initUpload(
            folderId: folderId,
            fileName: record.uploadedFileName,
            totalSize: fileSize,
            totalChunks: totalChunks
        )
    }
    let uploadId = initResponse.uploadId

    for chunkIndex in 0..<totalChunks {
        let chunkURL = try chunkFileBuilder.buildChunkFile(
            recordId: record.id,
            sourceURL: localURL,
            chunkIndex: chunkIndex,
            chunkSize: chunkSize,
            totalSize: fileSize
        )

        defer {
            if chunkURL.standardizedFileURL != localURL.standardizedFileURL {
                try? FileManager.default.removeItem(at: chunkURL)
            }
        }

        let actualChunkSize = try getFileSize(at: chunkURL)

        try await retry {
            try await apiClient.uploadChunk(
                uploadId: uploadId,
                chunkIndex: chunkIndex,
                chunkSize: actualChunkSize,
                chunkFileURL: chunkURL
            )
        }
    }

    try await retry {
        try await apiClient.completeUpload(uploadId: uploadId, fileHash: nil)
    }

    return uploadId
}
```

- [ ] **Step 6: Update queue upload mode text**

In `UploadQueueModels.swift`, replace `uploadModeText` with:

```swift
var uploadModeText: String {
    guard let sizeBytes else { return "Determined during upload" }
    return UploadPolicy.nexusRelayDefault.route(forFileSize: sizeBytes).displayName
}
```

- [ ] **Step 7: Update tests that construct `UploadPolicy`**

Where tests currently create:

```swift
UploadPolicy(
    streamThresholdBytes: 100,
    chunkSizeBytes: 50,
    maxRetries: 3,
    foregroundChunkConcurrency: 1,
    backgroundChunkConcurrency: 1
)
```

replace with:

```swift
UploadPolicy(
    multipartStreamMaxBytes: 50,
    directStreamMaxBytes: 100,
    chunkSizeBytes: 50,
    maxRetries: 3,
    foregroundChunkConcurrency: 1,
    backgroundChunkConcurrency: 1,
    recordUploadConcurrency: 1,
    progressThrottleMilliseconds: 300,
    chunkCopyBufferSize: 64 * 1024
)
```

- [ ] **Step 8: Run routing and upload tests**

Run:

```bash
cd ios/iphone
xcodegen generate --spec project.yml
xcodebuild test -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:NexusRelayIPhoneTests/UploadRoutingPolicyTests -only-testing:NexusRelayIPhoneTests/UploadEngineTests -only-testing:NexusRelayIPhoneTests/UploadQueueViewModelTests
```

Expected: pass.

- [ ] **Step 9: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Core/Upload/UploadRoutingPolicy.swift ios/iphone/NexusRelayIPhone/Core/Upload/UploadPolicy.swift ios/iphone/NexusRelayIPhone/Core/Upload/UploadEngine.swift ios/iphone/NexusRelayIPhone/Features/Queue/UploadQueueModels.swift ios/iphone/NexusRelayIPhoneTests/Upload/UploadRoutingPolicyTests.swift ios/iphone/NexusRelayIPhoneTests/Upload/UploadEngineTests.swift ios/iphone/NexusRelayIPhoneTests/Queue/UploadQueueViewModelTests.swift ios/iphone/project.yml
git commit -m "feat: align ios upload routing with web thresholds"
```

### Task 7: Align Client and Backend Chunk Sizes

**Files:**
- Modify: `../nexus-relay/frontend/lib/workers/upload.worker.ts`
- Modify: `../nexus-relay/frontend/lib/workers/upload-routing.ts`
- Modify: `../nexus-relay/frontend/lib/workers/upload-routing.test.ts`
- Modify: `../nexus-relay/backend/src/NexusRelay.Backend.Application/Configuration/DirectUploadOptions.cs`
- Modify: `../nexus-relay/backend/src/NexusRelay.Backend.Infrastructure/Configuration/GoogleDriveOptions.cs`
- Modify: backend upload tests that assert Drive resumable chunk size, especially `../nexus-relay/backend/tests/NexusRelay.Backend.Application.Tests/Features/Uploads/Commands/StreamTests.cs`

- [ ] **Step 1: Update web upload routing tests for client chunk size**

In `frontend/lib/workers/upload-routing.test.ts`, add:

```ts
import {
  BACKEND_DRIVE_UPLOAD_CHUNK_BYTES,
  CLIENT_CHUNK_UPLOAD_BYTES,
  DIRECT_UPLOAD_MAX_BYTES,
  MULTIPART_UPLOAD_MAX_BYTES,
  RESUMABLE_UPLOAD_CHUNK_BYTES,
  getDirectUploadMode,
  shouldUseChunkedUpload,
} from './upload-routing';

test('keeps browser to backend chunked upload size at 16MB', () => {
  assert.equal(CLIENT_CHUNK_UPLOAD_BYTES, 16 * 1024 * 1024);
});

test('documents backend to Google Drive resumable upload chunk size at 32MB', () => {
  assert.equal(BACKEND_DRIVE_UPLOAD_CHUNK_BYTES, 32 * 1024 * 1024);
  assert.equal(RESUMABLE_UPLOAD_CHUNK_BYTES, BACKEND_DRIVE_UPLOAD_CHUNK_BYTES);
});
```

Replace the existing `RESUMABLE_UPLOAD_CHUNK_BYTES == 16MB` assertion with the 32MB assertion above. The direct/resumable stream path is backend-to-Google-Drive, not browser-to-backend chunking.

- [ ] **Step 2: Export the 16MB web client chunk constant**

In `frontend/lib/workers/upload-routing.ts`, add:

```ts
export const CLIENT_CHUNK_UPLOAD_BYTES = 16 * MB;
export const BACKEND_DRIVE_UPLOAD_CHUNK_BYTES = 32 * MB;
```

Change:

```ts
export const RESUMABLE_UPLOAD_CHUNK_BYTES = 16 * MB;
```

to:

```ts
export const RESUMABLE_UPLOAD_CHUNK_BYTES = BACKEND_DRIVE_UPLOAD_CHUNK_BYTES;
```

Keep the old export name for compatibility with existing imports, but its value must now be 32MB.

- [ ] **Step 3: Use the exported constant in the upload worker**

In `frontend/lib/workers/upload.worker.ts`, replace:

```ts
const CHUNK_SIZE = 30 * 1024 * 1024; // 30MB per chunk
```

with:

```ts
import { CLIENT_CHUNK_UPLOAD_BYTES, shouldUseChunkedUpload } from './upload-routing';

const CHUNK_SIZE = CLIENT_CHUNK_UPLOAD_BYTES;
```

Remove the old `shouldUseChunkedUpload` import if it becomes duplicated.

- [ ] **Step 4: Update backend direct/resumable Drive chunk config to 32MB**

In `backend/src/NexusRelay.Backend.Application/Configuration/DirectUploadOptions.cs`, change:

```csharp
public int ResumableChunkSizeBytes { get; init; } = 16 * 1024 * 1024;
```

to:

```csharp
public int ResumableChunkSizeBytes { get; init; } = 32 * 1024 * 1024;
```

This affects `/upload/stream` files larger than 5MB that the backend uploads to Google Drive with Drive resumable upload.

- [ ] **Step 5: Update backend default Google Drive chunk config to 32MB**

In `backend/src/NexusRelay.Backend.Infrastructure/Configuration/GoogleDriveOptions.cs`, change:

```csharp
public int UploadChunkSizeBytes { get; init; } = Google.Apis.Upload.ResumableUpload.MinimumChunkSize * 256;
```

to:

```csharp
public int UploadChunkSizeBytes { get; init; } = 32 * 1024 * 1024;
```

This affects backend relay/post-processing paths that do not pass an explicit chunk size to `GoogleDriveService`.

- [ ] **Step 6: Update backend test expectations**

In backend tests that expect `chunkSizeBytes: 16 * 1024 * 1024`, update expected Drive API chunk size to:

```csharp
chunkSizeBytes: 32 * 1024 * 1024
```

Keep client-to-backend chunk tests at `16 * 1024 * 1024`.

- [ ] **Step 7: Run web upload routing tests**

Run from `G:\workspace\nexus-relay`:

```bash
npm test -- upload-routing
```

If the repo uses a different script, run the existing frontend test command that currently executes `frontend/lib/workers/upload-routing.test.ts`.

Expected: upload routing tests pass and assert `CLIENT_CHUNK_UPLOAD_BYTES == 16MB`.

- [ ] **Step 8: Run backend upload tests**

Run from `G:\workspace\nexus-relay`:

```bash
dotnet test backend/tests/NexusRelay.Backend.Application.Tests/NexusRelay.Backend.Application.Tests.csproj --filter "FullyQualifiedName~Uploads"
```

Expected: upload command tests pass with 32MB backend-to-Drive chunk expectations.

- [ ] **Step 9: Commit cross-repo config alignment**

In `G:\workspace\nexus-relay`:

```bash
git add frontend/lib/workers/upload.worker.ts frontend/lib/workers/upload-routing.ts frontend/lib/workers/upload-routing.test.ts backend/src/NexusRelay.Backend.Application/Configuration/DirectUploadOptions.cs backend/src/NexusRelay.Backend.Infrastructure/Configuration/GoogleDriveOptions.cs backend/tests
git commit -m "chore: align upload chunk sizes"
```

In `G:\workspace\nexus-relay-mobile`, Task 6 already commits the iOS side.

### Task 8: Add Progress-Capable HTTP Uploads

**Files:**
- Modify: `ios/iphone/NexusRelayIPhone/Core/API/HTTPClient.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Core/API/NexusRelayAPIClient.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/API/NexusRelayAPIClientTests.swift`

- [ ] **Step 1: Extend HTTP protocol without breaking existing callers**

Add:

```swift
struct HTTPUploadProgress: Equatable {
    let bytesSent: Int64
    let totalBytes: Int64?
}

typealias HTTPUploadProgressHandler = @Sendable (HTTPUploadProgress) async -> Void
```

Change protocol:

```swift
func uploadFile(_ request: HTTPRequest, fileURL: URL, progress: HTTPUploadProgressHandler?) async throws -> HTTPResponse
```

Keep existing method as extension:

```swift
extension HTTPClient {
    func uploadFile(_ request: HTTPRequest, fileURL: URL) async throws -> HTTPResponse {
        try await uploadFile(request, fileURL: fileURL, progress: nil)
    }
}
```

- [ ] **Step 2: Implement delegate-backed uploader**

Use a small per-upload delegate object:

```swift
final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let progress: HTTPUploadProgressHandler?

    init(progress: HTTPUploadProgressHandler?) {
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard let progress else { return }
        let total = totalBytesExpectedToSend > 0 ? totalBytesExpectedToSend : nil
        Task {
            await progress(HTTPUploadProgress(bytesSent: totalBytesSent, totalBytes: total))
        }
    }
}
```

In `SystemHTTPClient.uploadFile`, use `urlSession.upload(for:fromFile:delegate:)` on iOS 15+:

```swift
let delegate = UploadProgressDelegate(progress: progress)
let (data, urlResponse) = try await urlSession.upload(for: urlRequest, fromFile: fileURL, delegate: delegate)
```

- [ ] **Step 3: Add API progress plumbing**

Add overloads to `NexusRelayAPI`:

```swift
func streamUpload(fileURL: URL, fileName: String, folderId: UUID, mimeType: String, fileSize: Int64, progress: HTTPUploadProgressHandler?) async throws -> StreamUploadResponse
func uploadChunk(uploadId: UUID, chunkIndex: Int, chunkSize: Int64, chunkFileURL: URL, progress: HTTPUploadProgressHandler?) async throws
```

Keep default protocol extension wrappers for existing tests and callers.

- [ ] **Step 4: Run API tests**

Run:

```bash
cd ios/iphone
xcodebuild test -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:NexusRelayIPhoneTests/NexusRelayAPIClientTests
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Core/API/HTTPClient.swift ios/iphone/NexusRelayIPhone/Core/API/NexusRelayAPIClient.swift ios/iphone/NexusRelayIPhoneTests/API/NexusRelayAPIClientTests.swift
git commit -m "feat: report upload progress from http client"
```

### Task 9: Make Chunk Building Memory-Safe

**Files:**
- Modify: `ios/iphone/NexusRelayIPhone/Core/Upload/ChunkFileBuilder.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Core/Upload/UploadPolicy.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/Upload/ChunkFileBuilderTests.swift`

- [ ] **Step 1: Write buffered chunk test**

Add a test that creates a multi-megabyte temp file and verifies chunk size/content:

```swift
func testBuildChunkFileCopiesRequestedRange() throws {
    let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let bytes = Data((0..<1024 * 1024).map { UInt8($0 % 251) })
    try bytes.write(to: source)
    defer { try? FileManager.default.removeItem(at: source) }

    let builder = SystemChunkFileBuilder(copyBufferSize: 64 * 1024)
    let chunk = try builder.buildChunkFile(recordId: "record:1", sourceURL: source, chunkIndex: 1, chunkSize: 256 * 1024, totalSize: Int64(bytes.count))
    defer { builder.cleanChunks(recordId: "record:1") }

    let chunkData = try Data(contentsOf: chunk)
    XCTAssertEqual(chunkData.count, 256 * 1024)
    XCTAssertEqual(chunkData.first, bytes[256 * 1024])
}
```

- [ ] **Step 2: Add buffer size policy**

In `UploadPolicy`, these fields already exist after Task 6:

```swift
let chunkCopyBufferSize: Int
```

Default value:

```swift
chunkCopyBufferSize: 1024 * 1024
```

- [ ] **Step 3: Replace full chunk read**

Implement `SystemChunkFileBuilder` initializer:

```swift
init(copyBufferSize: Int = UploadPolicy.nexusRelayDefault.chunkCopyBufferSize) {
    self.copyBufferSize = copyBufferSize
    self.tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("com.nexusrelay.iphone.chunks", isDirectory: true)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
}
```

Replace `read(upToCount: Int(targetLength))` with a loop:

```swift
let input = try FileHandle(forReadingFrom: sourceURL)
defer { try? input.close() }
try input.seek(toOffset: UInt64(offset))

FileManager.default.createFile(atPath: chunkURL.path, contents: nil)
let output = try FileHandle(forWritingTo: chunkURL)
defer { try? output.close() }

var remaining = targetLength
while remaining > 0 {
    let readSize = min(copyBufferSize, Int(remaining))
    let data = try input.read(upToCount: readSize) ?? Data()
    if data.isEmpty { break }
    try output.write(contentsOf: data)
    remaining -= Int64(data.count)
}
```

- [ ] **Step 4: Run chunk tests**

```bash
cd ios/iphone
xcodebuild test -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:NexusRelayIPhoneTests/ChunkFileBuilderTests
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Core/Upload/ChunkFileBuilder.swift ios/iphone/NexusRelayIPhone/Core/Upload/UploadPolicy.swift ios/iphone/NexusRelayIPhoneTests/Upload/ChunkFileBuilderTests.swift
git commit -m "perf: buffer chunk file creation"
```

### Task 10: Add Bounded Record Upload Concurrency

**Files:**
- Modify: `ios/iphone/NexusRelayIPhone/Core/Upload/SyncOrchestrator.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Core/Upload/UploadEngine.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/Upload/SyncOrchestratorTests.swift`

- [ ] **Step 1: Write concurrency test**

Add:

```swift
func testSyncUsesBoundedUploadConcurrency() async throws {
    orchestrator = SystemSyncOrchestrator(
        apiClient: api,
        photosScanner: scanner,
        ledger: ledger,
        exporter: exporter,
        tempFileStore: tempStore,
        uploadEngine: engine,
        settingsStore: settingsStore,
        wifiChecker: { true },
        progressReporter: NoopUploadProgressReporter(),
        policy: UploadPolicy(
            multipartStreamMaxBytes: 50,
            directStreamMaxBytes: 100,
            chunkSizeBytes: 50,
            maxRetries: 1,
            foregroundChunkConcurrency: 1,
            backgroundChunkConcurrency: 1,
            recordUploadConcurrency: 2,
            progressThrottleMilliseconds: 300,
            chunkCopyBufferSize: 64 * 1024
        )
    )

    settingsStore.settings.destinationFolderId = UUID()
    engine.delayNanoseconds = 200_000_000
    scanner.candidates = (0..<4).map { index in
        PhotoAssetCandidate(
            assetLocalIdentifier: "asset-\(index)",
            resourceKind: .image,
            originalFilename: "IMG_\(index).HEIC",
            uniformTypeIdentifier: "public.heic",
            mimeType: "image/heic",
            creationDate: Date(),
            modificationDate: nil,
            pixelWidth: 100,
            pixelHeight: 100,
            durationSeconds: nil,
            resourceFileSize: 500
        )
    }

    let start = Date()
    let uploaded = try await orchestrator.startSync()
    let elapsed = Date().timeIntervalSince(start)

    XCTAssertEqual(uploaded, 4)
    XCTAssertLessThan(elapsed, 0.75)
}
```

- [ ] **Step 2: Add orchestrator dependencies**

Extend initializer with defaults:

```swift
progressReporter: UploadProgressReporting = NoopUploadProgressReporter(),
policy: UploadPolicy = .nexusRelayDefault
```

- [ ] **Step 3: Process each batch with task group**

Replace sequential `for record in pendingBatch` with a bounded group:

```swift
let concurrency = max(policy.recordUploadConcurrency, 1)
var iterator = pendingBatch.makeIterator()

try await withThrowingTaskGroup(of: Bool.self) { group in
    for _ in 0..<concurrency {
        guard let record = iterator.next() else { break }
        group.addTask { [self] in
            try await processRecord(record, folderId: folderId, settings: settings)
            return true
        }
    }

    while let _ = try await group.next() {
        uploadedCount += 1
        if isCancellationRequested() { continue }
        if let next = iterator.next() {
            group.addTask { [self] in
                try await processRecord(next, folderId: folderId, settings: settings)
                return true
            }
        }
    }
}
```

Make `processRecord` catch per-record errors internally and return `Bool` for success. Keep cancellation behavior: stop adding new work after pause, allow active uploads to finish.

- [ ] **Step 4: Emit progress events**

Inside record processing:

```swift
await progressReporter.report(.recordStarted(recordId: record.id, filename: record.originalFilename, totalBytes: record.sizeBytes, date: Date()))
await progressReporter.report(.recordProgress(UploadProgressPayload(recordId: record.id, filename: record.originalFilename, stage: .exporting, bytesCompleted: 0, totalBytes: record.sizeBytes, date: Date())))
```

Pass a progress closure into `uploadEngine.upload` so it can emit `.recordProgress` with `.uploading`.

- [ ] **Step 5: Run orchestrator tests**

```bash
cd ios/iphone
xcodebuild test -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:NexusRelayIPhoneTests/SyncOrchestratorTests
```

Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Core/Upload/SyncOrchestrator.swift ios/iphone/NexusRelayIPhone/Core/Upload/UploadEngine.swift ios/iphone/NexusRelayIPhoneTests/Upload/SyncOrchestratorTests.swift
git commit -m "perf: add bounded upload concurrency"
```

---

## Phase 4: Smooth Progress Bar and Realtime Update

### Task 11: Smooth Displayed Progress

**Files:**
- Create: `ios/iphone/NexusRelayIPhone/Features/SyncStatus/SmoothProgressModel.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncViewModel.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/SyncStatus/SmoothProgressModelTests.swift`

- [ ] **Step 1: Write smoothing tests**

```swift
import XCTest
@testable import NexusRelayIPhone

final class SmoothProgressModelTests: XCTestCase {
    func testProgressClampsBetweenZeroAndOne() {
        var model = SmoothProgressModel()
        model.updateTarget(-1)
        XCTAssertEqual(model.targetProgress, 0)
        model.updateTarget(2)
        XCTAssertEqual(model.targetProgress, 1)
    }

    func testDisplayedProgressDoesNotJumpBackwardDuringActiveUpload() {
        var model = SmoothProgressModel()
        model.updateTarget(0.7)
        model.displayedProgress = 0.6
        model.updateTarget(0.5, allowBackward: false)
        XCTAssertEqual(model.targetProgress, 0.7)
    }
}
```

- [ ] **Step 2: Implement model**

```swift
import Foundation

struct SmoothProgressModel: Equatable {
    private(set) var targetProgress: Double = 0
    var displayedProgress: Double = 0

    mutating func updateTarget(_ value: Double, allowBackward: Bool = true) {
        let clamped = min(max(value, 0), 1)
        if !allowBackward && clamped < targetProgress {
            return
        }
        targetProgress = clamped
    }
}
```

- [ ] **Step 3: Use in `LibrarySyncViewModel`**

Add:

```swift
@Published var snapshot: UploadSessionSnapshot = .empty
@Published var displayedOverallProgress: Double = 0
private var smoothProgress = SmoothProgressModel()
```

When snapshot changes:

```swift
let realProgress = snapshot.byteSummary.progressFraction ?? snapshot.overallCountProgress
smoothProgress.updateTarget(realProgress, allowBackward: snapshot.phase == .idle || snapshot.phase == .error)
displayedOverallProgress = smoothProgress.targetProgress
```

Use SwiftUI animation at render site:

```swift
.animation(.easeOut(duration: 0.25), value: viewModel.displayedOverallProgress)
```

- [ ] **Step 4: Run tests**

```bash
cd ios/iphone
xcodebuild test -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:NexusRelayIPhoneTests/SmoothProgressModelTests
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Features/SyncStatus/SmoothProgressModel.swift ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncViewModel.swift ios/iphone/NexusRelayIPhoneTests/SyncStatus/SmoothProgressModelTests.swift ios/iphone/project.yml
git commit -m "feat: smooth sync progress display"
```

### Task 12: Replace Multi-Property Polling with Snapshot Updates

**Files:**
- Modify: `ios/iphone/NexusRelayIPhone/Features/SyncStatus/SyncStatusViewModel.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncViewModel.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Features/Queue/UploadQueueView.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Features/Queue/UploadQueueViewModel.swift`

- [ ] **Step 1: Update SyncStatusViewModel facade**

Keep compatibility properties during transition:

```swift
@Published var sessionSnapshot: UploadSessionSnapshot = .empty
private let sessionStore: UploadSessionStore
private var cancellables = Set<AnyCancellable>()
```

Subscribe once:

```swift
sessionStore.$snapshot
    .receive(on: DispatchQueue.main)
    .sink { [weak self] snapshot in
        self?.sessionSnapshot = snapshot
        self?.queuedCount = snapshot.counts.pending
        self?.uploadedCount = snapshot.counts.completed
        self?.failedCount = snapshot.counts.failed
        self?.exportingCount = snapshot.counts.exporting
        self?.uploadingCount = snapshot.counts.uploading
        self?.lastSyncDate = snapshot.lastSyncDate
        self?.errorMessage = snapshot.lastErrorMessage
        self?.requiresSignInRepair = snapshot.isRepairSignInRequired
    }
    .store(in: &cancellables)
```

- [ ] **Step 2: Inject store as progress reporter**

When constructing orchestrator:

```swift
self.orchestrator = SystemSyncOrchestrator(
    apiClient: apiClient,
    photosScanner: scanner,
    ledger: ledger,
    exporter: exporter,
    tempFileStore: tempStore,
    uploadEngine: engine,
    settingsStore: settingsStore,
    progressReporter: sessionStore
)
```

- [ ] **Step 3: Reduce polling interval use**

Remove the 0.5s loop after event reporting is wired. Keep a low-frequency safety refresh:

```swift
let safetyRefreshTask = Task {
    while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        await sessionStore.refreshFromLedger()
    }
}
```

Cancel it when sync ends.

- [ ] **Step 4: Update Queue view subscriptions**

Replace four `.onReceive` blocks with one:

```swift
.onReceive(syncStatusViewModel.$sessionSnapshot) { _ in
    Task { await viewModel.load() }
}
```

Then debounce inside `UploadQueueViewModel` by ignoring concurrent loads:

```swift
guard !isLoading else { return }
```

- [ ] **Step 5: Run UI model tests**

```bash
cd ios/iphone
xcodebuild test -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:NexusRelayIPhoneTests/LibrarySyncSummaryTests -only-testing:NexusRelayIPhoneTests/UploadQueueViewModelTests -only-testing:NexusRelayIPhoneTests/SyncStatusViewModelTests
```

Expected: pass after updating expectations from count-only progress to snapshot-driven progress.

- [ ] **Step 6: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Features/SyncStatus/SyncStatusViewModel.swift ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncViewModel.swift ios/iphone/NexusRelayIPhone/Features/Queue/UploadQueueView.swift ios/iphone/NexusRelayIPhone/Features/Queue/UploadQueueViewModel.swift ios/iphone/NexusRelayIPhoneTests
git commit -m "refactor: drive sync ui from upload session snapshot"
```

---

## Phase 5: Centralize Colors, Theme, and Design Tokens

### Task 13: Expand NRDesignSystem

**Files:**
- Modify: `ios/iphone/NexusRelayIPhone/Core/Design/NRDesignSystem.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Features/FolderPicker/FolderPickerView.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Features/PixelDelivery/PixelDeliveryView.swift`

- [ ] **Step 1: Add missing and semantic tokens**

Modify `ColorToken`:

```swift
enum ColorToken {
    static let appBackground = Color(red: 0.980, green: 0.980, blue: 0.973)
    static let surface = Color.white
    static let surfaceMuted = Color(red: 0.955, green: 0.960, blue: 0.955)
    static let surfaceElevated = Color(red: 1.000, green: 1.000, blue: 0.995)
    static let primaryText = Color(red: 0.090, green: 0.090, blue: 0.090)
    static let secondaryText = Color(red: 0.420, green: 0.447, blue: 0.502)
    static let hairline = Color(red: 0.902, green: 0.906, blue: 0.890)
    static let divider = hairline
    static let accent = Color(red: 0.039, green: 0.518, blue: 0.647)
    static let accentSoft = accent.opacity(0.12)
    static let success = Color(red: 0.180, green: 0.678, blue: 0.420)
    static let successSoft = success.opacity(0.12)
    static let warning = Color(red: 0.949, green: 0.722, blue: 0.294)
    static let warningSoft = warning.opacity(0.14)
    static let error = Color(red: 0.847, green: 0.290, blue: 0.290)
    static let errorSoft = error.opacity(0.12)
    static let overlayScrim = Color.black.opacity(0.42)
}
```

Add reusable card modifier:

```swift
extension View {
    func nrCard() -> some View {
        padding(14)
            .background(NRDesign.ColorToken.surface, in: RoundedRectangle(cornerRadius: NRDesign.Radius.row, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NRDesign.Radius.row, style: .continuous)
                    .stroke(NRDesign.ColorToken.hairline, lineWidth: 1)
            )
    }
}
```

- [ ] **Step 2: Replace hard-coded folder colors**

In `FolderPickerView.swift`:

```swift
.foregroundStyle(NRDesign.ColorToken.error)
```

and:

```swift
.foregroundStyle(NRDesign.ColorToken.accent)
```

- [ ] **Step 3: Verify PixelDelivery compile**

`PixelDeliveryView.swift` should compile because `NRDesign.ColorToken.divider` now exists.

- [ ] **Step 4: Run build**

```bash
cd ios/iphone
xcodebuild build -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 15'
```

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Core/Design/NRDesignSystem.swift ios/iphone/NexusRelayIPhone/Features/FolderPicker/FolderPickerView.swift ios/iphone/NexusRelayIPhone/Features/PixelDelivery/PixelDeliveryView.swift
git commit -m "style: centralize ios design tokens"
```

---

## Phase 6: Testing, Regression, and Rollout

### Task 14: Full Test Matrix

**Files:**
- Modify tests touched by earlier phases.
- No production code unless tests expose a defect.

- [ ] **Step 1: Run all unit tests**

```bash
cd ios/iphone
xcodegen generate --spec project.yml
xcodebuild test -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 15'
```

Expected: all tests pass.

- [ ] **Step 2: Run upload-specific tests**

```bash
cd ios/iphone
xcodebuild test -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:NexusRelayIPhoneTests/UploadRoutingPolicyTests -only-testing:NexusRelayIPhoneTests/SyncOrchestratorTests -only-testing:NexusRelayIPhoneTests/UploadEngineTests -only-testing:NexusRelayIPhoneTests/ChunkFileBuilderTests -only-testing:NexusRelayIPhoneTests/SQLiteUploadLedgerTests
```

Expected: all tests pass.

- [ ] **Step 3: Manual device test with 50 files**

On real iPhone:

1. Sign in with Google through existing setup.
2. Select destination folder.
3. Enable Wi-Fi only.
4. Start Sync with 50 mixed images.
5. Confirm Sync page shows active filename, stage, counts, speed, and smooth progress.
6. Confirm Queue tab updates without repeated visible reload flicker.
7. Confirm web dashboard receives uploads.
8. Confirm Pixel tab still polls and shows downloaded items.

Expected: no duplicate uploads, no stuck active item, progress moves at least every 0.5s while network upload is active.

- [ ] **Step 4: Manual device test with 500 files**

On same network as previous baseline:

1. Start with clean ledger or known queue.
2. Sync 500 images.
3. Record total elapsed time.
4. Record files/minute and MB/minute from debug logs.
5. Background the app for 5 minutes, then foreground.
6. Confirm ledger counts remain consistent.

Expected: throughput improves versus sequential baseline; background remains best-effort but does not corrupt queue state.

- [ ] **Step 5: Failure regression**

Run these cases:

1. Turn off Wi-Fi while Wi-Fi-only is enabled.
2. Upload a file requiring iCloud network access while network is unavailable.
3. Expire auth session and verify sign-in repair state.
4. Kill app during upload and reopen.
5. Retry failed uploads.

Expected: failures show user-facing errors, failed queue can retry, no duplicate upload records are created.

- [ ] **Step 6: Commit test fixes**

If tests required fixes:

```bash
git add ios/iphone/NexusRelayIPhone ios/iphone/NexusRelayIPhoneTests ios/iphone/project.yml
git commit -m "test: verify ios sync upload refactor"
```

### Task 15: Performance Instrumentation and Rollout Notes

**Files:**
- Modify: `ios/iphone/NexusRelayIPhone/Core/Upload/SyncOrchestrator.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Core/Upload/UploadEngine.swift`
- Create: `docs/ios-sync-upload-refactor-rollout.md`

- [ ] **Step 1: Add lightweight timing logs**

Use `os.Logger`:

```swift
import OSLog

private let logger = Logger(subsystem: "com.nexusrelay.iphone", category: "upload")
```

Log phase boundaries:

```swift
logger.info("sync.scan.completed count=\(candidates.count)")
logger.info("sync.record.completed id=\(record.id, privacy: .public) bytes=\(actualSize)")
logger.error("sync.record.failed id=\(record.id, privacy: .public) error=\(userFacingMessage, privacy: .public)")
```

- [ ] **Step 2: Document rollout**

Create:

```markdown
# iOS Sync Upload Refactor Rollout

## Metrics to Compare

- Files uploaded per minute
- Megabytes uploaded per minute
- Files per minute by upload route: multipart stream, resumable stream, and chunked
- Average export duration
- Average upload duration
- Average upload duration by route
- Retry count
- Peak memory while chunking videos
- UI progress update cadence

## Rollback

If upload concurrency causes backend pressure, set `UploadPolicy.nexusRelayDefault.recordUploadConcurrency` to `1` and rebuild. If progress UI is noisy, increase `progressThrottleMilliseconds` from `300` to `500`.

## Known Limits

iOS background processing remains best-effort. Foreground sync should be treated as the reliable path for large first-time syncs.
```

- [ ] **Step 3: Commit docs and logs**

```bash
git add ios/iphone/NexusRelayIPhone/Core/Upload/SyncOrchestrator.swift ios/iphone/NexusRelayIPhone/Core/Upload/UploadEngine.swift docs/ios-sync-upload-refactor-rollout.md
git commit -m "docs: add ios sync rollout metrics"
```

---

## Additional Findings

- `PixelDeliveryView.swift` references `NRDesign.ColorToken.divider`, but current `NRDesignSystem.swift` does not define it. Task 13 fixes this.
- iOS currently has only two client-side upload routes (`<= 90MB` stream, `> 90MB` chunked). Web has three logical routes (`<= 5MB` multipart stream, `> 5MB && <= 90MB` resumable stream, `> 90MB` chunked). Task 6 adds the same explicit routing model to iOS while keeping the existing backend API.
- `UploadPolicy` already contains chunk concurrency fields, but current `UploadEngine` does not use them. This plan initially prioritizes explicit routing and record-level concurrency because those changes are safer with the existing backend contract.
- `ReconciliationService` scans all local candidates and all remote media pages. Keep this manual action; do not run reconciliation automatically during normal sync.
- `BackgroundSyncScheduler` and `AppDelegate` both contain background task handling patterns. This plan does not consolidate them unless tests show duplicate registration or scheduling issues.

## Self-Review

Spec coverage:

- Sync page UI/UX: Tasks 1, 2, 11, 12, 13.
- Upload slowness: Tasks 6, 7, 8, 9, 10, 15.
- Upload routing parity with web: Task 6.
- Upload chunk size contract: Task 7.
- Loading/progress bar smoothness: Tasks 3, 5, 8, 11, 12.
- Realtime update: Tasks 3, 5, 12.
- Color/design consistency: Task 13.
- iOS architecture: Tasks 3, 4, 5, 6, 10, 12.
- File-level plan: included above in File Structure and each task.
- Risk and verification: Tasks 14, 15 and Additional Findings.

Placeholder scan:

- The plan contains no placeholder markers, no unspecified implementation step, and no code step relies on an undefined type without defining it in an earlier or same task.

Type consistency:

- `UploadSessionSnapshot`, `UploadProgressEvent`, `UploadSessionStore`, and ledger snapshot names are used consistently across tasks.
- Existing names such as `UploadLedgerRecord`, `UploadQueueItem`, `UploadPolicy`, `SystemSyncOrchestrator`, and `SystemHTTPClient` match the current codebase.
