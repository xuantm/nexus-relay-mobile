# iOS Apple Photos Native UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the native iPhone uploader UI to match the approved Apple Photos Native direction while preserving the existing NexusRelay upload behavior.

**Architecture:** Keep upload/auth/PhotoKit behavior in the existing core services and add a thin presentation layer for UI-specific state. Replace the current dark dashboard with a light native SwiftUI shell: setup checklist, Library Sync home, Upload Queue, and Settings. Extend the ledger with read-only queue queries and manual retry support so the UI can show real rows instead of only aggregate counts.

**Tech Stack:** Swift, SwiftUI, PhotoKit, SQLite, XCTest, XcodeGen, GitHub Actions macOS.

---

## Source References

- Design spec: `docs/superpowers/specs/2026-06-06-ios-apple-photos-native-ui-design.md`
- Mockup: `docs/superpowers/assets/iphone-apple-photos-native-option-a.png`
- iPhone architecture: `docs/architecture/iphone-photos-uploader.md`
- iPhone API contract: `docs/contracts/iphone-upload-api.md`
- Existing implementation plan: `docs/implementation/iphone-photos-uploader-plan.md`

## Scope

Included:

- Light Apple Photos Native visual system.
- Three-tab app shell after setup: `Library Sync`, `Queue`, `Settings`.
- Setup checklist redesign.
- Library Sync home with photo mosaic, progress summary, primary sync action.
- Queue list with active, waiting, and failed rows.
- Settings list with account/server/folder/Photos/sync preferences.
- Presentation tests for labels, percentages, filters, and retry operations.
- Manual verification doc update.

Excluded:

- Backend changes.
- Pixel receiver changes.
- TestFlight or App Store release UI.
- Advanced throughput charts.
- Dark-only theme.
- Direct Google Drive controls.

## File Structure

Create:

- `ios/iphone/NexusRelayIPhone/Core/Design/NRDesignSystem.swift`
- `ios/iphone/NexusRelayIPhone/Features/AppShell/AppShellView.swift`
- `ios/iphone/NexusRelayIPhone/Features/Setup/SetupChecklistModels.swift`
- `ios/iphone/NexusRelayIPhone/Features/Setup/SetupChecklistView.swift`
- `ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncView.swift`
- `ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncViewModel.swift`
- `ios/iphone/NexusRelayIPhone/Features/LibrarySync/PhotoMosaicView.swift`
- `ios/iphone/NexusRelayIPhone/Features/Queue/UploadQueueView.swift`
- `ios/iphone/NexusRelayIPhone/Features/Queue/UploadQueueViewModel.swift`
- `ios/iphone/NexusRelayIPhone/Features/Queue/UploadQueueModels.swift`
- `ios/iphone/NexusRelayIPhone/Features/Settings/SettingsView.swift`
- `ios/iphone/NexusRelayIPhone/Features/Settings/SettingsViewModel.swift`
- `ios/iphone/NexusRelayIPhone/Core/Photos/PhotoThumbnailProvider.swift`
- `ios/iphone/NexusRelayIPhoneTests/Queue/UploadQueueViewModelTests.swift`
- `ios/iphone/NexusRelayIPhoneTests/LibrarySync/LibrarySyncViewModelTests.swift`
- `ios/iphone/NexusRelayIPhoneTests/Setup/SetupChecklistModelTests.swift`

Modify:

- `ios/iphone/project.yml`
- `ios/iphone/NexusRelayIPhone/App/NexusRelayIPhoneApp.swift`
- `ios/iphone/NexusRelayIPhone/Core/Ledger/UploadLedger.swift`
- `ios/iphone/NexusRelayIPhone/Core/Ledger/SQLiteUploadLedger.swift`
- `ios/iphone/NexusRelayIPhone/Features/Setup/SetupView.swift`
- `ios/iphone/NexusRelayIPhone/Features/Setup/SetupViewModel.swift`
- `ios/iphone/NexusRelayIPhone/Features/SyncStatus/SyncStatusView.swift`
- `ios/iphone/NexusRelayIPhone/Features/SyncStatus/SyncStatusViewModel.swift`
- `ios/iphone/NexusRelayIPhoneTests/Ledger/SQLiteUploadLedgerTests.swift`
- `ios/iphone/docs/manual-verification.md`

Keep:

- Existing API/auth/upload/orchestrator behavior.
- Existing folder auto-create flow for `iPhone Uploads`.
- Existing cookie/CSRF/session storage behavior.

## Shared Commands

Run from `G:/workspace/nexus-relay-mobile/ios/iphone` on macOS:

```bash
xcodegen generate --spec project.yml
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" test
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" build
```

On Windows, only run repository checks:

```powershell
git diff --check
git status --short --branch
```

---

## Task 1: Add The Apple Photos Native Design System

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Core/Design/NRDesignSystem.swift`
- Modify: `ios/iphone/project.yml`

- [ ] **Step 1: Add the design system file**

Create `NRDesignSystem.swift` with app-wide colors, spacing, and reusable status colors:

```swift
import SwiftUI

enum NRDesign {
    enum ColorToken {
        static let appBackground = Color(red: 0.980, green: 0.980, blue: 0.973)
        static let surface = Color.white
        static let primaryText = Color(red: 0.090, green: 0.090, blue: 0.090)
        static let secondaryText = Color(red: 0.420, green: 0.447, blue: 0.502)
        static let hairline = Color(red: 0.902, green: 0.906, blue: 0.890)
        static let accent = Color(red: 0.039, green: 0.518, blue: 0.647)
        static let success = Color(red: 0.180, green: 0.678, blue: 0.420)
        static let warning = Color(red: 0.949, green: 0.722, blue: 0.294)
        static let error = Color(red: 0.847, green: 0.290, blue: 0.290)
    }

    enum Radius {
        static let thumbnail: CGFloat = 8
        static let row: CGFloat = 12
        static let capsule: CGFloat = 24
    }

    enum Spacing {
        static let page: CGFloat = 20
        static let row: CGFloat = 12
        static let section: CGFloat = 24
    }
}

extension View {
    func nrPageBackground() -> some View {
        background(NRDesign.ColorToken.appBackground.ignoresSafeArea())
    }
}
```

- [ ] **Step 2: Ensure XcodeGen includes the new file**

Confirm `project.yml` source glob already includes `NexusRelayIPhone`. If it does, leave `project.yml` unchanged. If the file is not picked up after generation, add:

```yaml
sources:
  - NexusRelayIPhone
```

- [ ] **Step 3: Build-check design symbols**

Run:

```bash
xcodegen generate --spec project.yml
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" build
```

Expected: build succeeds with no missing `NRDesign` symbols.

- [ ] **Step 4: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Core/Design/NRDesignSystem.swift ios/iphone/project.yml
git commit -m "feat(ios): add Apple Photos native design tokens"
```

## Task 2: Add Queue Ledger Read APIs

**Files:**

