---
scope: architecture/system
status: verified
sources:
  - README.md
  - docs/architecture/pixel-companion-sync.md
  - docs/architecture/iphone-photos-uploader.md
  - android/pixel/README.md
  - ios/iphone/README.md
last_verified_commit: c53b326ddc88d1db76b2d958d18eb7daed2e8b28
---

# System Overview

## Summary
| Item | Value |
|---|---|
| Repo type | Native mobile repo with Android and iOS apps |
| Backend source | ⚠️ Undocumented — verify: backend lives in separate `nexus-relay` repo per root README |
| Web frontend source | ⚠️ Undocumented — verify: web app lives outside this repo |
| Database source | Local mobile persistence only; backend database is outside this repo |
| Main contracts | `docs/contracts/device-sync-api.md`, `docs/contracts/iphone-upload-api.md` |

## Detected Layers
| Layer | Status | Path | Evidence |
|---|---|---|---|
| Android mobile app | verified | `android/pixel` | Gradle Kotlin project, Compose UI, Retrofit API, WorkManager, FCM |
| iOS mobile app | verified | `ios/iphone` | XcodeGen SwiftUI project, PhotoKit, Keychain, SQLite, URLSession |
| Shared API contracts | verified | `docs/contracts` | Device sync and iPhone upload contracts |
| Architecture docs | verified | `docs/architecture` | Pixel and iPhone flow docs |
| CI/CD | verified | `.github/workflows` | iOS CI and iOS release artifact workflows |
| Backend implementation | not present | ⚠️ Undocumented — verify | Root README states backend remains in main `nexus-relay` repo |
| Web frontend implementation | not present | ⚠️ Undocumented — verify | Root README states web app remains in main `nexus-relay` repo |
| Infrastructure as code | not found | ⚠️ Undocumented — verify | No Docker, Compose, Kubernetes, Terraform, Helm, or Makefile found |

## Architecture Map
| Unit | Responsibility | Calls / Uses | Called By |
|---|---|---|---|
| Pixel app | Receives NexusRelay device-sync jobs, downloads media, imports into Android MediaStore, confirms jobs | NexusRelay device-sync API, FCM, WorkManager, DataStore, EncryptedSharedPreferences, MediaStore | User, FCM, periodic WorkManager poll |
| iPhone app | Uploads Apple Photos media into NexusRelay folders | NexusRelay auth/folder/upload APIs, Google OAuth browser flow, PhotoKit, Keychain, SQLite, BackgroundTasks | User, iOS BGProcessing |
| NexusRelay backend | External source of API truth and durable server-side queue | Google Drive relay, FCM sender, auth/session endpoints | Both mobile apps |
| Shared docs/contracts | Manual API agreement between mobile repo and backend repo | Mobile DTOs and external backend implementation | Codex/developers |

## Backend / Frontend Detection
No server controllers/routes, web app package manifests, backend migrations, Dockerfiles, or web frontend build files were found in this repo. Do not infer backend or web behavior beyond `docs/contracts` and checked mobile clients.

## Gaps / Verify
> ⚠️ Undocumented — verify: source-of-truth API schema is manual markdown; no OpenAPI/protobuf/GraphQL schema was found.

> ⚠️ Undocumented — verify: production backend deployment, backend database, Google Drive relay internals, and web pairing-code UI are outside this repo.
