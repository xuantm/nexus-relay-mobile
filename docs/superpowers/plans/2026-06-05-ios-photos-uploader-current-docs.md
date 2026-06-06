# iOS Photos Uploader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the native iPhone Photos uploader that uploads selected Photos media into NexusRelay and lets the existing backend and Pixel device-sync path deliver completed media to Pixel devices.

**Architecture:** The iOS app is an uploader only: PhotoKit scan, SQLite upload ledger, app-private export staging, cookie-authenticated NexusRelay API client, CSRF-aware POST requests, stream/chunk upload engine, best-effort background retry, and SwiftUI setup/status screens. The app never calls Google Drive and never talks to Pixel directly.

**Tech Stack:** Swift, SwiftUI, PhotoKit, BackgroundTasks, URLSession, SQLite, Keychain, XCTest, XcodeGen, GitHub Actions macOS.

---

## Source Baseline

Use these documents as the implementation baseline:

- `README.md`
- `docs/architecture/iphone-photos-uploader.md`
- `docs/contracts/iphone-upload-api.md`
- `docs/implementation/iphone-photos-uploader-plan.md`
- `docs/architecture/iphone-source-notes-from-nexus-relay.md`
- `G:/workspace/nexus-relay/docs/upload_flow_under_90mb.md`
- `G:/workspace/nexus-relay/docs/upload_flow_above_90mb.md`
- `G:/workspace/nexus-relay/docs/system_architecture.md`
- `G:/workspace/nexus-relay/docs/superpowers/specs/2026-06-02-device-sync-backend-architecture.md`
- `G:/workspace/nexus-relay/docs/tasks/20260602-device-sync-backend/implementation-report-round-1.md`

Code cross-checks performed against the current backend/frontend:

- `G:/workspace/nexus-relay/frontend/lib/workers/upload.worker.ts`
- `G:/workspace/nexus-relay/backend/src/NexusRelay.Backend.Api/Endpoints/UploadEndpoints.cs`
- `G:/workspace/nexus-relay/backend/src/NexusRelay.Backend.Api/Endpoints/AuthEndpoints.cs`
- `G:/workspace/nexus-relay/backend/src/NexusRelay.Backend.Api/Program.Helpers.cs`
- `G:/workspace/nexus-relay/backend/src/NexusRelay.Backend.Application/DTOs/Contracts.cs`

## Fixed Product Decisions

- iOS MVP is a native Photos uploader, not an iOS receiver.
- Pixel delivery is out of iOS scope and happens after backend `MediaItem` reaches `Completed` and device-sync jobs are created.
- iOS calls NexusRelay APIs only. It must not call Google Drive APIs.
- Auth uses existing cookie auth for MVP.
- All unsafe HTTP methods must support the backend CSRF flow unless the backend intentionally exempts mobile endpoints.
- Stream uploads use `<= 90 MB`.
- Chunked uploads use `> 90 MB`.
- Chunk size is `30 MB`.
- Max request retries is `3`.
- Default destination folder is `iPhone Uploads`.
- Default settings are `wifiOnly = true`, `includeVideos = true`, `includeLivePhotoVideo = false`.
- Live Photo paired video is post-MVP unless explicitly pulled into MVP.

## Contract Gaps To Close Before App Code

The current mobile contract is close, but implementation must close these gaps before writing production iOS networking code:

- `POST` endpoints require CSRF handling today because backend middleware validates antiforgery for non-GET requests.
- iOS must call `GET /api/auth/csrf`, store the returned request token, keep the `nexus_csrf` cookie, and send `X-NexusRelay-CSRF` on `POST /api/auth/login`, `/api/auth/refresh`, `/api/folders`, `/api/upload/init`, `/api/upload/chunk`, and `/api/upload/complete`.
- `GET /api/folders/{id}/media` returns `FolderContentDto`, not a bare media array. Reconciliation must parse `media.items` and support the existing `mediaItems` field while the contract is cleaned up.
- `x-file-name` is URL-decoded by the backend, so iOS should percent-encode the uploaded file name in the header.
- `/api/upload/chunk` accepts raw `application/octet-stream` bytes with `x-upload-id`, `x-chunk-index`, and `x-chunk-size` headers.

## Target Repository Layout