- Modify: `ios/iphone/NexusRelayIPhone/Core/Ledger/UploadLedger.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Core/Ledger/SQLiteUploadLedger.swift`
- Modify: `ios/iphone/NexusRelayIPhoneTests/Ledger/SQLiteUploadLedgerTests.swift`

- [ ] **Step 1: Extend the ledger protocol**

Add a queue filter and read/retry methods:

```swift
enum UploadQueueFilter: Equatable {
    case all
    case active
    case failed
}

protocol UploadLedger: AnyObject {
    func upsertDiscovered(_ candidates: [PhotoAssetCandidate], folderId: UUID) async throws
    func nextUploadBatch(limit: Int) async throws -> [UploadLedgerRecord]
    func listQueueRecords(filter: UploadQueueFilter, limit: Int) async throws -> [UploadLedgerRecord]
    func retryFailed(ids: [String]) async throws
    func markExporting(id: String) async throws
    func markReady(id: String, stagedFileURL: URL, sizeBytes: Int64) async throws
    func markUploading(id: String) async throws
    func markUploaded(id: String, backendUploadId: UUID) async throws
    func markSyncedByFingerprintSuffixes(_ suffixes: Set<String>, folderId: UUID) async throws
    func markFailed(id: String, error: String, retryable: Bool) async throws
    func getLedgerCounts() async throws -> LedgerCounts
}
```

- [ ] **Step 2: Write failing SQLite tests**

Add tests to `SQLiteUploadLedgerTests`:

```swift
func testListQueueRecordsFiltersActiveWaitingAndFailed() async throws {
    let folderId = UUID()
    let candidate1 = makeCandidate(assetId: "asset-active", fileName: "active.jpg")
    let candidate2 = makeCandidate(assetId: "asset-waiting", fileName: "waiting.jpg")
    let candidate3 = makeCandidate(assetId: "asset-failed", fileName: "failed.jpg")

    try await ledger.upsertDiscovered([candidate1, candidate2, candidate3], folderId: folderId)
    try await ledger.markUploading(id: candidate1.id)
    try await ledger.markFailed(id: candidate3.id, error: "Network error", retryable: true)

    let all = try await ledger.listQueueRecords(filter: .all, limit: 10)
    let active = try await ledger.listQueueRecords(filter: .active, limit: 10)
    let failed = try await ledger.listQueueRecords(filter: .failed, limit: 10)

    XCTAssertEqual(all.count, 3)
    XCTAssertEqual(active.map(\.assetLocalIdentifier), ["asset-active"])
    XCTAssertEqual(failed.map(\.assetLocalIdentifier), ["asset-failed"])
}

func testRetryFailedResetsAttemptsAndClearsError() async throws {
    let folderId = UUID()
    let candidate = makeCandidate(assetId: "asset-failed", fileName: "failed.jpg")

    try await ledger.upsertDiscovered([candidate], folderId: folderId)
    try await ledger.markFailed(id: candidate.id, error: "Server unavailable", retryable: false)
    try await ledger.retryFailed(ids: [candidate.id])

    let records = try await ledger.listQueueRecords(filter: .all, limit: 10)
    XCTAssertEqual(records.first?.status, .discovered)
    XCTAssertEqual(records.first?.attemptCount, 0)
    XCTAssertNil(records.first?.lastError)
}
```

If `makeCandidate` does not exist in the test file, add this helper inside `SQLiteUploadLedgerTests`:

```swift
private func makeCandidate(assetId: String, fileName: String) -> PhotoAssetCandidate {
    PhotoAssetCandidate(
        assetLocalIdentifier: assetId,
        resourceKind: .image,
        originalFilename: fileName,
        uniformTypeIdentifier: "public.jpeg",
        mimeType: "image/jpeg",
        creationDate: Date(timeIntervalSince1970: 1_780_000_000),
        modificationDate: nil,
        pixelWidth: 1200,
        pixelHeight: 800,
        durationSeconds: nil,
        resourceFileSize: 1024
    )
}
```

- [ ] **Step 3: Run failing tests**

Run:

```bash
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" -only-testing:NexusRelayIPhoneTests/SQLiteUploadLedgerTests test
```

Expected: tests fail because `listQueueRecords` and `retryFailed` are not implemented.

- [ ] **Step 4: Implement SQLite queue queries**

Add `listQueueRecords` to `SQLiteUploadLedger` using status filters:

```swift
func listQueueRecords(filter: UploadQueueFilter, limit: Int) async throws -> [UploadLedgerRecord] {
    let statusClause: String
    switch filter {
    case .all:
        statusClause = "status IN ('discovered', 'exporting', 'readyToUpload', 'uploading', 'failed')"
    case .active:
        statusClause = "status IN ('exporting', 'uploading')"
    case .failed:
        statusClause = "status = 'failed'"
    }

    let sql = """
    SELECT id, asset_local_identifier, resource_kind, fingerprint_suffix,
           original_filename, uploaded_file_name, mime_type, size_bytes,
           status, backend_folder_id, backend_upload_id, local_staged_file_url,
           attempt_count, last_attempt_at, last_error
    FROM upload_ledger
    WHERE \(statusClause)
    ORDER BY
      CASE status
        WHEN 'failed' THEN 0
        WHEN 'uploading' THEN 1
        WHEN 'exporting' THEN 2
        WHEN 'readyToUpload' THEN 3
        ELSE 4
      END,
      last_attempt_at DESC,
      id ASC
    LIMIT ?;
    """

    return try queryRecords(sql: sql, params: [limit])
}
```

Extract the existing `nextUploadBatch` row mapping into a private helper:

```swift
private func queryRecords(sql: String, params: [Any]) throws -> [UploadLedgerRecord] {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw DatabaseError.prepareFailed(errorMessage())
    }
    defer { sqlite3_finalize(stmt) }

    bind(params, to: stmt)

    var records: [UploadLedgerRecord] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
        records.append(readRecord(from: stmt))
    }
    return records
}
```

Add helpers:

```swift
private func bind(_ params: [Any], to stmt: OpaquePointer?) {
    for (index, param) in params.enumerated() {
        let bindIndex = Int32(index + 1)
        if let strVal = param as? String {
            sqlite3_bind_text(stmt, bindIndex, strVal, -1, SQLITE_TRANSIENT)
        } else if let intVal = param as? Int64 {
            sqlite3_bind_int64(stmt, bindIndex, intVal)
        } else if let intVal = param as? Int {
            sqlite3_bind_int64(stmt, bindIndex, Int64(intVal))
        } else {
            sqlite3_bind_null(stmt, bindIndex)
        }
    }
}

private func readRecord(from stmt: OpaquePointer?) -> UploadLedgerRecord {
    let id = String(cString: sqlite3_column_text(stmt, 0))
    let assetId = String(cString: sqlite3_column_text(stmt, 1))
    let kindRaw = String(cString: sqlite3_column_text(stmt, 2))
    let suffix = String(cString: sqlite3_column_text(stmt, 3))
    let originalFilename = String(cString: sqlite3_column_text(stmt, 4))
    let uploadedFileName = String(cString: sqlite3_column_text(stmt, 5))
    let mimeType = String(cString: sqlite3_column_text(stmt, 6))
    let sizeBytes: Int64? = sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 7)
    let statusRaw = String(cString: sqlite3_column_text(stmt, 8))
    let folderId = sqlite3_column_type(stmt, 9) == SQLITE_NULL ? nil : UUID(uuidString: String(cString: sqlite3_column_text(stmt, 9)))
    let uploadId = sqlite3_column_type(stmt, 10) == SQLITE_NULL ? nil : UUID(uuidString: String(cString: sqlite3_column_text(stmt, 10)))
    let localUrl = sqlite3_column_type(stmt, 11) == SQLITE_NULL ? nil : URL(string: String(cString: sqlite3_column_text(stmt, 11)))
    let attemptCount = Int(sqlite3_column_int(stmt, 12))
    let lastAttempt = sqlite3_column_type(stmt, 13) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 13)))
    let lastError = sqlite3_column_type(stmt, 14) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 14))

    return UploadLedgerRecord(
        id: id,
        assetLocalIdentifier: assetId,
        resourceKind: PhotoResourceKind(rawValue: kindRaw) ?? .image,
        fingerprintSuffix: suffix,
        originalFilename: originalFilename,
        uploadedFileName: uploadedFileName,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        status: UploadStatus(rawValue: statusRaw) ?? .discovered,
        backendFolderId: folderId,
        backendUploadId: uploadId,
        localStagedFileURL: localUrl,
        attemptCount: attemptCount,
        lastAttemptAt: lastAttempt,
        lastError: lastError
    )
}
```

- [ ] **Step 5: Implement manual retry**

Add:

```swift
func retryFailed(ids: [String]) async throws {
    guard !ids.isEmpty else { return }

    try execute("BEGIN TRANSACTION;")
    do {
        for id in ids {
            let sql = """
            UPDATE upload_ledger
            SET status = 'discovered',
                attempt_count = 0,
                last_error = NULL,
                last_attempt_at = NULL
            WHERE id = ? AND status = 'failed';
            """
            try runUpdate(sql, params: [id])
        }
        try execute("COMMIT;")
    } catch {
        try? execute("ROLLBACK;")
        throw error
    }
}
```

- [ ] **Step 6: Run ledger tests**

Run:

```bash
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" -only-testing:NexusRelayIPhoneTests/SQLiteUploadLedgerTests test
```

Expected: `SQLiteUploadLedgerTests` pass.

- [ ] **Step 7: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Core/Ledger/UploadLedger.swift ios/iphone/NexusRelayIPhone/Core/Ledger/SQLiteUploadLedger.swift ios/iphone/NexusRelayIPhoneTests/Ledger/SQLiteUploadLedgerTests.swift
git commit -m "feat(ios): expose upload queue records"
```

## Task 3: Add Queue Presentation Models And Tests

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Features/Queue/UploadQueueModels.swift`
- Create: `ios/iphone/NexusRelayIPhoneTests/Queue/UploadQueueViewModelTests.swift`

- [ ] **Step 1: Create queue model tests**

Add tests for labels and filters:

```swift
import XCTest
@testable import NexusRelayIPhone

final class UploadQueueViewModelTests: XCTestCase {
    func testQueueItemMapsStatusLabels() {
        let failed = UploadQueueItem(record: makeRecord(status: .failed, lastError: "Network error"))
        let uploading = UploadQueueItem(record: makeRecord(status: .uploading, lastError: nil))
        let waiting = UploadQueueItem(record: makeRecord(status: .discovered, lastError: nil))

        XCTAssertEqual(failed.statusText, "Network error")
        XCTAssertEqual(uploading.statusText, "Uploading")
        XCTAssertEqual(waiting.statusText, "Waiting to upload")
    }

    func testQueueItemProgressFractions() {
        XCTAssertEqual(UploadQueueItem(record: makeRecord(status: .uploaded, lastError: nil)).progressFraction, 1)
        XCTAssertEqual(UploadQueueItem(record: makeRecord(status: .uploading, lastError: nil)).progressFraction, 0.72)
        XCTAssertEqual(UploadQueueItem(record: makeRecord(status: .discovered, lastError: nil)).progressFraction, 0)
    }

    private func makeRecord(status: UploadStatus, lastError: String?) -> UploadLedgerRecord {
        UploadLedgerRecord(
            id: "record-1",
            assetLocalIdentifier: "asset-1",
            resourceKind: .image,
            fingerprintSuffix: "a3f91c0d8e74b210",
            originalFilename: "IMG_1234.HEIC",
            uploadedFileName: "IMG_1234__nr-a3f91c0d8e74b210.HEIC",
            mimeType: "image/heic",
            sizeBytes: 1024,
            status: status,
            backendFolderId: nil,
            backendUploadId: nil,
            localStagedFileURL: nil,
            attemptCount: 0,
            lastAttemptAt: nil,
            lastError: lastError
        )
    }
}
```

- [ ] **Step 2: Run failing tests**

Run:

```bash
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" -only-testing:NexusRelayIPhoneTests/UploadQueueViewModelTests test
```

Expected: tests fail because `UploadQueueItem` does not exist.

- [ ] **Step 3: Add queue presentation models**

Create:

```swift
import Foundation

enum UploadQueueSegment: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case failed = "Failed"

    var id: String { rawValue }

    var ledgerFilter: UploadQueueFilter {
        switch self {
        case .all: return .all
        case .active: return .active
        case .failed: return .failed
        }
    }
}

struct UploadQueueItem: Identifiable, Equatable {
    let id: String
    let assetLocalIdentifier: String
    let filename: String
    let resourceKind: PhotoResourceKind
    let sizeBytes: Int64?
    let status: UploadStatus
    let statusText: String
    let progressFraction: Double
    let canRetry: Bool

    init(record: UploadLedgerRecord) {
        self.id = record.id
        self.assetLocalIdentifier = record.assetLocalIdentifier
        self.filename = record.originalFilename
        self.resourceKind = record.resourceKind
        self.sizeBytes = record.sizeBytes
        self.status = record.status
        self.statusText = Self.statusText(for: record)
        self.progressFraction = Self.progressFraction(for: record.status)
        self.canRetry = record.status == .failed
    }

    private static func statusText(for record: UploadLedgerRecord) -> String {
        if record.status == .failed, let error = record.lastError, !error.isEmpty {
            return error
        }

        switch record.status {
        case .discovered: return "Waiting to upload"
        case .exporting: return "Preparing"
        case .readyToUpload: return "Ready"
        case .uploading: return "Uploading"
        case .uploaded: return "Uploaded"
        case .synced: return "Uploaded"
        case .failed: return "Failed"
        case .skipped: return "Skipped"
        }
    }

    private static func progressFraction(for status: UploadStatus) -> Double {
        switch status {
        case .discovered: return 0
        case .exporting: return 0.18
        case .readyToUpload: return 0.32
        case .uploading: return 0.72
        case .uploaded, .synced: return 1
        case .failed, .skipped: return 0
        }
    }
}
```

