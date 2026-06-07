# NexusRelay Pixel Companion App

This is the Android Pixel companion app for receiving media sync jobs from the NexusRelay backend, downloading them, and importing them into the Android MediaStore.

Release builds default to https://relay.xuantruong.org. Debug builds keep the backend URL field visible for local testing.

## Features

- **Setup & Device Registration**: Simple Compose UI to pair the device using a temporary pairing code (or QR code payload) generated from the NexusRelay web interface.
- **Secure Token Storage**: Persists device sync API keys using AndroidX Security EncryptedSharedPreferences.
- **Local Ledger**: Prevents duplicate downloads and keeps sync state histories.
- **Background Worker**: Jetpack WorkManager-driven downloads with retry-on-network-failure.
- **FCM Push Notification**: Listens for wake-up push signals from Firebase to execute background sync tasks instantly.
- **Fallback Polling**: Periodic polling backup tasks scheduled every 15 minutes to guarantee sync even if push notifications are dropped.

## Tech Stack

- **Language**: Kotlin
- **Build System**: Gradle 9.1 (Kotlin DSL) with Version Catalogs
- **UI**: Jetpack Compose (Material 3)
- **Background Tasks**: WorkManager
- **Networking**: Retrofit, OkHttp, Moshi
- **Push Messaging**: Firebase Cloud Messaging (FCM)
- **Security**: EncryptedSharedPreferences

## Getting Started

### Prerequisites

- Java Development Kit (JDK) 17+ or 21+
- Android SDK installed (Target API 36)

### Firebase Cloud Messaging (FCM) Setup

1. Create a Firebase project in the Firebase Console.
2. Register the Android app with the package name: `com.nexusrelay.pixel`.
3. Download the generated `google-services.json` file.
4. Place `google-services.json` inside the `app/` directory (`android/pixel/app/google-services.json`).
5. When `google-services.json` is present, the build automatically applies the Google Services Gradle plugin so Firebase can initialize and issue an FCM token during device registration.
6. (Optional) For development/local builds where FCM is not needed, you can build without adding Firebase, but background notifications will not be received. Polling and manual sync will still function.

### Build and Run

To compile and assemble the debug APK:

```bash
cd android/pixel
./gradlew assembleDebug
```

To run unit tests:

```bash
./gradlew test
```

### Installation

Install the debug APK on a connected emulator or physical device via ADB:

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

## Device Pairing Flow

Instead of requiring user account credentials (username/password) on the mobile device, registration uses a short-lived pairing code flow:

1. **Generate Pairing Code**: Log in to the NexusRelay web client and generate a temporary pairing code / QR code.
2. **Setup on Device**: Open the Pixel app. In the setup screen, enter the pairing code (or scan the QR code payload) and the device name. The backend URL can be specified if it is a debug build.
3. **Redeem**: The app sends a request to the backend to redeem the code.
4. **Token Storage**: Upon successful validation, the backend returns a unique `deviceToken` and configuration settings (e.g. `wifiOnly`, `syncScope`). The app stores the token in encrypted storage.
5. **Sync**: All future sync operations use the revocable `X-Device-Token` header.

