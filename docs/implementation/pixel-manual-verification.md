# Pixel Companion App Manual Verification Guide

This guide details how to perform manual integration testing for the Pixel companion application.

## Prerequisites

1. Run a local or staging NexusRelay backend.
2. Have a physical Android device or emulator connected via ADB.

---

## Test Scenarios

### Scenario 1: Device Registration

1. Build and install the APK:
   ```bash
   cd android/pixel
   ./gradlew assembleDebug
   adb install -r app/build/outputs/apk/debug/app-debug.apk
   ```
2. Open the **NexusRelay Pixel** app.
3. Observe that the **Register Device** setup screen is shown.
4. Enter your backend URL (e.g. `https://my-nexus-relay-server.com`) and device name (e.g. `Pixel Emulator`).
5. Tap **Register**.
6. Verify:
   - A success message appears on screen.
   - The app transitions to the **Status Screen**.
   - Under Settings, verify the Backend URL, Device Name, and Target ID are populated.

### Scenario 2: Manual Sync Test

1. From the Status Screen, observe that the confirmed sync count is `0`.
2. Upload a test image file on the NexusRelay server.
3. Tap **Sync Now** in the app.
4. Verify:
   - The status badge changes to `Downloading` for the new job, then `ConfirmPending`, and finally `Confirmed`.
   - The confirmed sync count increases by `1`.
   - The job details appear under **Sync Ledger** with a green `Confirmed` status.
   - Open the phone's gallery app or file manager and verify that the image is saved under the `Pictures/NexusRelay` directory.

### Scenario 3: FCM Wake-up Test

1. Configure `google-services.json` inside the app.
2. Put the app in the background.
3. Upload a new image to the NexusRelay server.
4. Verify that FCM triggers an immediate background task execution.
5. Bring the app to the foreground and verify that the image was downloaded and imported automatically, and is listed under the Sync Ledger.

### Scenario 4: Polling Fallback Test

1. If Firebase is not configured or push notifications are offline, upload a media file on the server.
2. Leave the device idle for 15 minutes.
3. Verify that the `PollWorker` triggers background sync and the new media item is downloaded and imported successfully.

### Scenario 5: Retry & Duplicate Prevention Test

1. Start downloading a large video file.
2. Disconnect the device network connection mid-download.
3. Verify:
   - The job is NOT marked as `Failed` in the ledger (its status remains `Downloading` or `Queued`), and the transient network failure is thrown to trigger retry.
   - Re-enable the network and click **Sync Now** (or wait for the WorkManager retry).
   - Verify that the sync resumes, downloads, and imports successfully, without generating duplicate media entries in the MediaStore.