- [ ] **Step 4: Run queue model tests**

Run:

```bash
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" -only-testing:NexusRelayIPhoneTests/UploadQueueViewModelTests test
```

Expected: queue model tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Features/Queue/UploadQueueModels.swift ios/iphone/NexusRelayIPhoneTests/Queue/UploadQueueViewModelTests.swift
git commit -m "feat(ios): add upload queue presentation models"
```

## Task 4: Add Thumbnail Provider For Photo Mosaic And Queue Rows

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Core/Photos/PhotoThumbnailProvider.swift`
- Create: `ios/iphone/NexusRelayIPhoneTests/LibrarySync/LibrarySyncViewModelTests.swift`

- [ ] **Step 1: Add thumbnail provider protocol**

Create:

```swift
import PhotoKit
import SwiftUI
import UIKit

protocol PhotoThumbnailProvider {
    func thumbnail(forAssetLocalIdentifier id: String, targetSize: CGSize) async -> UIImage?
}

final class PhotoKitThumbnailProvider: PhotoThumbnailProvider {
    func thumbnail(forAssetLocalIdentifier id: String, targetSize: CGSize) async -> UIImage? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = assets.firstObject else { return nil }

        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
```

- [ ] **Step 2: Add a fake provider for future view-model tests**

Inside `LibrarySyncViewModelTests`, add:

```swift
import UIKit
@testable import NexusRelayIPhone

final class FakeThumbnailProvider: PhotoThumbnailProvider {
    var requestedIds: [String] = []

    func thumbnail(forAssetLocalIdentifier id: String, targetSize: CGSize) async -> UIImage? {
        requestedIds.append(id)
        return UIImage(systemName: "photo")
    }
}
```

- [ ] **Step 3: Build-check PhotoKit imports**

Run:

```bash
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" build
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Core/Photos/PhotoThumbnailProvider.swift ios/iphone/NexusRelayIPhoneTests/LibrarySync/LibrarySyncViewModelTests.swift
git commit -m "feat(ios): add photos thumbnail provider"
```

## Task 5: Replace Root Flow With Native App Shell

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Features/AppShell/AppShellView.swift`
- Modify: `ios/iphone/NexusRelayIPhone/App/NexusRelayIPhoneApp.swift`

- [ ] **Step 1: Add app shell**

Create:

```swift
import SwiftUI

struct AppShellView: View {
    var onLogout: () -> Void

    var body: some View {
        TabView {
            LibrarySyncView()
                .tabItem {
                    Label("Sync", systemImage: "icloud.and.arrow.up")
                }

            UploadQueueView()
                .tabItem {
                    Label("Queue", systemImage: "list.bullet")
                }

            SettingsView(onLogout: onLogout)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(NRDesign.ColorToken.accent)
    }
}
```

- [ ] **Step 2: Update app root**

Change the setup-complete branch in `NexusRelayIPhoneApp`:

```swift
if isSetupComplete {
    AppShellView(onLogout: {
        isSetupComplete = false
    })
} else {
    SetupView(onSetupSuccess: {
        isSetupComplete = true
    })
}
```

- [ ] **Step 3: Add temporary compile stubs**

If `LibrarySyncView`, `UploadQueueView`, or `SettingsView` do not exist yet, create minimal versions that will be replaced in later tasks:

```swift
import SwiftUI

struct LibrarySyncView: View {
    var body: some View {
        NavigationStack {
            Text("Library Sync")
                .navigationTitle("Library Sync")
        }
    }
}
```

Use equivalent stubs for `UploadQueueView` and `SettingsView`.

- [ ] **Step 4: Build-check shell**

Run:

```bash
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" build
```

Expected: build succeeds and app routes to TabView after setup.

- [ ] **Step 5: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/App/NexusRelayIPhoneApp.swift ios/iphone/NexusRelayIPhone/Features/AppShell/AppShellView.swift ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncView.swift ios/iphone/NexusRelayIPhone/Features/Queue/UploadQueueView.swift ios/iphone/NexusRelayIPhone/Features/Settings/SettingsView.swift
git commit -m "feat(ios): add native tab app shell"
```

## Task 6: Redesign Setup As Apple-Style Checklist

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Features/Setup/SetupChecklistModels.swift`
- Create: `ios/iphone/NexusRelayIPhone/Features/Setup/SetupChecklistView.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Features/Setup/SetupView.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Features/Setup/SetupViewModel.swift`
- Create: `ios/iphone/NexusRelayIPhoneTests/Setup/SetupChecklistModelTests.swift`

- [ ] **Step 1: Add checklist model tests**

Create tests:

```swift
import XCTest
@testable import NexusRelayIPhone

final class SetupChecklistModelTests: XCTestCase {
    func testChecklistRowsExposeUserFacingLabels() {
        let rows = SetupChecklistRow.makeRows(
            serverURL: "https://relay.example.com",
            username: "xuan",
            photosStatus: .authorized,
            destinationFolderName: "iPhone Uploads"
        )

        XCTAssertEqual(rows.map(\.title), ["Server", "Sign in", "Photos Access", "Destination Folder"])
        XCTAssertEqual(rows[0].subtitle, "relay.example.com")
        XCTAssertEqual(rows[1].subtitle, "xuan")
        XCTAssertEqual(rows[2].subtitle, "Full access")
        XCTAssertEqual(rows[3].subtitle, "iPhone Uploads")
    }
}
```

- [ ] **Step 2: Add checklist models**

Create:

```swift
import Foundation
import SwiftUI

enum SetupChecklistState: Equatable {
    case complete
    case pending
    case failed

    var iconName: String {
        switch self {
        case .complete: return "checkmark.circle.fill"
        case .pending: return "circle"
        case .failed: return "exclamationmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .complete: return NRDesign.ColorToken.success
        case .pending: return NRDesign.ColorToken.accent
        case .failed: return NRDesign.ColorToken.error
        }
    }
}

struct SetupChecklistRow: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let state: SetupChecklistState

    static func makeRows(
        serverURL: String,
        username: String,
        photosStatus: PhotoLibraryAuthorizationStatus,
        destinationFolderName: String
    ) -> [SetupChecklistRow] {
        [
            SetupChecklistRow(
                id: "server",
                title: "Server",
                subtitle: URL(string: serverURL)?.host ?? "Add server URL",
                systemImage: "server.rack",
                state: URL(string: serverURL) == nil ? .pending : .complete
            ),
            SetupChecklistRow(
                id: "signin",
                title: "Sign in",
                subtitle: username.isEmpty ? "NexusRelay account" : username,
                systemImage: "person.crop.circle",
                state: username.isEmpty ? .pending : .complete
            ),
            SetupChecklistRow(
                id: "photos",
                title: "Photos Access",
                subtitle: photosSubtitle(photosStatus),
                systemImage: "photo.on.rectangle",
                state: photosStatus == .authorized || photosStatus == .limited ? .complete : .pending
            ),
            SetupChecklistRow(
                id: "folder",
                title: "Destination Folder",
                subtitle: destinationFolderName,
                systemImage: "folder",
                state: destinationFolderName.isEmpty ? .pending : .complete
            )
        ]
    }

