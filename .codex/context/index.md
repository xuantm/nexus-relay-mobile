---
scope: context/index
status: verified
sources:
  - README.md
  - android/pixel/README.md
  - ios/iphone/README.md
  - .github/workflows/ios-iphone-ci.yml
  - .github/workflows/ios-iphone-release.yml
last_verified_commit: c53b326ddc88d1db76b2d958d18eb7daed2e8b28
---

# Codex Context Index

| File | Scope | Read when | Canonical facts | Status | Sources |
|---|---|---|---|---|---|
| `architecture/system-overview.md` | system | Understanding repo purpose, layers, and missing backend/web source | mobile-only repo, external backend boundary, major flows | verified | `README.md`, `docs/architecture/*`, `android/pixel/README.md`, `ios/iphone/README.md` |
| `architecture/service-map.md` | architecture/services | Locating deployable apps and external dependencies | Android app, iOS app, external NexusRelay backend, FCM | partial | `README.md`, `android/pixel/settings.gradle.kts`, `ios/iphone/project.yml`, `.github/workflows/*` |
| `architecture/cross-layer-flows.md` | architecture/flows | Tracing Pixel receive and iPhone upload flows end to end | setup, auth, sync, upload, reconciliation paths | partial | `docs/architecture/*`, mobile API/sync/upload source |
| `mobile/android-pixel.md` | mobile/android | Changing Android Pixel app behavior | Kotlin modules, commands, app startup, sync worker, storage | verified | `android/pixel/README.md`, `android/pixel/app/build.gradle.kts`, Android source files |
| `mobile/ios-iphone.md` | mobile/ios | Changing iPhone uploader behavior | SwiftUI modules, XcodeGen, auth, upload, ledger, background tasks | verified | `ios/iphone/README.md`, `ios/iphone/project.yml`, iOS source files |
| `mobile/build-signing.md` | mobile/release | Building, installing, and release artifact work | Android debug APK, iOS CI artifacts, unsigned iOS archive | partial | `android/pixel/README.md`, `ios/iphone/README.md`, `.github/workflows/ios-iphone-release.yml` |
| `contracts/api-contracts.md` | contracts/api | Modifying backend API DTOs, endpoints, or client calls | device sync endpoints, iPhone auth/folder/upload endpoints, status vocabulary | partial | `docs/contracts/*.md`, mobile API clients |
| `contracts/compatibility.md` | contracts/compatibility | Assessing contract changes and rollout safety | manual contract duplication, no OpenAPI source, backward compatibility rules | partial | `docs/contracts/*.md`, `android/pixel/app/src/main/java/com/nexusrelay/pixel/api/*`, `ios/iphone/NexusRelayIPhone/Core/API/*` |
| `database/local-persistence.md` | database/local | Changing local state, ledgers, retries, settings, or data recovery | Android DataStore ledger/settings, encrypted token store, iOS SQLite ledger, UserDefaults, Keychain | verified | Android storage/auth files, iOS ledger/settings/auth files |
| `integrations/external-systems.md` | integrations | Touching external systems or platform services | NexusRelay backend, Firebase FCM, Google auth, PhotoKit, MediaStore, Google Drive boundary | partial | README/docs, manifest/plist, mobile integration source |
| `messaging/topology.md` | messaging/topology | Changing push signals, background work, polling, or BGProcessing | FCM signal plus WorkManager pull, iOS BGProcessing recovery | partial | `docs/architecture/pixel-companion-sync.md`, `FcmReceiverService.kt`, `SyncWorker.kt`, `PollWorker.kt`, iOS background files |
| `messaging/failure-handling.md` | messaging/failures | Changing retry, recovery, idempotency, or duplicate handling | WorkManager retry, local confirmation retry, upload retry, ledger recovery | partial | Android sync/storage files, iOS upload/ledger/reconciliation files |
| `infra/pipelines.md` | infra/ci-cd | Changing CI/CD, workflow gates, or deployment docs | iOS CI/release workflows, no Android CI found | verified | `.github/workflows/ios-iphone-ci.yml`, `.github/workflows/ios-iphone-release.yml` |
| `security/auth-and-data-protection.md` | security | Changing auth, tokens, cookies, permissions, sensitive storage, or upload/download boundaries | Pixel device token, iOS cookies/CSRF, Google auth, Keychain, encrypted prefs, no direct Drive access | partial | contract docs, auth/storage files, manifest/plist |
| `testing/verification-matrix.md` | testing | Choosing checks before completion | focused Android/iOS/contract/manual verification commands | partial | READMEs, test file tree, CI workflows |
| `development/generated-and-off-limits.md` | development/safety | Avoiding generated, local, secret, or risky files | generated project/build outputs, secret files, stale helper risks | verified | `.gitignore`, Android `.gitignore`, project files, `fix_endpoints.py`, `window_dump.xml` |

## Repository State Note
The working tree had uncommitted Android, iOS, contract, and superpowers doc changes when this context was generated. Treat source facts as verified from the working tree, not only from the commit listed above.
