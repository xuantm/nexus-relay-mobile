# iPhone Photos Uploader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the iPhone app that uploads Photos media into NexusRelay so the existing backend and Pixel sync path can deliver those uploads to the Pixel.

**Architecture:** The app scans Photos through PhotoKit, persists an upload ledger in SQLite, exports original resources to temporary app storage, uploads through existing NexusRelay backend APIs, and uses background processing as a best-effort retry path. Dedupe is based on a local ledger plus a backend-visible filename fingerprint.

**Tech Stack:** Swift, SwiftUI, PhotoKit, BackgroundTasks, URLSession, SQLite, Keychain, XCTest, XcodeGen, GitHub Actions macOS.

---

## Scope

This plan covers only the iPhone uploader app under `ios/iphone`.

Included:

- iOS project scaffold.
- Login/session handling with existing NexusRelay cookie auth.
- Destination folder picker/create flow.
- Photos permission request and limited library handling.
- PhotoKit scanner and asset fingerprinting.
- SQLite upload ledger.
- Temporary original-resource export.
- Stream and chunked upload clients.
- Manual sync and background retry.
- Queue/status UI.
- Unit tests and macOS CI.

Excluded:

- Pixel receiver changes.
- NexusRelay backend changes.
- Direct Google Drive access.
- App Store release.
- iOS receiver behavior for NexusRelay device-sync jobs.
- Full automatic backup while the app is never opened.

## Expected Repository Layout

```text
ios/
  iphone/
    README.md
    project.yml
    NexusRelayIPhone/
      App/
        NexusRelayIPhoneApp.swift
        AppDelegate.swift
      Features/
        Setup/
        SyncStatus/
        FolderPicker/
      Core/
        API/
        Auth/
        Background/
        Ledger/
        Photos/
        Upload/
        Utilities/
      Resources/
        Info.plist
    NexusRelayIPhoneTests/
      API/
      Auth/
      Ledger/
      Photos/
      Upload/
.github/
  workflows/
    ios-iphone.yml
docs/
  architecture/iphone-photos-uploader.md
  contracts/iphone-upload-api.md
  implementation/iphone-photos-uploader-plan.md
```

## Worker Assignment Map

- Worker A: Part 1 iOS scaffold and CI baseline.
- Worker B: Part 2 API contracts and auth session.
- Worker C: Part 3 settings, Keychain, and folder setup.
- Worker D: Part 4 Photos scanner and fingerprinting.
- Worker E: Part 5 SQLite upload ledger.
- Worker F: Part 6 export staging.
- Worker G: Part 7 upload engine.
- Worker H: Part 8 sync orchestrator and background tasks.
- Worker I: Part 9 SwiftUI status UI.
- Worker J: Part 10 reconciliation and recovery.
- Worker K: Part 11 integration verification and docs.

Parts 2, 3, and 5 can start after Part 1. Parts 4 and 6 can start after Part 1. Part 7 depends on Parts 2 and 6. Part 8 depends on Parts 4, 5, and 7. Part 10 depends on Parts 2, 4, and 5.

## Shared Constants

Use these defaults unless the owner changes them:

```text
Bundle id: com.nexusrelay.iphone
App name: NexusRelay iPhone
Minimum iOS: 17.0
Default folder name: iPhone Uploads
Stream threshold: 90 MB
Chunk size: 30 MB
Max request retries: 3
Fingerprint marker: __nr-
Background processing identifier: com.nexusrelay.iphone.sync
```

## Part 1: iOS Project Scaffold

**Worker:** iOS scaffold worker.

**Files:**

- Create: `ios/iphone/README.md`
- Create: `ios/iphone/project.yml`
- Create: `ios/iphone/NexusRelayIPhone/App/NexusRelayIPhoneApp.swift`
- Create: `ios/iphone/NexusRelayIPhone/App/AppDelegate.swift`
- Create: `ios/iphone/NexusRelayIPhone/Resources/Info.plist`
- Create: `ios/iphone/NexusRelayIPhoneTests/SmokeTests.swift`
- Create: `.github/workflows/ios-iphone.yml`

