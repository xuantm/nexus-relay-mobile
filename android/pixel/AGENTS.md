# AGENTS.md - Android Pixel

Root rules still apply: see `../../AGENTS.md`.

## Commands
```bash
./gradlew.bat assembleDebug
./gradlew.bat testDebugUnitTest
./gradlew.bat connectedDebugAndroidTest
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

## Local Rules
- Keep `google-services.json`, keystores, and `local.properties` out of git.
- Pairing/auth changes must preserve `X-Device-Token` sync behavior and encrypted token storage.
- WorkManager, FCM, ledger, MediaStore import, and cleanup changes should include focused unit tests or instrumented tests where applicable.

## Context
Relevant context starts at `../../.codex/context/index.md`, especially `mobile/android-pixel.md`, `contracts/api-contracts.md`, `database/local-persistence.md`, and `messaging/*`.