    private static func photosSubtitle(_ status: PhotoLibraryAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "Full access"
        case .limited: return "Limited access"
        case .denied: return "Access denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Choose access"
        }
    }
}
```

- [ ] **Step 3: Update SetupViewModel for checklist rows**

Add:

```swift
@Published var photosStatus: PhotoLibraryAuthorizationStatus = .notDetermined
@Published var destinationFolderName = "iPhone Uploads"

var checklistRows: [SetupChecklistRow] {
    SetupChecklistRow.makeRows(
        serverURL: serverURL,
        username: username,
        photosStatus: photosStatus,
        destinationFolderName: destinationFolderName
    )
}
```

In `init`, set:

```swift
self.destinationFolderName = s.destinationFolderName
self.photosStatus = photosScanner.authorizationStatus()
```

After `ensurePhotosAuthorization`, set:

```swift
photosStatus = photosStatus
```

Use a different local constant name so it compiles:

```swift
let grantedStatus = await ensurePhotosAuthorization()
self.photosStatus = grantedStatus
guard grantedStatus == .authorized || grantedStatus == .limited else {
    throw SyncError.photosPermissionRequired
}
```

- [ ] **Step 4: Add checklist row view**

Create:

```swift
import SwiftUI

struct SetupChecklistView: View {
    let rows: [SetupChecklistRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                HStack(spacing: 14) {
                    Image(systemName: row.state.iconName)
                        .font(.title3)
                        .foregroundStyle(row.state.tint)
                        .frame(width: 28)

                    Image(systemName: row.systemImage)
                        .font(.title3)
                        .foregroundStyle(NRDesign.ColorToken.accent)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title)
                            .font(.headline)
                            .foregroundStyle(NRDesign.ColorToken.primaryText)
                        Text(row.subtitle)
                            .font(.caption)
                            .foregroundStyle(NRDesign.ColorToken.secondaryText)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NRDesign.ColorToken.secondaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if row.id != rows.last?.id {
                    Divider().padding(.leading, 86)
                }
            }
        }
        .background(NRDesign.ColorToken.surface)
        .clipShape(RoundedRectangle(cornerRadius: NRDesign.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NRDesign.Radius.row, style: .continuous)
                .stroke(NRDesign.ColorToken.hairline, lineWidth: 1)
        )
    }
}
```

- [ ] **Step 5: Replace SetupView layout**

Replace the dark gradient with:

```swift
NavigationStack {
    ScrollView {
        VStack(alignment: .leading, spacing: NRDesign.Spacing.section) {
            VStack(alignment: .leading, spacing: 8) {
                Text("NexusRelay")
                    .font(.largeTitle.bold())
                    .foregroundStyle(NRDesign.ColorToken.primaryText)
                Text("Set up photo relay from this iPhone")
                    .font(.subheadline)
                    .foregroundStyle(NRDesign.ColorToken.secondaryText)
            }
            .padding(.top, 24)

            SetupChecklistView(rows: viewModel.checklistRows)

            setupFields
            setupPreferences

            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(NRDesign.ColorToken.error)
            }

            Text("Password is not stored after login. Photos stay local until upload starts.")
                .font(.caption)
                .foregroundStyle(NRDesign.ColorToken.secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)

            Button {
                Task {
                    await viewModel.saveAndLogin()
                    if viewModel.isSetupComplete {
                        onSetupSuccess()
                    }
                }
            } label: {
                Label(viewModel.isLoading ? "Connecting..." : "Continue", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(NRDesign.ColorToken.accent)
            .disabled(viewModel.isLoading)
        }
        .padding(.horizontal, NRDesign.Spacing.page)
        .padding(.bottom, 32)
    }
    .navigationBarTitleDisplayMode(.inline)
    .nrPageBackground()
}
```

Move fields and toggles into private computed views named `setupFields` and `setupPreferences` using `TextField`, `SecureField`, `Toggle`, `LabeledContent`, and white section backgrounds.

- [ ] **Step 6: Run setup tests and build**

Run:

```bash
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" -only-testing:NexusRelayIPhoneTests/SetupChecklistModelTests test
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" build
```

Expected: tests and build pass.

- [ ] **Step 7: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Features/Setup ios/iphone/NexusRelayIPhoneTests/Setup
git commit -m "feat(ios): redesign setup as native checklist"
```

## Task 7: Build Library Sync Home

**Files:**

- Modify: `ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncView.swift`
- Create: `ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncViewModel.swift`
- Create: `ios/iphone/NexusRelayIPhone/Features/LibrarySync/PhotoMosaicView.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Features/SyncStatus/SyncStatusViewModel.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/LibrarySync/LibrarySyncViewModelTests.swift`

- [ ] **Step 1: Add summary tests**

Append to `LibrarySyncViewModelTests`:

```swift
@MainActor
final class LibrarySyncSummaryTests: XCTestCase {
    func testSummaryComputesProgress() {
        let summary = LibrarySyncSummary(uploaded: 842, waiting: 319, failed: 3, active: 6)

        XCTAssertEqual(summary.progressPercentText, "72% uploaded")
        XCTAssertEqual(summary.summaryText, "842 uploaded · 319 waiting · 3 need attention")
        XCTAssertEqual(summary.progressFraction, 842.0 / 1170.0, accuracy: 0.001)
    }

    func testEmptySummaryDoesNotDivideByZero() {
        let summary = LibrarySyncSummary(uploaded: 0, waiting: 0, failed: 0, active: 0)

        XCTAssertEqual(summary.progressPercentText, "0% uploaded")
        XCTAssertEqual(summary.progressFraction, 0)
    }
}
```

- [ ] **Step 2: Add summary model in LibrarySyncViewModel**

Create:

```swift
import Foundation
import SwiftUI
import UIKit

struct LibrarySyncSummary: Equatable {
    let uploaded: Int
    let waiting: Int
    let failed: Int
    let active: Int

    var total: Int { uploaded + waiting + failed + active }

    var progressFraction: Double {
        guard total > 0 else { return 0 }
        return Double(uploaded) / Double(total)
    }

    var progressPercentText: String {
        "\(Int((progressFraction * 100).rounded()))% uploaded"
    }

    var summaryText: String {
        "\(uploaded) uploaded · \(waiting) waiting · \(failed) need attention"
    }
}

@MainActor
final class LibrarySyncViewModel: ObservableObject {
    @Published var summary = LibrarySyncSummary(uploaded: 0, waiting: 0, failed: 0, active: 0)
    @Published var activeStatus: ActiveSyncStatus = .idle
    @Published var lastSyncDate: Date?
    @Published var errorMessage: String?
    @Published var mosaicImages: [UIImage] = []

    private let syncStatusViewModel: SyncStatusViewModel
    private let thumbnailProvider: PhotoThumbnailProvider

    init(
        syncStatusViewModel: SyncStatusViewModel = SyncStatusViewModel(),
        thumbnailProvider: PhotoThumbnailProvider = PhotoKitThumbnailProvider()
    ) {
        self.syncStatusViewModel = syncStatusViewModel
        self.thumbnailProvider = thumbnailProvider
        refreshFromSyncViewModel()
    }

    func refreshFromSyncViewModel() {
        summary = LibrarySyncSummary(
            uploaded: syncStatusViewModel.uploadedCount,
            waiting: syncStatusViewModel.queuedCount,
            failed: syncStatusViewModel.failedCount,
            active: syncStatusViewModel.exportingCount + syncStatusViewModel.uploadingCount
        )
        activeStatus = syncStatusViewModel.activeStatus
        lastSyncDate = syncStatusViewModel.lastSyncDate
        errorMessage = syncStatusViewModel.errorMessage
    }

    func syncNow() async {
        await syncStatusViewModel.syncNow()
        refreshFromSyncViewModel()
    }

    func reconcile() async {
        await syncStatusViewModel.reconcile()
        refreshFromSyncViewModel()
    }
}
```

- [ ] **Step 3: Add photo mosaic view**

Create:

```swift
import SwiftUI
import UIKit

struct PhotoMosaicView: View {
    let images: [UIImage]

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                tile(index: 0).gridCellRows(2)
                tile(index: 1)
                tile(index: 2)
            }
            GridRow {
                tile(index: 3)
                tile(index: 4).gridCellColumns(2)
            }
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func tile(index: Int) -> some View {
        if images.indices.contains(index) {
            Image(uiImage: images[index])
                .resizable()
                .scaledToFill()
                .clipped()
        } else {
            Rectangle()
                .fill(NRDesign.ColorToken.hairline)
                .overlay(Image(systemName: "photo").foregroundStyle(NRDesign.ColorToken.secondaryText))
        }
    }
}
```

- [ ] **Step 4: Build Library Sync screen**

Create `LibrarySyncView`:

```swift
import SwiftUI

struct LibrarySyncView: View {
    @StateObject private var viewModel = LibrarySyncViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NRDesign.Spacing.section) {
                    PhotoMosaicView(images: viewModel.mosaicImages)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(viewModel.summary.progressPercentText)
                            .font(.largeTitle.bold())
                            .foregroundStyle(NRDesign.ColorToken.primaryText)

                        ProgressView(value: viewModel.summary.progressFraction)
                            .tint(NRDesign.ColorToken.accent)

                        Text(viewModel.summary.summaryText)
                            .font(.callout)
                            .foregroundStyle(NRDesign.ColorToken.primaryText)

                        if let lastSync = viewModel.lastSyncDate {
                            Text("Last sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(NRDesign.ColorToken.secondaryText)
                        }
                    }

                    if let error = viewModel.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(NRDesign.ColorToken.error)
                    }

                    Button {
                        Task { await viewModel.syncNow() }
                    } label: {
                        Label(viewModel.activeStatus == .idle ? "Sync" : "Syncing", systemImage: "icloud.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(NRDesign.ColorToken.accent)
                    .disabled(viewModel.activeStatus != .idle)
                }
                .padding(NRDesign.Spacing.page)
            }
            .navigationTitle("Library Sync")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.reconcile() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityLabel("Rebuild upload history")
                }
            }
            .nrPageBackground()
            .task {
                viewModel.refreshFromSyncViewModel()
            }
        }
    }
}
```

- [ ] **Step 5: Run tests and build**

Run:

```bash
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" -only-testing:NexusRelayIPhoneTests/LibrarySyncSummaryTests test
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" build
```

Expected: tests and build pass.

- [ ] **Step 6: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Features/LibrarySync ios/iphone/NexusRelayIPhoneTests/LibrarySync
git commit -m "feat(ios): add Apple Photos style sync home"
```

## Task 8: Build Upload Queue UI

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Features/Queue/UploadQueueViewModel.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Features/Queue/UploadQueueView.swift`
- Modify: `ios/iphone/NexusRelayIPhoneTests/Queue/UploadQueueViewModelTests.swift`

- [ ] **Step 1: Add fake ledger and view-model tests**

Append inside `UploadQueueViewModelTests`:

```swift
@MainActor
func testQueueViewModelLoadsFilteredRows() async throws {
    let ledger = FakeQueueLedger(records: [
        makeRecord(id: "1", status: .uploading),
        makeRecord(id: "2", status: .failed),
        makeRecord(id: "3", status: .discovered)
    ])
    let viewModel = UploadQueueViewModel(ledger: ledger)

    viewModel.selectedSegment = .failed
    await viewModel.load()

    XCTAssertEqual(viewModel.items.map(\.id), ["2"])
}

@MainActor
func testRetryAllRetriesFailedIdsAndReloads() async throws {
    let ledger = FakeQueueLedger(records: [
        makeRecord(id: "1", status: .failed),
        makeRecord(id: "2", status: .failed)
    ])
    let viewModel = UploadQueueViewModel(ledger: ledger)

    await viewModel.load()
    await viewModel.retryAll()

    XCTAssertEqual(ledger.retriedIds, ["1", "2"])
}

private func makeRecord(id: String, status: UploadStatus) -> UploadLedgerRecord {
    UploadLedgerRecord(
        id: id,
        assetLocalIdentifier: "asset-\(id)",
        resourceKind: .image,
        fingerprintSuffix: "a3f91c0d8e74b210",
        originalFilename: "IMG_\(id).HEIC",
        uploadedFileName: "IMG_\(id)__nr-a3f91c0d8e74b210.HEIC",
        mimeType: "image/heic",
        sizeBytes: 1024,
        status: status,
        backendFolderId: nil,
        backendUploadId: nil,
        localStagedFileURL: nil,
        attemptCount: 0,
        lastAttemptAt: nil,
        lastError: status == .failed ? "Upload failed" : nil
    )
}
```

Add fake ledger outside `UploadQueueViewModelTests`:

```swift
final class FakeQueueLedger: UploadLedger {
    var records: [UploadLedgerRecord]
    var retriedIds: [String] = []

    init(records: [UploadLedgerRecord]) {
        self.records = records
    }

    func listQueueRecords(filter: UploadQueueFilter, limit: Int) async throws -> [UploadLedgerRecord] {
        switch filter {
        case .all: return records
        case .active: return records.filter { $0.status == .uploading || $0.status == .exporting }
        case .failed: return records.filter { $0.status == .failed }
        }
    }

    func retryFailed(ids: [String]) async throws {
        retriedIds = ids
    }

    func upsertDiscovered(_ candidates: [PhotoAssetCandidate], folderId: UUID) async throws {}
    func nextUploadBatch(limit: Int) async throws -> [UploadLedgerRecord] { [] }
    func markExporting(id: String) async throws {}
    func markReady(id: String, stagedFileURL: URL, sizeBytes: Int64) async throws {}
    func markUploading(id: String) async throws {}
    func markUploaded(id: String, backendUploadId: UUID) async throws {}
    func markSyncedByFingerprintSuffixes(_ suffixes: Set<String>, folderId: UUID) async throws {}
    func markFailed(id: String, error: String, retryable: Bool) async throws {}
    func getLedgerCounts() async throws -> LedgerCounts {
        LedgerCounts(queued: 0, uploaded: 0, failed: 0, exporting: 0, uploading: 0)
    }
}
```

- [ ] **Step 2: Implement queue view model**

Create:

```swift
import Foundation

@MainActor
final class UploadQueueViewModel: ObservableObject {
    @Published var selectedSegment: UploadQueueSegment = .all
    @Published var items: [UploadQueueItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let ledger: UploadLedger

    init(ledger: UploadLedger? = nil) {
        if let ledger {
            self.ledger = ledger
        } else {
            let dbURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ledger.sqlite")
            var isCorrupt = false
            self.ledger = LedgerFactory.createOrRecoverLedger(dbURL: dbURL, isCorrupted: &isCorrupt)
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let records = try await ledger.listQueueRecords(filter: selectedSegment.ledgerFilter, limit: 100)
            items = records.map(UploadQueueItem.init(record:))
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func retryAll() async {
        let ids = items.filter(\.canRetry).map(\.id)
        guard !ids.isEmpty else { return }
        do {
            try await ledger.retryFailed(ids: ids)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 3: Implement queue view**

Replace `UploadQueueView`:

```swift
import SwiftUI

struct UploadQueueView: View {
    @StateObject private var viewModel = UploadQueueViewModel()

    var body: some View {
        NavigationStack {
            List {
                Picker("Queue Filter", selection: $viewModel.selectedSegment) {
                    ForEach(UploadQueueSegment.allCases) { segment in
                        Text(segment.rawValue).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(NRDesign.ColorToken.appBackground)

                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(NRDesign.ColorToken.error)
                }

                ForEach(viewModel.items) { item in
                    UploadQueueRow(item: item)
                }

                if viewModel.selectedSegment == .failed && viewModel.items.contains(where: \.canRetry) {
                    Button("Retry all") {
                        Task { await viewModel.retryAll() }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle(viewModel.selectedSegment == .failed ? "Needs Attention" : "Upload Queue")
            .nrPageBackground()
            .task { await viewModel.load() }
            .onChange(of: viewModel.selectedSegment) { _, _ in
                Task { await viewModel.load() }
            }
        }
    }
}

private struct UploadQueueRow: View {
    let item: UploadQueueItem

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: NRDesign.Radius.thumbnail, style: .continuous)
                .fill(NRDesign.ColorToken.hairline)
                .frame(width: 58, height: 58)
                .overlay(Image(systemName: item.resourceKind == .video ? "video" : "photo"))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.filename)
                    .font(.headline)
                    .foregroundStyle(NRDesign.ColorToken.primaryText)
                    .lineLimit(1)
                Text(item.statusText)
                    .font(.caption)
                    .foregroundStyle(item.status == .failed ? NRDesign.ColorToken.error : NRDesign.ColorToken.secondaryText)
                ProgressView(value: item.progressFraction)
                    .tint(item.status == .failed ? NRDesign.ColorToken.error : NRDesign.ColorToken.accent)
            }

            if item.canRetry {
                Image(systemName: "arrow.clockwise.circle")
                    .font(.title2)
                    .foregroundStyle(NRDesign.ColorToken.accent)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.filename), \(item.statusText)")
    }
}
```

- [ ] **Step 4: Run queue tests and build**

Run:

```bash
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" -only-testing:NexusRelayIPhoneTests/UploadQueueViewModelTests test
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" build
```

Expected: tests and build pass.

- [ ] **Step 5: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Features/Queue ios/iphone/NexusRelayIPhoneTests/Queue
git commit -m "feat(ios): add native upload queue"
```

## Task 9: Build Native Settings Screen

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Features/Settings/SettingsViewModel.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Features/Settings/SettingsView.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Features/SyncStatus/SyncStatusViewModel.swift`
- Modify: `ios/iphone/NexusRelayIPhoneTests/SyncStatus/SyncStatusViewModelTests.swift`

- [ ] **Step 1: Add settings view model**

Create:

```swift
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var serverURLString = ""
    @Published var folderName = ""
    @Published var wifiOnly = true
    @Published var includeVideos = true
    @Published var includeLivePhotoVideo = false
    @Published var photosAccessText = "Unknown"

    private let settingsStore: SettingsStore
    private let photosScanner: PhotoLibraryClient

    init(
        settingsStore: SettingsStore = UserDefaultsSettingsStore(),
        photosScanner: PhotoLibraryClient = PhotoKitPhotoLibraryClient()
    ) {
        self.settingsStore = settingsStore
        self.photosScanner = photosScanner
        load()
    }

    func load() {
        let settings = settingsStore.settings
        serverURLString = settings.backendBaseURL?.absoluteString ?? "Not set"
        folderName = settings.destinationFolderName
        wifiOnly = settings.wifiOnly
        includeVideos = settings.includeVideos
        includeLivePhotoVideo = settings.includeLivePhotoVideo
        photosAccessText = photosText(photosScanner.authorizationStatus())
    }

    func saveSyncPreferences() {
        var settings = settingsStore.settings
        settings.wifiOnly = wifiOnly
        settings.includeVideos = includeVideos
        settings.includeLivePhotoVideo = includeLivePhotoVideo
        settingsStore.settings = settings
    }

    private func photosText(_ status: PhotoLibraryAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "Full access"
        case .limited: return "Limited access"
        case .denied: return "Access denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not requested"
        }
    }
}
```

- [ ] **Step 2: Implement settings view**

Replace `SettingsView`:

```swift
import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    var onLogout: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    LabeledContent("Server", value: viewModel.serverURLString)
                    Button(role: .destructive) {
                        onLogout()
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Section("Library") {
                    LabeledContent("Destination Folder", value: viewModel.folderName)
                    LabeledContent("Photos Access", value: viewModel.photosAccessText)
                }

                Section("Sync") {
                    Toggle("Wi-Fi Only", isOn: $viewModel.wifiOnly)
                    Toggle("Include Videos", isOn: $viewModel.includeVideos)
                    Toggle("Live Photo Video", isOn: $viewModel.includeLivePhotoVideo)
                }

                Section {
                    Text("Background sync is best effort. Open the app and tap Sync for the most reliable upload.")
                        .font(.caption)
                        .foregroundStyle(NRDesign.ColorToken.secondaryText)
                }
            }
            .navigationTitle("Settings")
            .scrollContentBackground(.hidden)
            .nrPageBackground()
            .onChange(of: viewModel.wifiOnly) { _, _ in viewModel.saveSyncPreferences() }
            .onChange(of: viewModel.includeVideos) { _, _ in viewModel.saveSyncPreferences() }
            .onChange(of: viewModel.includeLivePhotoVideo) { _, _ in viewModel.saveSyncPreferences() }
        }
    }
}
```

- [ ] **Step 3: Wire sign out through existing logout behavior**

In `AppShellView`, pass the existing logout callback into `SettingsView`. If logout should clear cookies and ledger, route through `SyncStatusViewModel.logout()` by adding a small `SessionActions` object:

```swift
@MainActor
final class SessionActions: ObservableObject {
    private let syncStatusViewModel = SyncStatusViewModel()