- [ ] **Step 1: Create XcodeGen project config**

Create `ios/iphone/project.yml`:

```yaml
name: NexusRelayIPhone
options:
  bundleIdPrefix: com.nexusrelay
  deploymentTarget:
    iOS: "17.0"
settings:
  base:
    SWIFT_VERSION: "5.10"
targets:
  NexusRelayIPhone:
    type: application
    platform: iOS
    sources:
      - NexusRelayIPhone
    resources:
      - NexusRelayIPhone/Resources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.nexusrelay.iphone
        INFOPLIST_FILE: NexusRelayIPhone/Resources/Info.plist
    dependencies: []
  NexusRelayIPhoneTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - NexusRelayIPhoneTests
    dependencies:
      - target: NexusRelayIPhone
```

- [ ] **Step 2: Add Info.plist**

Create `ios/iphone/NexusRelayIPhone/Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>NexusRelay iPhone</string>
  <key>NSPhotoLibraryUsageDescription</key>
  <string>NexusRelay needs access to upload selected photos and videos to your NexusRelay server.</string>
  <key>BGTaskSchedulerPermittedIdentifiers</key>
  <array>
    <string>com.nexusrelay.iphone.sync</string>
  </array>
  <key>UIBackgroundModes</key>
  <array>
    <string>processing</string>
  </array>
</dict>
</plist>
```

- [ ] **Step 3: Add app entry point**

Create `ios/iphone/NexusRelayIPhone/App/NexusRelayIPhoneApp.swift`:

```swift
import SwiftUI

@main
struct NexusRelayIPhoneApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            Text("NexusRelay iPhone")
                .padding()
        }
    }
}
```

- [ ] **Step 4: Add app delegate**

Create `ios/iphone/NexusRelayIPhone/App/AppDelegate.swift`:

```swift
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }
}
```

- [ ] **Step 5: Add README**

Create `ios/iphone/NexusRelayIPhoneTests/SmokeTests.swift`:

```swift
import XCTest
@testable import NexusRelayIPhone

final class SmokeTests: XCTestCase {
    func testTestBundleLoads() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 6: Add README**

Create `ios/iphone/README.md`:

````markdown
# NexusRelay iPhone

iPhone Photos uploader for NexusRelay.

## Build

```bash
cd ios/iphone
xcodegen generate
xcodebuild -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' build
```
````

- [ ] **Step 7: Add GitHub Actions macOS build**

Create `.github/workflows/ios-iphone.yml`:

```yaml
name: iOS iPhone

on:
  pull_request:
    paths:
      - 'ios/iphone/**'
      - '.github/workflows/ios-iphone.yml'
  push:
    branches:
      - develop
      - 'feature/**'
    paths:
      - 'ios/iphone/**'
      - '.github/workflows/ios-iphone.yml'

jobs:
  build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Install XcodeGen
        run: brew install xcodegen
      - name: Generate project
        working-directory: ios/iphone
        run: xcodegen generate
      - name: Build
        working-directory: ios/iphone
        run: xcodebuild -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' build
```

- [ ] **Step 8: Verify scaffold**

Run on macOS:

```bash
cd ios/iphone
xcodegen generate
xcodebuild -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected:

```text
** BUILD SUCCEEDED **
```

Commit:

```bash
git add ios/iphone .github/workflows/ios-iphone.yml
git commit -m "feat(ios): scaffold iphone uploader app"
```

## Part 2: API Contracts And Auth Session

**Worker:** API/auth worker.

**Depends on:** Part 1.

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Core/API/APIModels.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/API/NexusRelayAPI.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/API/HTTPClient.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Auth/AuthSession.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/API/APIModelsTests.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/Auth/AuthSessionTests.swift`

- [ ] **Step 1: Add API DTOs**

Create `APIModels.swift`:

```swift
import Foundation

struct LoginRequest: Codable, Equatable {
    let username: String
    let password: String
}