```text
ios/
  iphone/
    README.md
    project.yml
    NexusRelayIPhone/
      App/
      Core/
        API/
        Auth/
        Background/
        Ledger/
        Photos/
        Upload/
        Utilities/
      Features/
        Setup/
        SyncStatus/
        FolderPicker/
      Resources/
    NexusRelayIPhoneTests/
      API/
      Auth/
      Ledger/
      Photos/
      Upload/
      Utilities/
.github/
  workflows/
    ios-iphone.yml
```

## Milestone 0: Contract Alignment

**Outcome:** The mobile repo documents the actual backend contract before implementation starts.

**Files:**

- Modify: `docs/contracts/iphone-upload-api.md`
- Modify: `docs/implementation/iphone-photos-uploader-plan.md`

- [ ] Add `GET /api/auth/csrf` to the iPhone upload API contract.
- [ ] Document that cookie-authenticated `POST` calls send `X-NexusRelay-CSRF`.
- [ ] Document that the app keeps the backend cookie jar, including `access_token`, `refresh_token`, and `nexus_csrf`.
- [ ] Replace the folder media reconciliation response shape with `FolderContentDto`.
- [ ] Document the raw chunk body format and exact headers.
- [ ] Keep a note that backend should later consider a mobile bearer-token auth endpoint to remove CSRF/cookie complexity.
- [ ] Review the updated contract against `UploadEndpoints.cs`, `AuthEndpoints.cs`, `FolderEndpoints.cs`, and `Contracts.cs`.
- [ ] Commit: `docs(ios): align iphone upload contract with backend`

## Milestone 1: iOS Scaffold And CI

**Outcome:** A buildable iOS app shell exists under `ios/iphone`.

**Files:**

- Create: `ios/iphone/project.yml`
- Create: `ios/iphone/README.md`
- Create: `ios/iphone/NexusRelayIPhone/App/NexusRelayIPhoneApp.swift`
- Create: `ios/iphone/NexusRelayIPhone/App/AppDelegate.swift`
- Create: `ios/iphone/NexusRelayIPhone/Resources/Info.plist`
- Create: `ios/iphone/NexusRelayIPhoneTests/SmokeTests.swift`
- Create: `.github/workflows/ios-iphone.yml`

- [ ] Scaffold with XcodeGen, bundle id `com.nexusrelay.iphone`, minimum iOS `17.0`.
- [ ] Add Photos usage description.
- [ ] Add `BGTaskSchedulerPermittedIdentifiers` with `com.nexusrelay.iphone.sync`.
- [ ] Add `UIBackgroundModes` value `processing`.
- [ ] Add a smoke unit test.
- [ ] Add macOS CI that runs `xcodegen generate`, `xcodebuild test`, and `xcodebuild build`.
- [ ] Verify on macOS: `xcodebuild -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test`.
- [ ] Commit: `feat(ios): scaffold iphone uploader app`

## Milestone 2: API Client, Cookie Auth, And CSRF

**Outcome:** The app can log in, refresh, log out, call authenticated APIs, and attach CSRF headers for unsafe methods.

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Core/API/APIModels.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/API/HTTPClient.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/API/NexusRelayAPIClient.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Auth/AuthSession.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Auth/CookieSessionStore.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Auth/CSRFTokenProvider.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Auth/KeychainStore.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/API/NexusRelayAPIClientTests.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/Auth/CSRFTokenProviderTests.swift`

- [ ] Model `BrowserAuthResponse`, `FolderDTO`, `FolderContentDTO`, `MediaItemDTO`, `InitUploadRequest`, `InitUploadResponse`, `CompleteUploadRequest`, and `StreamUploadResponse`.
- [ ] Implement a shared `URLSession` using `HTTPCookieStorage`.
- [ ] Persist cookie/session material in Keychain.
- [ ] Implement `GET /api/auth/csrf` and cache the request token until a 400/401/403 indicates it should be refreshed.
- [ ] Add `X-NexusRelay-CSRF` to every non-GET request.
- [ ] On `401`, call `/api/auth/refresh` once, refresh CSRF, and retry the original request once.
- [ ] On refresh failure, pause uploads and surface "Login required".
- [ ] Unit test login, CSRF header attachment, one-shot refresh retry, and refresh failure.
- [ ] Commit: `feat(ios): add authenticated nexusrelay api client`

## Milestone 3: Settings And Destination Folder Setup

**Outcome:** The user can configure a backend URL and destination NexusRelay folder.

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Core/Utilities/AppSettings.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Utilities/SettingsStore.swift`
- Create: `ios/iphone/NexusRelayIPhone/Features/FolderPicker/FolderPickerView.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/Utilities/SettingsStoreTests.swift`

