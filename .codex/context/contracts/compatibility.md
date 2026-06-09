---
scope: contracts/compatibility
status: partial
sources:
  - docs/contracts/device-sync-api.md
  - docs/contracts/iphone-upload-api.md
  - android/pixel/app/src/test/java/com/nexusrelay/pixel/api/DeviceSyncDtoTest.kt
  - ios/iphone/NexusRelayIPhoneTests/API/NexusRelayAPIClientTests.swift
  - ios/iphone/NexusRelayIPhone/Core/API/APIModels.swift
last_verified_commit: c53b326ddc88d1db76b2d958d18eb7daed2e8b28
---

# Contract Compatibility

## Compatibility Rules
| Change | Rule | Verification |
|---|---|---|
| Add response field | Prefer optional/defaulted mobile decoding during backend rollout | Android Moshi DTO test; iOS decode test |
| Remove/rename response field | Treat as breaking unless both mobile clients are updated and released | Update contract docs, DTOs, tests |
| Add required request field | Treat as breaking for already-installed mobile clients | Backend should default or version |
| Change auth header/cookie/CSRF behavior | High risk; trace through security context and tests | API/auth tests plus manual backend run |
| Change status enum | Update public contract docs and local projection helpers | Android `SyncStatus`; iOS `UploadStatus` tests |
| Change upload threshold/chunk size | Update `UploadPolicy`, docs, manual large-file verification | iOS upload/chunk tests |

## Manual Contract Duplication
| Contract | Markdown | Android DTO | iOS DTO |
|---|---|---|---|
| Device sync jobs | `docs/contracts/device-sync-api.md` | `DeviceSyncJobDto` | n/a |
| Pixel pairing | `docs/contracts/device-sync-api.md` | `RedeemPairingCodeRequest/Response` | n/a |
| iPhone auth/folders/uploads | `docs/contracts/iphone-upload-api.md` | n/a | `APIModels.swift`, `NexusRelayAPIClient.swift` |
| Shared statuses | both contract docs | `SyncStatus` | `UploadStatus` |

## High-Risk Compatibility Areas
| Area | Risk | Existing mitigation |
|---|---|---|
| Pixel device token flow | Backend change can strand paired devices | Encrypted token storage plus `X-Device-Token` contract |
| iOS cookie/CSRF flow | Backend auth changes can break all unsafe requests | `HTTPClient` auto-CSRF and refresh-once handling |
| iOS folder media shape | Backend has `mediaItems` and `media.items` shapes in contract | `FolderContentDTO` supports both optional fields |
| Upload API status meanings | Backend relay may be async after upload response | Contract distinguishes upload accepted/completed from Pixel delivery |

## Gaps / Verify
> ⚠️ Undocumented — verify: no versioning policy, deprecation window, contract tests against a live backend, or generated client pipeline was found.