struct BrowserAuthResponse: Codable, Equatable {
    let id: UUID
    let username: String
    let email: String?
    let role: String
}

struct FolderDTO: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let parentId: UUID?
    let googleDriveFolderId: String?
    let createdAt: Date
    let childCount: Int
    let mediaCount: Int
}

struct CreateFolderRequest: Codable, Equatable {
    let name: String
    let parentId: UUID?
}

struct InitUploadRequest: Codable, Equatable {
    let folderId: UUID?
    let fileName: String
    let totalSize: Int64
    let totalChunks: Int
}

struct InitUploadResponse: Codable, Equatable {
    let uploadId: UUID
}

struct CompleteUploadRequest: Codable, Equatable {
    let uploadId: UUID
    let fileHash: String?
}

struct StreamUploadResponse: Codable, Equatable {
    let uploadId: UUID
}
```

- [ ] **Step 2: Add HTTP client protocol**

Create `HTTPClient.swift`:

```swift
import Foundation

struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data?
}

struct HTTPResponse {
    let statusCode: Int
    let headers: [AnyHashable: Any]
    let body: Data
}

protocol HTTPClient {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
    func uploadFile(_ request: HTTPRequest, fileURL: URL) async throws -> HTTPResponse
}
```

- [ ] **Step 3: Add auth session**

Create `AuthSession.swift`:

```swift
import Foundation

struct AuthSession: Equatable {
    let userId: UUID
    let username: String
    let role: String
    let cookies: [HTTPCookie]

    var isAuthenticated: Bool {
        !cookies.isEmpty
    }
}
```

- [ ] **Step 4: Add API interface**

Create `NexusRelayAPI.swift`:

```swift
import Foundation

protocol NexusRelayAPI {
    func login(username: String, password: String) async throws -> AuthSession
    func refresh(session: AuthSession) async throws -> AuthSession
    func currentUser(session: AuthSession) async throws -> BrowserAuthResponse
    func listRootFolders(session: AuthSession) async throws -> [FolderDTO]
    func createFolder(name: String, parentId: UUID?, session: AuthSession) async throws -> FolderDTO
    func streamUpload(fileURL: URL, fileName: String, folderId: UUID, mimeType: String, fileSize: Int64, session: AuthSession) async throws -> StreamUploadResponse
    func initUpload(folderId: UUID, fileName: String, totalSize: Int64, totalChunks: Int, session: AuthSession) async throws -> InitUploadResponse
    func uploadChunk(uploadId: UUID, chunkIndex: Int, chunkSize: Int64, chunkFileURL: URL, session: AuthSession) async throws
    func completeUpload(uploadId: UUID, fileHash: String?, session: AuthSession) async throws
}
```

- [ ] **Step 5: Test DTO decoding**

Create `APIModelsTests.swift` with JSON fixtures from `docs/contracts/iphone-upload-api.md`.

Run:

```bash
cd ios/iphone
xcodebuild -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Expected:

```text
** TEST SUCCEEDED **
```

Commit:

```bash
git add ios/iphone/NexusRelayIPhone/Core/API ios/iphone/NexusRelayIPhone/Core/Auth ios/iphone/NexusRelayIPhoneTests
git commit -m "feat(ios): add nexusrelay api contracts"
```

## Part 3: Settings, Keychain, And Folder Setup

**Worker:** setup worker.

**Depends on:** Parts 1 and 2.

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Core/Auth/KeychainStore.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Auth/SessionStore.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Utilities/AppSettings.swift`
- Create: `ios/iphone/NexusRelayIPhone/Features/FolderPicker/FolderPickerView.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/Auth/SessionStoreTests.swift`

- [ ] **Step 1: Store secrets in Keychain**

Implement `KeychainStore` with methods:

```swift
protocol KeychainStore {
    func save(_ data: Data, account: String) throws
    func load(account: String) throws -> Data?
    func delete(account: String) throws
}
```

- [ ] **Step 2: Store non-secret settings**

Implement `AppSettings` with:

```swift
struct AppSettings: Codable, Equatable {
    var backendBaseURL: URL?
    var destinationFolderId: UUID?
    var destinationFolderName: String
    var wifiOnly: Bool
    var includeVideos: Bool
    var includeLivePhotoVideo: Bool