    func logout() {
        syncStatusViewModel.logout()
    }
}
```

Then call:

```swift
sessionActions.logout()
onLogout()
```

- [ ] **Step 4: Run build**

Run:

```bash
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" build
```

Expected: build succeeds and settings toggles persist.

- [ ] **Step 5: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Features/Settings ios/iphone/NexusRelayIPhone/Features/AppShell/AppShellView.swift
git commit -m "feat(ios): add native settings screen"
```

## Task 10: Remove Or Retire Dark Sync Dashboard

**Files:**

- Modify: `ios/iphone/NexusRelayIPhone/Features/SyncStatus/SyncStatusView.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Features/SyncStatus/SyncStatusViewModel.swift`
- Modify: `ios/iphone/NexusRelayIPhoneTests/SyncStatus/SyncStatusViewModelTests.swift`

- [ ] **Step 1: Decide compatibility boundary**

Keep `SyncStatusViewModel` as the service-backed sync actions model. Stop using `SyncStatusView` as the main UI.

- [ ] **Step 2: Replace SyncStatusView with compatibility wrapper**

Replace its body with:

```swift
struct SyncStatusView: View {
    var onLogout: () -> Void

    var body: some View {
        AppShellView(onLogout: onLogout)
    }
}
```

- [ ] **Step 3: Keep existing SyncStatusViewModel tests**