- [ ] Store `backendBaseURL`, `destinationFolderId`, `destinationFolderName`, `wifiOnly`, `includeVideos`, and `includeLivePhotoVideo`.
- [ ] Default folder name to `iPhone Uploads`.
- [ ] List root folders through `GET /api/folders`.
- [ ] Select an existing `iPhone Uploads` folder when present.
- [ ] Create `iPhone Uploads` through `POST /api/folders` when missing.
- [ ] Persist selected folder id only after the backend returns a valid `FolderDTO`.
- [ ] Unit test folder selection, folder creation, and settings persistence.
- [ ] Commit: `feat(ios): add settings and folder setup`

## Milestone 4: PhotoKit Scanner And Fingerprints

**Outcome:** The app can discover upload candidates and generate stable backend-visible filenames without exposing Photos local identifiers.

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Core/Photos/PhotoAssetCandidate.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Photos/PhotoLibraryClient.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Photos/PhotoKitPhotoLibraryClient.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Photos/AssetFingerprinter.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/Photos/AssetFingerprinterTests.swift`

- [ ] Request Photos permission and handle `.authorized`, `.limited`, `.denied`, and `.restricted`.
- [ ] Scan image and video resources using public PhotoKit APIs only.
- [ ] Store each candidate as `assetLocalIdentifier`, `resourceKind`, original filename, UTI, MIME type, dates, dimensions, duration, and size.
- [ ] Generate `sha256(assetLocalIdentifier + resourceKind + creationDate + originalFilename + resourceFileSize)`.
- [ ] Use first 16 lowercase hex chars as the public suffix.
- [ ] Generate uploaded file names as `<base>__nr-<suffix>.<extension>`.
- [ ] Sanitize `/`, `\`, quotes, CR, and LF from names.
- [ ] Unit test deterministic fingerprints, changed-size fingerprints, filename sanitization, extension preservation, and no raw local identifier leakage.
- [ ] Commit: `feat(ios): add photokit scanning and fingerprinting`

## Milestone 5: SQLite Upload Ledger

**Outcome:** Upload state survives app restarts, crashes, retries, and local recovery.

**Files:**

- Modify: `ios/iphone/project.yml`
- Create: `ios/iphone/NexusRelayIPhone/Core/Ledger/UploadLedger.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Ledger/UploadLedgerModels.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Ledger/SQLiteUploadLedger.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/Ledger/SQLiteUploadLedgerTests.swift`

- [ ] Link `libsqlite3.tbd`.
- [ ] Create a schema for candidate identity, fingerprint suffix, uploaded filename, backend folder id, backend upload id, staged file URL, status, attempt count, last attempt time, and last error.
- [ ] Use statuses `discovered`, `exporting`, `readyToUpload`, `uploading`, `uploaded`, `synced`, `failed`, and `skipped`.
- [ ] Use a unique key on `assetLocalIdentifier + resourceKind + fingerprintSuffix + backendFolderId`.
- [ ] Implement transitions for discovery, export, ready, upload, uploaded, synced, failed, skipped.
- [ ] Return retryable failed rows in the next upload batch until max retries is reached.
- [ ] Unit test duplicate discovery, legal transitions, retryable failures, terminal failures, and synced rows excluded from upload batch.
- [ ] Commit: `feat(ios): add upload ledger`

## Milestone 6: Export Staging

**Outcome:** The app exports Photos originals into app-private temporary files before upload.

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Core/Upload/AssetExporter.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Upload/PhotoKitAssetExporter.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Upload/TemporaryFileStore.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/Upload/TemporaryFileStoreTests.swift`

- [ ] Export with `PHAssetResourceManager.writeData(for:toFile:options:)`.
- [ ] Use app-private temporary directories keyed by ledger record id.
- [ ] Delete partial files when export fails.
- [ ] Delete staged files after successful upload or terminal skip.
- [ ] Skip iCloud-only exports on cellular when Wi-Fi-only is enabled.
- [ ] Mark iCloud network-required failures without blocking the full queue.
- [ ] Unit test temp paths, cleanup, and stale temp deletion.
- [ ] Commit: `feat(ios): add photos export staging`

## Milestone 7: Upload Engine