    static let defaults = AppSettings(
        backendBaseURL: nil,
        destinationFolderId: nil,
        destinationFolderName: "iPhone Uploads",
        wifiOnly: true,
        includeVideos: true,
        includeLivePhotoVideo: false
    )
}
```

- [ ] **Step 3: Add folder setup flow**

The setup flow should:

```text
1. list root folders;
2. select existing "iPhone Uploads" if present;
3. otherwise offer to create it;
4. store destinationFolderId after success.
```

- [ ] **Step 4: Verify**

Run:

```bash
cd ios/iphone
xcodebuild -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Commit:

```bash
git add ios/iphone/NexusRelayIPhone/Core/Auth ios/iphone/NexusRelayIPhone/Core/Utilities ios/iphone/NexusRelayIPhone/Features/FolderPicker ios/iphone/NexusRelayIPhoneTests/Auth
git commit -m "feat(ios): add session and folder setup"
```

## Part 4: Photos Scanner And Fingerprinting

**Worker:** PhotoKit worker.

**Depends on:** Part 1.

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Core/Photos/PhotoAssetCandidate.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Photos/PhotoLibraryClient.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Photos/AssetFingerprinter.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/Photos/AssetFingerprinterTests.swift`

- [ ] **Step 1: Define upload candidate**

Create:

```swift
import Foundation

enum PhotoResourceKind: String, Codable {
    case image
    case video
    case livePhotoVideo
}

struct PhotoAssetCandidate: Codable, Equatable, Identifiable {
    var id: String { assetLocalIdentifier + ":" + resourceKind.rawValue }
    let assetLocalIdentifier: String
    let resourceKind: PhotoResourceKind
    let originalFilename: String
    let uniformTypeIdentifier: String
    let mimeType: String
    let creationDate: Date?
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let durationSeconds: Double?
    let resourceFileSize: Int64?
}
```

- [ ] **Step 2: Implement fingerprinting**

Fingerprint input:

```text
assetLocalIdentifier
resourceKind
creationDate ISO string
originalFilename
resourceFileSize
```

Public suffix:

```text
first 16 lowercase hex chars of sha256(input)
```

Uploaded filename:

```text
<sanitized-original-base>__nr-<suffix>.<original-extension>
```

- [ ] **Step 3: Add PhotoLibraryClient protocol**

```swift
protocol PhotoLibraryClient {
    func authorizationStatus() async -> PhotoLibraryAuthorizationStatus
    func requestAuthorization() async -> PhotoLibraryAuthorizationStatus
    func fetchCandidates(includeVideos: Bool, includeLivePhotoVideo: Bool) async throws -> [PhotoAssetCandidate]
}
```

- [ ] **Step 4: Verify**

Test cases:

```text
same candidate -> same suffix
changed file size -> different suffix
raw localIdentifier never appears in uploaded filename
original extension is preserved
unsafe filename chars are removed
```

Commit:

```bash
git add ios/iphone/NexusRelayIPhone/Core/Photos ios/iphone/NexusRelayIPhoneTests/Photos
git commit -m "feat(ios): add photo scanner models and fingerprinting"
```

## Part 5: SQLite Upload Ledger

**Worker:** ledger worker.

**Depends on:** Part 4.

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Core/Ledger/UploadLedger.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Ledger/UploadLedgerModels.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Ledger/SQLiteUploadLedger.swift`
- Modify: `ios/iphone/project.yml`
- Test: `ios/iphone/NexusRelayIPhoneTests/Ledger/SQLiteUploadLedgerTests.swift`

- [ ] **Step 1: Define statuses**

Update `ios/iphone/project.yml` to link SQLite:

```yaml
  NexusRelayIPhone:
    dependencies:
      - sdk: libsqlite3.tbd
```

- [ ] **Step 2: Define statuses**

```swift
enum UploadStatus: String, Codable, Equatable {
    case discovered
    case exporting
    case readyToUpload
    case uploading
    case uploaded
    case synced
    case failed
    case skipped
}
```

- [ ] **Step 3: Define ledger record**

```swift
struct UploadLedgerRecord: Codable, Equatable, Identifiable {
    let id: String
    let assetLocalIdentifier: String
    let resourceKind: PhotoResourceKind
    let fingerprintSuffix: String
    let originalFilename: String
    let uploadedFileName: String
    let mimeType: String
    let sizeBytes: Int64?
    let status: UploadStatus
    let backendFolderId: UUID?
    let backendUploadId: UUID?
    let localStagedFileURL: URL?
    let attemptCount: Int
    let lastAttemptAt: Date?
    let lastError: String?
}
```

- [ ] **Step 4: Add ledger protocol**

```swift
protocol UploadLedger {
    func upsertDiscovered(_ candidates: [PhotoAssetCandidate], folderId: UUID) async throws
    func nextUploadBatch(limit: Int) async throws -> [UploadLedgerRecord]
    func markExporting(id: String) async throws
    func markReady(id: String, stagedFileURL: URL, sizeBytes: Int64) async throws
    func markUploading(id: String) async throws
    func markUploaded(id: String, backendUploadId: UUID) async throws
    func markSyncedByFingerprintSuffixes(_ suffixes: Set<String>, folderId: UUID) async throws
    func markFailed(id: String, error: String, retryable: Bool) async throws
}
```

- [ ] **Step 5: Verify**

Test transitions:

```text
discovered -> exporting -> readyToUpload -> uploading -> uploaded -> synced
failed retryable record appears in nextUploadBatch
synced record does not appear in nextUploadBatch
duplicate candidate updates existing row
```

Commit:

```bash
git add ios/iphone/NexusRelayIPhone/Core/Ledger ios/iphone/NexusRelayIPhoneTests/Ledger
git commit -m "feat(ios): add upload ledger"
```

## Part 6: Export Staging

**Worker:** export worker.

**Depends on:** Parts 4 and 5.

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Core/Upload/AssetExporter.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Upload/TemporaryFileStore.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/Upload/TemporaryFileStoreTests.swift`

- [ ] **Step 1: Add temporary file store**

Responsibilities:

```text
create per-record temp directory
return final staged file URL
delete staged file after successful upload
clean stale temp files older than 7 days
```

- [ ] **Step 2: Add asset exporter protocol**

```swift
protocol AssetExporter {
    func exportOriginalResource(
        candidate: PhotoAssetCandidate,
        outputFileName: String,
        allowNetworkAccess: Bool
    ) async throws -> URL
}
```

- [ ] **Step 3: Implement PhotoKit exporter**

Use `PHAssetResourceManager.writeData(for:toFile:options:)`.

Rules:

```text
allowNetworkAccess = false when Wi-Fi only is enabled and current network is cellular
write to app-private temporary file
do not mutate Photos library
delete partial temp file when export fails
```

- [ ] **Step 4: Verify**

Use fake exporter in unit tests and run manual device test for real PhotoKit export.

Commit:

```bash
git add ios/iphone/NexusRelayIPhone/Core/Upload ios/iphone/NexusRelayIPhoneTests/Upload
git commit -m "feat(ios): add photos export staging"
```

## Part 7: Upload Engine

**Worker:** upload worker.

**Depends on:** Parts 2, 5, and 6.

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Core/Upload/UploadEngine.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Upload/UploadPolicy.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Upload/ChunkFileBuilder.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/Upload/UploadEngineTests.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/Upload/ChunkFileBuilderTests.swift`

- [ ] **Step 1: Add upload policy**

