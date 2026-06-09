---
scope: integrations/external-systems
status: partial
sources:
  - README.md
  - docs/architecture/pixel-companion-sync.md
  - docs/architecture/iphone-photos-uploader.md
  - android/pixel/app/src/main/AndroidManifest.xml
  - ios/iphone/NexusRelayIPhone/Resources/Info.plist
  - android/pixel/app/src/main/java/com/nexusrelay/pixel/sync/FcmReceiverService.kt
  - ios/iphone/NexusRelayIPhone/Core/Auth/GoogleAuthCoordinator.swift
last_verified_commit: c53b326ddc88d1db76b2d958d18eb7daed2e8b28
---

# External Systems

## Integration Map
| System | Used by | Purpose | Source / Config |
|---|---|---|---|
| NexusRelay backend | Android + iOS | Pairing, device sync, auth, folders, uploads | `docs/contracts/*.md`, API clients |
| Firebase Cloud Messaging | Android | Wake-up signal and FCM token registration | `FcmReceiverService.kt`, `FcmTokenSync.kt`, manifest service |
| Android MediaStore | Android | Store downloaded images/videos | `MediaStoreImporter.kt` |
| Google OAuth through NexusRelay | iOS | User sign-in via system browser | `GoogleAuthCoordinator.swift` |
| Apple PhotoKit | iOS | Scan and export user photos/videos | `PhotoKitPhotoLibraryClient.swift`, `PhotoKitAssetExporter.swift` |
| iOS BackgroundTasks | iOS | Background sync attempts | `Info.plist`, `AppDelegate.swift`, `BackgroundSyncScheduler.swift` |
| Google Drive | Backend only | Backend relay storage | Mobile docs explicitly say mobile apps must not call it directly |

## Configuration / Secrets
| Integration | Config | Secret handling |
|---|---|---|
| Android FCM | `android/pixel/app/google-services.json` | ignored; local-only; do not commit |
| Android backend URL | BuildConfig default + optional debug setup field | URL is non-secret |
| iOS backend URL | `AppSettings.defaults` and setup settings | URL is non-secret |
| iOS Google auth | backend URL + browser redirect | mobile stores cookies, not Google tokens |
| iOS Keychain | service `com.nexusrelay.iphone.session` | stores cookie session material |

## Gaps / Verify
> ⚠️ Undocumented — verify: FCM server sender, Firebase project identifiers, Google OAuth client configuration, backend auth settings, and Google Drive relay credentials are outside this repo.

> ⚠️ Undocumented — verify: no local emulator/service-compose topology was found.
