---
scope: mobile/ios-iphone
status: verified
sources:
  - ios/iphone/README.md
  - ios/iphone/project.yml
  - ios/iphone/NexusRelayIPhone/Resources/Info.plist
  - ios/iphone/NexusRelayIPhone/App/NexusRelayIPhoneApp.swift
  - ios/iphone/NexusRelayIPhone/Core/API/NexusRelayAPIClient.swift
  - ios/iphone/NexusRelayIPhone/Core/Upload/SyncOrchestrator.swift
last_verified_commit: c53b326ddc88d1db76b2d958d18eb7daed2e8b28
---

# iOS iPhone App

## Summary
| Item | Value |
|---|---|
| Path | `ios/iphone` |
| Project source | `project.yml` via XcodeGen |
| Runtime | Swift 5.10, SwiftUI, iOS deployment target 17.0 |
| Bundle id | `com.nexusrelay.iphone` |
| Local persistence | SQLite via `libsqlite3`, UserDefaults, Keychain |
| Platform integrations | PhotoKit, BackgroundTasks, ASWebAuthenticationSession |
| Upload policy | stream <= 90 MB, chunked > 90 MB, 30 MB chunks, max 3 retries |

## Folder Structure
| Path | Purpose |
|---|---|
| `NexusRelayIPhone/App` | App entrypoint and background task registration. |
| `NexusRelayIPhone/Core/API` | API protocol/client, HTTP transport, DTOs. |
| `NexusRelayIPhone/Core/Auth` | Google auth callback parsing, Keychain session, CSRF token provider. |
| `NexusRelayIPhone/Core/Ledger` | SQLite upload ledger schema and transitions. |
| `NexusRelayIPhone/Core/Photos` | PhotoKit scanning, candidates, thumbnails, fingerprints. |
| `NexusRelayIPhone/Core/Upload` | Sync orchestration, export, chunking, temp files, reconciliation. |
| `NexusRelayIPhone/Features` | SwiftUI setup, sync, queue, settings, status views/models. |
| `NexusRelayIPhoneTests` | XCTest coverage for API, auth, ledger, upload, setup, settings, sync status. |

## Canonical Facts
| Fact | Source |
|---|---|
| Setup completion requires backend URL, destination folder id, and Photos access. | `App/NexusRelayIPhoneApp.swift` |
| Google sign-in uses `ASWebAuthenticationSession` against `api/auth/google/login?client=ios`. | `Core/Auth/GoogleAuthCoordinator.swift` |
| Session exchange uses `POST api/auth/ios/session-exchange`. | `Core/API/NexusRelayAPIClient.swift` |
| Unsafe HTTP methods receive `X-NexusRelay-CSRF`. | `Core/API/HTTPClient.swift`, `Core/Auth/CSRFTokenProvider.swift` |
| Local upload ledger table is `upload_ledger`. | `Core/Ledger/SQLiteUploadLedger.swift` |
| Background task id is `com.nexusrelay.iphone.sync`. | `Resources/Info.plist`, `App/AppDelegate.swift` |

## Change Safely
| Change | Inspect | Verification |
|---|---|---|
| Project settings/files | `project.yml`, `NexusRelayIPhone.xcodeproj` | `xcodegen generate --spec project.yml` |
| API/auth | `Core/API/*`, `Core/Auth/*`, API/auth tests | `xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/NexusRelayAPIClientTests` |
| Ledger schema/states | `Core/Ledger/*`, ledger tests | `xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/SQLiteUploadLedgerTests` |
| Upload/retry/chunking | `Core/Upload/*`, upload tests | `xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/UploadEngineTests` |
| PhotoKit behavior | `Core/Photos/*`, manual device verification | simulator tests plus real-device Photos/iCloud checks |

## Gaps / Verify
> ⚠️ Undocumented — verify: App Store/TestFlight signing and provisioning are not configured; release workflow intentionally creates unsigned artifacts.

> ⚠️ Undocumented — verify: iCloud-only Photos and background continuation require physical-device verification.