```swift
struct UploadPolicy: Equatable {
    let streamThresholdBytes: Int64
    let chunkSizeBytes: Int64
    let maxRetries: Int

    static let nexusRelayDefault = UploadPolicy(
        streamThresholdBytes: 90 * 1024 * 1024,
        chunkSizeBytes: 30 * 1024 * 1024,
        maxRetries: 3
    )
}
```

- [ ] **Step 2: Add upload engine**

```swift
protocol UploadEngine {
    func upload(record: UploadLedgerRecord, session: AuthSession, folderId: UUID) async throws -> UUID
}
```

Behavior:

```text
if file size <= 90 MB -> call /api/upload/stream
if file size > 90 MB -> init, upload chunks, complete
on 401 -> refresh session, retry original request once
on network error -> retry request up to maxRetries
return backend uploadId
```

- [ ] **Step 3: Add chunk file builder**

The backend expects each `/api/upload/chunk` request body length to match `x-chunk-size`.

Create temporary chunk files with exact sizes:

```text
chunk 0 = bytes 0..<chunkSize
chunk n = bytes start..<min(end, fileSize)
```

- [ ] **Step 4: Verify**

Test:

```text
small file uses stream upload
large file uses init/chunk/complete
chunk sizes are exact
401 refreshes and retries once
network failure retries up to maxRetries
permanent 4xx marks failure
```

Commit:

```bash
git add ios/iphone/NexusRelayIPhone/Core/Upload ios/iphone/NexusRelayIPhoneTests/Upload
git commit -m "feat(ios): add nexusrelay upload engine"
```

## Part 8: Sync Orchestrator And Background Tasks

**Worker:** sync orchestration worker.

**Depends on:** Parts 3, 4, 5, 6, and 7.

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Core/Background/BackgroundSyncScheduler.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Upload/SyncOrchestrator.swift`
- Modify: `ios/iphone/NexusRelayIPhone/App/AppDelegate.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/Upload/SyncOrchestratorTests.swift`

- [ ] **Step 1: Add sync orchestrator**

Responsibilities:

```text
check auth and destination folder
request or validate Photos permission
scan candidates
upsert candidates into ledger
drain next upload batch
export each record
upload each record
mark uploaded/synced
cleanup temp files
continue after single-record failure
```

- [ ] **Step 2: Add background scheduler**

Use:

```swift
import BackgroundTasks
```

Register:

```text
com.nexusrelay.iphone.sync
```

Schedule:

```text
BGProcessingTaskRequest(identifier: "com.nexusrelay.iphone.sync")
requiresNetworkConnectivity = true
requiresExternalPower = false
earliestBeginDate = Date().addingTimeInterval(15 * 60)
```

- [ ] **Step 3: Update AppDelegate**

Register background task at launch. On task execution, call the orchestrator and set task success based on result.

- [ ] **Step 4: Verify**

Unit tests:

```text
orchestrator skips when not logged in
orchestrator skips when folder missing
orchestrator continues after one failed upload
orchestrator respects Wi-Fi-only setting
background scheduler submits expected task request
```

Commit:

```bash
git add ios/iphone/NexusRelayIPhone/Core/Background ios/iphone/NexusRelayIPhone/Core/Upload ios/iphone/NexusRelayIPhone/App/AppDelegate.swift ios/iphone/NexusRelayIPhoneTests
git commit -m "feat(ios): add sync orchestration"
```

## Part 9: SwiftUI Setup And Status UI

**Worker:** UI worker.

**Depends on:** Parts 3, 5, and 8.

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Features/Setup/SetupView.swift`
- Create: `ios/iphone/NexusRelayIPhone/Features/SyncStatus/SyncStatusView.swift`
- Create: `ios/iphone/NexusRelayIPhone/Features/SyncStatus/SyncStatusViewModel.swift`
- Modify: `ios/iphone/NexusRelayIPhone/App/NexusRelayIPhoneApp.swift`

- [ ] **Step 1: Add setup view**

Fields:

```text
Backend URL
Username
Password
Login button
Photos permission button
Destination folder selector
Wi-Fi only toggle
Include videos toggle
```