**Outcome:** The app uploads small and large files through the existing NexusRelay upload APIs.

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Core/Upload/UploadPolicy.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Upload/UploadEngine.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Upload/ChunkFileBuilder.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/Upload/UploadEngineTests.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/Upload/ChunkFileBuilderTests.swift`

- [ ] Implement `UploadPolicy.nexusRelayDefault` with `90 MB` stream threshold, `30 MB` chunk size, `3` max retries, foreground chunk concurrency `2`, and background chunk concurrency `1`.
- [ ] For stream uploads, call `POST /api/upload/stream` with URL-encoded `x-file-name`, `x-folder-id`, `x-file-size`, `Content-Type`, cookies, CSRF header, and exact file bytes.
- [ ] For chunk uploads, call `POST /api/upload/init`, upload raw chunk files with `x-upload-id`, `x-chunk-index`, `x-chunk-size`, then call `POST /api/upload/complete`.
- [ ] Use file-backed `URLSessionUploadTask` requests, not in-memory `Data`, for stream uploads and chunk uploads.
- [ ] Build chunk temp files with exact byte ranges so `x-chunk-size` matches body length.
- [ ] Send `fileHash = null` on `/api/upload/complete` until the app has a measured full-file hash implementation.
- [ ] Treat upload responses as backend acceptance, not final Pixel import completion.
- [ ] Retry network failures up to max retries with backoff.
- [ ] On 4xx other than 401, mark the record failed with the backend error.
- [ ] Unit test stream path, chunk path, exact chunk sizes, 401 refresh, CSRF refresh, retry ceiling, and permanent failure.
- [ ] Commit: `feat(ios): add nexusrelay upload engine`

## Milestone 8: Reconciliation And Recovery

**Outcome:** The app can rebuild local upload state from Photos plus backend folder media.

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Core/Upload/ReconciliationService.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/Upload/ReconciliationServiceTests.swift`

- [ ] List destination folder media with `GET /api/folders/{folderId}/media?mediaPageSize=60`.
- [ ] Page until all media needed for reconciliation is retrieved or no more pages remain.
- [ ] Parse `__nr-<16-hex>` markers from backend filenames.
- [ ] Scan local Photos candidates and compute suffixes.
- [ ] Mark local candidates as `synced` when suffixes exist in backend media names.
- [ ] On SQLite open failure, move the bad DB to `UploadLedger.corrupt.<timestamp>.sqlite`, create a new DB, and run reconciliation.
- [ ] Unit test marker parsing, folder DTO decoding, synced marking, and corrupt-ledger recovery.
- [ ] Commit: `feat(ios): add upload reconciliation`

## Milestone 9: Sync Orchestrator And Background Retry

