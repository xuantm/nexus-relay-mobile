---
scope: mobile/build-signing
status: partial
sources:
  - android/pixel/README.md
  - android/pixel/app/build.gradle.kts
  - ios/iphone/README.md
  - ios/iphone/project.yml
  - .github/workflows/ios-iphone-release.yml
last_verified_commit: c53b326ddc88d1db76b2d958d18eb7daed2e8b28
---

# Build And Signing

## Android
| Item | Value |
|---|---|
| Debug build | `cd android/pixel && ./gradlew.bat assembleDebug` |
| Install | `adb install -r app/build/outputs/apk/debug/app-debug.apk` |
| Default backend | `https://relay.xuantruong.org` |
| Release backend URL field | hidden via `SHOW_BACKEND_URL_FIELD=false` |
| FCM config | optional local `android/pixel/app/google-services.json` |
| Signing | ⚠️ Undocumented — verify: no release keystore config found |
| Distribution | README/architecture mention sideloaded debug/internal APK for MVP |

## iOS
| Item | Value |
|---|---|
| Project generation | `cd ios/iphone && xcodegen generate --spec project.yml` |
| Simulator build | `xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' build` |
| Release workflow | `.github/workflows/ios-iphone-release.yml` |
| CI runner | `macos-15`, Xcode 16.4 |
| Release artifacts | simulator app zip and unsigned device `.xcarchive` |
| Code signing | workflow sets `CODE_SIGNING_ALLOWED=NO`; README says not TestFlight-ready |
| Development team | `DEVELOPMENT_TEAM: 55PLL367DQ` in `project.yml` |

## Do Not Store
| Secret / Artifact | Rule |
|---|---|
| Android keystores, `keystore.properties`, Firebase service accounts | ignored by `.gitignore`; never commit |
| `google-services.json` | local-only for FCM; never commit |
| iOS provisioning profiles/certificates/App Store Connect credentials | ⚠️ Undocumented — verify storage; never commit |
| Generated APK/AAB/app archives | keep as local/CI artifacts |

## Gaps / Verify
> ⚠️ Undocumented — verify: no Android release workflow, Play Store track, fastlane config, iOS signing export options, TestFlight pipeline, or production deployment checklist was found.