Run:

```bash
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" -only-testing:NexusRelayIPhoneTests/SyncStatusViewModelTests test
```

Expected: existing view-model tests pass.

- [ ] **Step 4: Run build**

Run:

```bash
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" build
```

Expected: build succeeds and no dark dashboard screen remains in the app route.

- [ ] **Step 5: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Features/SyncStatus ios/iphone/NexusRelayIPhoneTests/SyncStatus
git commit -m "refactor(ios): retire dark sync dashboard UI"
```

## Task 11: Polish Empty, Loading, Error, And Accessibility States

**Files:**

- Modify: `ios/iphone/NexusRelayIPhone/Features/Setup/SetupView.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncView.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Features/Queue/UploadQueueView.swift`
- Modify: `ios/iphone/NexusRelayIPhone/Features/Settings/SettingsView.swift`

- [ ] **Step 1: Add empty library state**

In `LibrarySyncView`, when summary total is zero, show:

```swift
ContentUnavailableView(
    "No items ready to upload",
    systemImage: "photo.on.rectangle",
    description: Text("Tap Sync after granting Photos access.")
)
```

- [ ] **Step 2: Add queue empty states**

In `UploadQueueView`, when `items` is empty, show:

```swift
ContentUnavailableView(
    viewModel.selectedSegment == .failed ? "No failed uploads" : "Queue is clear",
    systemImage: viewModel.selectedSegment == .failed ? "checkmark.circle" : "tray",
    description: Text(viewModel.selectedSegment == .failed ? "Uploads needing attention will appear here." : "New uploads appear here after scanning.")
)
```

- [ ] **Step 3: Add accessibility labels**

Add labels for primary actions:

```swift
.accessibilityLabel("Start NexusRelay sync")
.accessibilityHint("Scans Photos and uploads pending items to the selected NexusRelay folder")
```

For queue rows:

```swift
.accessibilityLabel("\(item.filename), \(item.statusText)")
.accessibilityHint(item.canRetry ? "Double tap Retry all to retry failed uploads" : "")
```

- [ ] **Step 4: Check Dynamic Type manually**

In Simulator:

```text
Settings app -> Accessibility -> Display & Text Size -> Larger Text
```

Expected:

- Setup rows do not clip.
- Queue filenames truncate cleanly on one line.
- Primary buttons remain at least 44 pt tall.
- Progress labels remain readable.

- [ ] **Step 5: Commit**

```bash
git add ios/iphone/NexusRelayIPhone/Features
git commit -m "polish(ios): add native empty and accessibility states"
```

## Task 12: Update Manual Verification

**Files:**

- Modify: `ios/iphone/docs/manual-verification.md`

- [ ] **Step 1: Replace dark dashboard verification text**

Document the new visual checks:

```markdown
### Apple Photos Native UI Checks