**Outcome:** Manual sync is reliable, and background processing resumes existing queued work when iOS allows it.

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Core/Background/BackgroundSyncScheduler.swift`
- Create: `ios/iphone/NexusRelayIPhone/Core/Upload/SyncOrchestrator.swift`
- Modify: `ios/iphone/NexusRelayIPhone/App/AppDelegate.swift`
- Test: `ios/iphone/NexusRelayIPhoneTests/Upload/SyncOrchestratorTests.swift`

- [ ] Manual sync checks auth, folder, Photos permission, and network policy.
- [ ] Manual sync scans candidates, upserts ledger rows, exports originals, uploads files, cleans temp files, and continues after one record fails.
- [ ] Background sync drains existing ledger work first and scans incrementally when time allows.
- [ ] Use `URLSessionConfiguration.background` for eligible file-backed upload tasks where it does not break CSRF/cookie refresh behavior.
- [ ] Register `BGProcessingTask` with `com.nexusrelay.iphone.sync`.
- [ ] Schedule next background attempt after each foreground/manual run.
- [ ] Respect Low Power Mode, constrained network, and Wi-Fi-only settings.
- [ ] Unit test missing auth, missing folder, denied Photos, one-record failure continuation, and Wi-Fi-only skip.
- [ ] Commit: `feat(ios): add sync orchestration`

## Milestone 10: SwiftUI Setup And Status UI

**Outcome:** The user can configure, sync, observe progress, and recover from common failures.

**Files:**

- Create: `ios/iphone/NexusRelayIPhone/Features/Setup/SetupView.swift`
- Create: `ios/iphone/NexusRelayIPhone/Features/Setup/SetupViewModel.swift`
- Create: `ios/iphone/NexusRelayIPhone/Features/SyncStatus/SyncStatusView.swift`
- Create: `ios/iphone/NexusRelayIPhone/Features/SyncStatus/SyncStatusViewModel.swift`
- Modify: `ios/iphone/NexusRelayIPhone/App/NexusRelayIPhoneApp.swift`

- [ ] Setup UI captures backend URL, username, password, Photos permission, destination folder, Wi-Fi-only, include videos, and manual sync entry point.
- [ ] Status UI shows auth state, Photos state, folder, queued count, uploading count, synced count, failed count, last sync time, and last error.
- [ ] Add `Sync now`, `Retry failed`, `Reconcile`, and `Logout` actions.
- [ ] Show "Preparing assets" immediately before heavy PhotoKit export/scanning work.
- [ ] Keep heavy export/hash/upload work off the main actor.
- [ ] Manual test setup flow on Simulator with mocked Photos where possible.
- [ ] Commit: `feat(ios): add setup and sync status ui`

## Milestone 11: End-To-End Verification

**Outcome:** The native uploader is proven against NexusRelay backend and the Pixel delivery path.

**Files:**

- Create: `ios/iphone/docs/manual-verification.md`
- Modify: `ios/iphone/README.md`

- [ ] Run unit tests on macOS.
- [ ] Run iOS Simulator build.
- [ ] Run against local NexusRelay backend and verify login, CSRF, folder setup, stream upload, chunk upload, and reconciliation.
- [ ] Run on a real iPhone with limited Photos access.
- [ ] Upload one image under `90 MB`.
- [ ] Upload one video over `90 MB`.
- [ ] Confirm media appears in NexusRelay destination folder.
- [ ] Confirm backend marks uploaded media `Completed`.
- [ ] Confirm Pixel receives device-sync jobs and imports media through the existing Pixel path.
- [ ] Kill and restart the iOS app mid-queue and verify ledger recovery.
- [ ] Delete the local ledger and verify reconciliation prevents duplicate upload.
- [ ] Toggle Wi-Fi-only and verify cellular upload is skipped.
- [ ] Expire auth and verify refresh or login-required pause.
- [ ] Document results and not-run items.
- [ ] Commit: `docs(ios): add manual verification results`

## Work Split

- Worker A: Milestone 0, contract alignment.
- Worker B: Milestone 1, scaffold and CI.
- Worker C: Milestone 2, networking/auth/CSRF.
- Worker D: Milestone 3, settings and folder setup.
- Worker E: Milestone 4, PhotoKit scanner and fingerprinting.
- Worker F: Milestone 5, SQLite ledger.
- Worker G: Milestone 6, export staging.
- Worker H: Milestone 7, upload engine.
- Worker I: Milestone 8, reconciliation.
- Worker J: Milestone 9, orchestration/background.
- Worker K: Milestone 10, UI.
- Worker L: Milestone 11, end-to-end verification.

## Dependency Order

```text
0 -> 1 -> 2 -> 3
1 -> 4 -> 5 -> 6
2 + 5 + 6 -> 7
2 + 4 + 5 -> 8
3 + 5 + 7 + 8 -> 9
3 + 9 -> 10
1..10 -> 11
```

## Acceptance Checklist

- App stores session/cookie material in Keychain.
- App sends CSRF headers for unsafe cookie-authenticated calls.
- App never stores user password after login.
- App never calls Google Drive directly.
- App never exposes raw Photos local identifiers in uploaded filenames.
- App can upload `<= 90 MB` through stream upload.
- App can upload `> 90 MB` through chunked upload.
- Chunk request body length matches `x-chunk-size`.
- Auth refresh retries the original request once only.
- Local ledger survives app restart.
- Reconciliation prevents duplicate upload after ledger loss.
- Manual sync works without relying on background execution.
- Background processing resumes queued work best-effort.
- Limited Photos access works.
- iCloud-only assets do not block the full queue.
- Pixel delivery is verified after backend `Completed` status.
- CI build and unit tests pass on macOS.

## Known Risks

- Current docs omit CSRF for iPhone; implementation must either support CSRF or backend must add a mobile-specific auth exemption/token flow.
- Background upload timing is not guaranteed by iOS; manual sync must remain the primary reliable path.
- Real PhotoKit export behavior, iCloud-only assets, and limited-library UX require physical iPhone testing.
- `FolderContentDto` shape should be kept backward-compatible in the iOS decoder while docs and backend stabilize.
- If deployment exposes only the Next.js front door and not the backend API, the iOS base URL decision must be tested with large uploads through the public route.