- [ ] **Step 2: Add sync status view**

Show:

```text
auth status
Photos permission status
destination folder
queued count
uploading count
synced count
failed count
last sync time
last error
Sync now button
Retry failed button
```

- [ ] **Step 3: Wire app root**

If no backend URL/session/folder, show setup. Otherwise show sync status.

- [ ] **Step 4: Manual verification**

On iPhone or simulator:

```text
open app
enter backend URL
login
grant Photos permission
select/create folder
tap Sync now
see queue progress
```

Commit:

```bash
git add ios/iphone/NexusRelayIPhone/Features ios/iphone/NexusRelayIPhone/App/NexusRelayIPhoneApp.swift
git commit -m "feat(ios): add setup and sync status ui"
```

## Part 10: Reconciliation And Recovery

**Worker:** recovery worker.

**Depends on:** Parts 2, 4, and 5.

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Core/Upload/ReconciliationService.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/Upload/ReconciliationServiceTests.swift`

- [ ] **Step 1: Parse backend filename markers**

Parse:

```text
__nr-<16 lowercase hex chars>
```

from backend media filenames.

- [ ] **Step 2: Rebuild synced status**

Algorithm:

```text
1. list destination folder media;
2. collect fingerprint suffixes from filenames;
3. scan local Photos candidates;
4. upsert candidates into ledger;
5. mark records whose suffix exists in backend as synced.
```

- [ ] **Step 3: Handle corrupted ledger**

On SQLite open failure:

```text
move database to UploadLedger.corrupt.<timestamp>.sqlite
create a new database
run reconciliation
show a non-blocking warning in status UI
```

- [ ] **Step 4: Verify**

Test:

```text
backend filename marker parser ignores normal filenames
matching suffix marks record synced
corrupted ledger path is moved aside
new ledger is created after corruption
```

Commit:

```bash
git add ios/iphone/NexusRelayIPhone/Core/Upload ios/iphone/NexusRelayIPhoneTests/Upload
git commit -m "feat(ios): add upload reconciliation"
```

## Part 11: End-To-End Verification

**Worker:** integration worker.

**Depends on:** Parts 1-10.

**Files:**

- Create: `ios/iphone/docs/manual-verification.md`
- Modify: `ios/iphone/README.md`

- [ ] **Step 1: Run unit tests**

Run on macOS:

```bash
cd ios/iphone
xcodegen generate
xcodebuild -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 2: Run build**

```bash
cd ios/iphone
xcodebuild -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected:

```text
** BUILD SUCCEEDED **
```

- [ ] **Step 3: Manual backend upload test**

Use a real iPhone and deployed NexusRelay:

```text
1. login to NexusRelay from app
2. create/select iPhone Uploads folder
3. grant limited Photos access with one image and one video
4. tap Sync now
5. confirm files appear in NexusRelay folder
6. wait for backend relay to mark items Completed
7. confirm Pixel receives device-sync jobs and imports media
```

- [ ] **Step 4: Manual recovery tests**

Test:

```text
delete app ledger and reopen app
run reconciliation
confirm already-uploaded Photos items are not uploaded again
toggle Wi-Fi only and verify cellular upload is skipped
force auth expiration and verify refresh or login-required state
kill app during upload and verify retry resumes from ledger
```

- [ ] **Step 5: Update docs**

Document:

```text
build steps
GitHub Actions macOS workflow
manual verification results
known iOS background limits
```

Commit:

```bash
git add ios/iphone/README.md ios/iphone/docs/manual-verification.md
git commit -m "docs(ios): add manual verification guide"
```

## Review Checklist

Before opening PR:

```text
No raw Photos localIdentifier in backend-visible filename
No Google Drive API calls in iOS app
No user password stored after login
Keychain stores session/cookie material
Ledger can recover using backend filename fingerprints
Manual sync works without background execution
Background task is best-effort only
Large files use chunked upload
401 refresh retries once only
All unit tests pass on macOS
GitHub Actions macOS workflow passes
```
