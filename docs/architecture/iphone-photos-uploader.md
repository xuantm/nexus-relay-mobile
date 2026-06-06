# iPhone Photos Uploader Architecture

## Goal

Build an iPhone app that uploads selected or newly discovered media from Apple Photos into NexusRelay. After NexusRelay finishes the normal backend upload and relay flow, the existing Pixel device-sync path can deliver those media items to the Pixel.

The iPhone app is an uploader. It does not receive NexusRelay device-sync jobs and it does not talk to the Pixel directly.

## Recommended Design

Use:

```text
PhotoKit scan + local upload ledger + URLSession uploads + BGProcessing fallback
```

The iPhone app should treat NexusRelay as the server-side source of media storage and the local ledger as the source of local upload progress. iOS background execution is best-effort, so the app must make manual "Sync now" reliable and use background processing as a recovery path rather than the only path.

## Flow

```text
iPhone app setup
  -> user logs in to NexusRelay
  -> user chooses or creates destination folder
  -> user grants Photos access
  -> app scans PhotoKit assets
  -> app records upload candidates in local ledger
  -> app exports original asset resource to app-private temporary file
  -> app uploads through NexusRelay /api/upload endpoints
  -> backend relays media to Google Drive
  -> backend marks MediaItem Completed
  -> backend creates DeviceSyncJob for Pixel targets
  -> Pixel app receives through existing device-sync flow
```

## Scope

Included:

- iPhone app setup and status UI.
- Login against existing NexusRelay auth endpoints.
- Destination folder selection or creation.
- Photos permission handling for full and limited access.
- PhotoKit asset scanning.
- Local dedupe and upload ledger.
- Original image/video export from Photos.
- Upload through existing NexusRelay upload APIs.
- Background upload and retry where iOS allows it.
- Reconciliation after local ledger corruption or reinstall.

Excluded:

- Pixel receiver changes.
- NexusRelay backend device-sync changes.
- Direct Google Drive access from iOS.
- Direct iPhone-to-Pixel transfer.
- App Store release automation for the MVP.
- Full automatic backup guarantees while the app is never opened; iOS does not allow that reliably.

## Backend API Boundary

The iPhone app should only call NexusRelay backend APIs:

- `/api/auth/login`
- `/api/auth/refresh`
- `/api/auth/logout`
- `/api/auth/me`
- `/api/folders`
- `/api/folders/{id}/media`
- `/api/upload/stream`
- `/api/upload/init`
- `/api/upload/chunk`
- `/api/upload/complete`

The current backend login endpoint returns auth cookies, not bearer tokens, so the iPhone MVP should use cookie-based auth. The API client should still isolate auth behind an `AuthSession` abstraction so a later mobile bearer-token endpoint can be swapped in without rewriting upload code.

## PhotoKit Model

The app should use public PhotoKit APIs only. It must not inspect or depend on Apple's private Photos database.

Supported assets:

- images;
- videos;
- Live Photo still image and paired video as separate upload candidates if enabled.

MVP recommendation:

```text
Upload normal image and video resources first.
Treat Live Photo paired video as a later part unless the owner explicitly wants it in MVP.
```

For each upload candidate, the app stores:

```text
assetLocalIdentifier
resourceType
originalFilename
uniformTypeIdentifier
mimeType
creationDate
modificationDate
pixelWidth
pixelHeight
durationSeconds
resourceFileSize
fingerprint
uploadStatus
backendFolderId
backendUploadId
backendMediaId
uploadedFileName
lastAttemptAt
lastError
```

## Deduplication

The app must know whether a Photos item was already uploaded without relying only on volatile in-memory state.

Use two layers:

1. Local ledger keyed by `assetLocalIdentifier + resourceType + versionKey`.
2. Backend filename fingerprint so the app can rebuild state after local ledger loss.

The fingerprint should be deterministic and not expose the raw `assetLocalIdentifier`:

```text
fingerprint = sha256(assetLocalIdentifier + resourceType + creationDate + originalFilename + resourceFileSize)
publicSuffix = first 16 hex chars of fingerprint
```

Uploaded filename format:

```text
<original-name-without-extension>__nr-<publicSuffix>.<extension>
```

Example:

```text
IMG_1001__nr-a3f91c0d8e74b210.HEIC
```

This lets the iPhone app list the NexusRelay destination folder and parse existing `__nr-<suffix>` markers. If the local ledger is deleted or corrupted, the app can scan Photos, list backend media names, and mark matching candidates as already uploaded.

## Local Ledger

Use SQLite for the iOS ledger. It is small, queryable, resilient enough for queue state, and easy to test with temporary databases.

Statuses:

```text
Discovered
Exporting
ReadyToUpload
Uploading
Uploaded
Confirming
Synced
Failed
Skipped
```

For stream upload, `Uploaded` means `/api/upload/stream` returned successfully. For chunked upload, `Uploaded` means `/api/upload/complete` returned successfully. The backend relay can still be processing after that; Pixel sync starts only after the backend marks media `Completed`.

## Upload Strategy

Use the same threshold as the web uploader unless backend limits change:

```text
Stream upload <= 90 MB
Chunked upload > 90 MB
Chunk size = 30 MB
Max retries per request = 3
```

Stream upload:

```text
POST /api/upload/stream
headers: x-file-name, x-folder-id, x-file-size, Content-Type
body: file bytes
```

Chunked upload:

```text
POST /api/upload/init
POST /api/upload/chunk for each chunk
POST /api/upload/complete
```

The app should upload from app-private temporary files, not from Photos streams directly. This makes retries, background handoff, and file-size validation predictable.

## iOS Background Execution

iOS does not guarantee continuous background execution for a general sync app. Design with these rules:

- Manual foreground sync must be the most reliable path.
- Use `BGProcessingTask` for periodic scan and queue drain.
- Use `URLSessionConfiguration.background` for long-running upload requests where practical.
- Register tasks in `Info.plist` using `BGTaskSchedulerPermittedIdentifiers`.
- Respect Low Power Mode and network constraints.
- If "Wi-Fi only" is enabled, do not export from iCloud or upload on cellular.

Background execution should resume existing ledger work. It should not assume it can scan the entire library every time.

## iCloud Photos

Some Photos assets may not be fully local. When exporting with `PHAssetResourceManager`, the app can allow network access only if settings permit it.

Rules:

- If Wi-Fi-only is enabled and the current network is cellular, skip iCloud-only assets.
- If network access is disabled, mark the asset `Failed` with a clear `needsICloudDownload` reason.
- Do not block the whole queue on one iCloud-only asset.

## Error Handling

Network failure:

- keep ledger status retryable;
- exponential backoff;
- retry the exact same fingerprint and filename.

Auth failure:

- call `/api/auth/refresh`;
- if refresh fails, pause queue and show "Login required";
- do not store the user's password.

Export failure:

- keep the Photos asset id and error;
- allow manual retry;
- skip unsupported resource types.

Local ledger corruption:

- move the bad database aside;
- create a new database;
- rebuild from PhotoKit scan plus backend folder filename fingerprints.

Backend folder missing:

- show setup repair UI;
- let user choose another folder or recreate the default folder.

## Security

- Store cookies/session material in Keychain.
- Store non-secret settings in UserDefaults.
- Keep temporary export files under app-private storage.
- Delete temporary files after successful upload or terminal failure.
- Never call Google Drive directly.
- Never include raw Photos local identifiers in backend-visible filenames.

## Testing Strategy

Unit tests should cover:

- fingerprint generation;
- filename marker parsing;
- ledger transitions;
- retry policy;
- API request construction;
- auth refresh behavior;
- folder reconciliation.

Integration tests should run on macOS/iOS Simulator where possible:

- login with mocked URLProtocol;
- scan with fake PhotoLibrary adapter;
- upload with fake URLSession transport;
- database recovery from a corrupted ledger file.

Manual verification on an iPhone is required for:

- Photos limited-access behavior;
- iCloud-only assets;
- background upload continuation;
- app restart during upload;
- Wi-Fi-only behavior;
- Pixel receives uploaded item after backend relay completes.