1. First launch opens the `NexusRelay` setup checklist.
2. Setup rows show `Server`, `Sign in`, `Photos Access`, and `Destination Folder`.
3. Completing setup opens the three-tab shell: `Sync`, `Queue`, and `Settings`.
4. `Library Sync` shows a photo mosaic, progress text, a progress bar, and a primary `Sync` action.
5. `Queue` shows segmented filters for `All`, `Active`, and `Failed`.
6. `Settings` shows account, server, destination folder, Photos access, and sync toggles.
7. The app uses a light Apple-style UI, not the old dark gradient dashboard.
```

- [ ] **Step 2: Add blocked-state checks**

Add:

```markdown
### Blocked State Checks

1. With Wi-Fi only enabled on cellular, the sync home should show `Waiting for Wi-Fi`.
2. With expired auth cookies, the app should pause sync and show `Sign in required`.
3. With failed rows in the queue, the `Failed` filter should expose `Retry all`.
```

- [ ] **Step 3: Commit**

```bash
git add ios/iphone/docs/manual-verification.md
git commit -m "docs(ios): update manual verification for native UI"
```

## Task 13: Full Verification And Final Commit Check

**Files:**

- Review all files changed in Tasks 1-12.

- [ ] **Step 1: Run full unit test suite on macOS**

Run:

```bash
cd ios/iphone
xcodegen generate --spec project.yml
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" test
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 2: Run simulator build**

Run:

```bash
cd ios/iphone
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" build
```

Expected:

```text
** BUILD SUCCEEDED **
```

- [ ] **Step 3: Run repository checks**

Run:

```bash
git diff --check
git status --short --branch
```

Expected:

- `git diff --check` exits 0.
- `git status` shows only intentional committed changes or a clean worktree.

- [ ] **Step 4: Push branch after user approval**

Run:

```bash
git push origin feature/ios-uploader-plan
```

Expected: remote branch updates successfully.

## Review Checklist

- Setup uses light Apple-style checklist, not dark gradient cards.
- Library Sync uses photo mosaic and compact progress, not a heavy stats dashboard.
- Queue shows real ledger rows with filters and retry.
- Settings uses native List sections and persists sync toggles.
- Raw Photos local identifiers never appear in UI.
- CSRF/cookie/upload behavior remains untouched.
- Manual sync remains the most reliable foreground path.
- Dynamic Type does not clip important text.
- Unit tests cover new presentation mappings and ledger query behavior.
