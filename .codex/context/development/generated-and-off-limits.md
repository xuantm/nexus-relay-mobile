---
scope: development/generated-and-off-limits
status: verified
sources:
  - .gitignore
  - android/pixel/.gitignore
  - ios/iphone/project.yml
  - android/pixel/app/build.gradle.kts
  - fix_endpoints.py
  - window_dump.xml
last_verified_commit: c53b326ddc88d1db76b2d958d18eb7daed2e8b28
---

# Generated And Off-Limits

## Generated / Derived
| Path | Source of truth | Rule |
|---|---|---|
| `ios/iphone/NexusRelayIPhone.xcodeproj` | `ios/iphone/project.yml` | Prefer editing `project.yml` and regenerating with XcodeGen. |
| `android/pixel/app/build/`, `android/pixel/build/` | Gradle | Do not edit or commit generated build outputs. |
| `artifacts/` | local generated artifacts | Do not treat as source unless user explicitly asks. |
| `window_dump.xml` | captured Android UI dump | Do not treat as current UI source. |

## Secrets / Local Files
| Path/pattern | Rule |
|---|---|
| `android/pixel/app/google-services.json` | local FCM config; ignored; never commit |
| `*.jks`, `*.keystore`, `keystore.properties` | signing secrets; ignored; never commit |
| `firebase-service-account.json` | secret; ignored; never commit |
| `local.properties` | local Android SDK path/config; ignored; never commit |
| iOS provisioning/cert/keychain/cookie data | never print, copy into context, or commit |

## Risky Utility
| Path | Risk |
|---|---|
| `fix_endpoints.py` | Hard-coded helper that edits `/workspace/nexus-relay/backend/src/NexusRelay.Backend.Api/Endpoints/DeviceSyncEndpoints.cs` outside this repo; do not run unless explicitly requested and the external backend path is verified. |

## Stale Docs / Captures
| Path | Note |
|---|---|
| `window_dump.xml` | Shows older Android setup text (`Register Device`) that may not match current Compose source. |
| `ios/iphone/docs/manual-verification.md` | Mentions `/.github/workflows/ios-iphone.yml`, but actual workflow files are `ios-iphone-ci.yml` and `ios-iphone-release.yml`. |
| `docs/implementation/*`, `docs/superpowers/*` | Planning/spec artifacts; useful history but verify against current source before using as facts. |

## Change Safely
| Change | Required care |
|---|---|
| Generated project/build files | Regenerate from source config; do not hand-edit generated output unless unavoidable. |
| Contract docs | Cross-check with mobile DTOs/tests and external backend repo. |
| External backend helper scripts | Confirm target path, repo, branch, and user intent before running. |
