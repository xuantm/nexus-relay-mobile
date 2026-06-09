---
scope: contracts/api
status: partial
sources:
  - docs/contracts/device-sync-api.md
  - docs/contracts/iphone-upload-api.md
  - android/pixel/app/src/main/java/com/nexusrelay/pixel/api/NexusRelayApi.kt
  - android/pixel/app/src/main/java/com/nexusrelay/pixel/api/DeviceSyncDtos.kt
  - ios/iphone/NexusRelayIPhone/Core/API/NexusRelayAPIClient.swift
  - ios/iphone/NexusRelayIPhone/Core/API/APIModels.swift
last_verified_commit: c53b326ddc88d1db76b2d958d18eb7daed2e8b28
---

# API Contracts

## Source Of Truth
| Contract | Path | Consumer | Backend source |
|---|---|---|---|
| Device sync API | `docs/contracts/device-sync-api.md` | Android Pixel app | ⚠️ Undocumented — verify: external `nexus-relay` repo |
| iPhone upload API | `docs/contracts/iphone-upload-api.md` | iOS iPhone app | ⚠️ Undocumented — verify: external `nexus-relay` repo |

## Pixel Device Sync Endpoints
| Method | Route | Auth | Request | Response | Client |
|---|---|---|---|---|---|
| `POST` | `/api/device-sync/pairing-codes/redeem` | anonymous pairing code | `RedeemPairingCodeRequest` | `RedeemPairingCodeResponse` | `android/pixel/app/src/main/java/com/nexusrelay/pixel/api/NexusRelayApi.kt` |
| `POST` | `/api/device-sync/fcm-token` | `X-Device-Token` | `UpdateDeviceFcmTokenRequest` | empty/204-style | `NexusRelayApi.updateFcmToken` |
| `GET` | `/api/device-sync/jobs/pending` | `X-Device-Token` | none | `List<DeviceSyncJobDto>` | `NexusRelayApi.pendingJobs` |
| `POST` | `/api/device-sync/jobs/{jobId}/downloading` | `X-Device-Token` | none | empty/204-style | `NexusRelayApi.markDownloading` |
| `GET` | `/api/device-sync/jobs/{jobId}/download` | `X-Device-Token` | none | streamed bytes | `NexusRelayApi.downloadJob` |
| `POST` | `/api/device-sync/jobs/{jobId}/confirm` | `X-Device-Token` | imported URI/size | empty/204-style | `NexusRelayApi.confirm` |
| `POST` | `/api/device-sync/jobs/{jobId}/fail` | `X-Device-Token` | error message | empty/204-style | `NexusRelayApi.fail` |

## iPhone Auth / Folder / Upload Endpoints
| Method | Route | Auth | Request | Response | Client |
|---|---|---|---|---|---|
| `GET` | `/api/auth/google/login` | browser | `client=ios`, `returnUrl=nexusrelay://auth/success` | callback URL | `GoogleAuthCoordinator.swift` |
| `POST` | `/api/auth/ios/session-exchange` | one-time code | `IosSessionExchangeRequest` | cookies + `BrowserAuthResponse` | `NexusRelayAPIClient.exchangeIosSession` |
| `GET` | `/api/auth/csrf` | cookies | none | `{ token }` | `CSRFTokenProvider.swift` |
| `POST` | `/api/auth/refresh` | cookies + CSRF | none | refreshed cookies | `HTTPClient.performRefresh` |
| `GET` | `/api/auth/me` | cookies | none | `BrowserAuthResponse` | `NexusRelayAPIClient.currentUser` |
| `GET` | `/api/folders` | cookies | none | `[FolderDTO]` | `listRootFolders` |
| `POST` | `/api/folders` | cookies + CSRF | `CreateFolderRequest` | `FolderDTO` | `createFolder` |
| `GET` | `/api/folders/{folderId}/media` | cookies | page/cursor query | `FolderContentDTO` | `listFolderMedia` |
| `POST` | `/api/upload/stream` | cookies + CSRF | file headers + bytes | `StreamUploadResponse` | `streamUpload` |
| `POST` | `/api/upload/init` | cookies + CSRF | `InitUploadRequest` | `InitUploadResponse` | `initUpload` |
| `POST` | `/api/upload/chunk` | cookies + CSRF | chunk headers + bytes | empty/200-style | `uploadChunk` |
| `POST` | `/api/upload/complete` | cookies + CSRF | `CompleteUploadRequest` | empty/200-style | `completeUpload` |

## Status Vocabulary
| Area | Public values | Local/internal mapping |
|---|---|---|
| Pixel receive sync | `Pending`, `Syncing`, `Synced`, `Failed` | `LocalSyncStatus.toSyncStatus()` maps local ledger states |
| iPhone upload | `Pending`, `Uploading`, `Uploaded`, `Failed` | `UploadLedgerStatus.uploadStatus` maps SQLite ledger states |

## Gaps / Verify
> ⚠️ Undocumented — verify: no OpenAPI/protobuf/generated client was found; mobile DTOs and markdown contracts must be kept in sync manually.

> ⚠️ Undocumented — verify: backend route handlers, response status codes, cookie flags, and DTO compatibility are not verifiable inside this repo.
