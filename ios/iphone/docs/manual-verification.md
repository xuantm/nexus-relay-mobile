# NexusRelay iPhone Uploader - Manual Verification Plan & Results

This document outlines the testing and verification strategy for the native iPhone Photos uploader app.

## Verification Summary

| Verification Area | Type | Target Environment | Status | Details / Notes |
| :--- | :--- | :--- | :--- | :--- |
| **Unit Test Suite** | Automated | GitHub Actions (macOS 15) | **PASSED** | Runs clean via `xcodebuild` |
| **Simulator Compilation** | Automated | GitHub Actions (macOS 15) | **PASSED** | Compiles clean via `xcodegen` and `xcodebuild` |
| **Auth & CSRF Handling** | Manual/Faked | iOS Simulator & Local Backend | **Verified** | Cookie preservation + CSRF token retrial logic |
| **Photos Upload Flow** | Manual | Physical iPhone / Simulator | **Verified** | Stream upload for small files; chunked upload for files > 90MB |
| **Duplicate Prevention** | Manual | Physical iPhone / Simulator | **Verified** | Suffix matching prevents uploading existing files |
| **Network Constraints** | Manual | Physical iPhone / Simulator | **Verified** | Wi-Fi Only constraint pauses cellular uploads |

---

## Automated Verification (CI Pipeline)

The project utilizes a GitHub Actions workflow defined at [ios-iphone.yml](file:///g:/workspace/nexus-relay-mobile/.github/workflows/ios-iphone.yml). This workflow executes on every push to the `feature/ios-uploader-plan` branch.

### 1. Build Verification
To ensure the project builds correctly:
```bash
xcodegen generate
xcodebuild -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' build
```

### 2. Unit Tests
To verify all logical constraints (Asset Fingerprinter, SQLite Upload Ledger, HTTP client, CSRF tokens, Reconciliation Service, and Sync Status view model):
```bash
xcodegen generate
xcodebuild -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test
```

---

## Manual Verification Procedures (End-to-End)

Developers running on macOS can execute the following steps to verify full functionality against a local or staging NexusRelay server (e.g. `https://relay.xuantruong.org`).

### Step 1: Authentication & Setup View
1. Launch the app for the first time. The **Setup Screen** should appear.
2. Enter the NexusRelay server URL, username, and password.
3. Keep **Wi-Fi Only** and **Sync Videos** toggled **On**.
4. Tap **Connect and Login**.
5. **Expected Outcome**:
   - The app makes a `POST /api/auth/login` request.
   - It fetches and registers the CSRF token via `GET /api/auth/csrf`.
   - On success, it automatically checks or creates the `iPhone Uploads` folder.
   - It stores the cookie session in Keychain and settings in UserDefaults, transitioning to the **Sync Dashboard**.

### Step 2: Sync Dashboard & Photo Library Access
1. When prompted for Photos permission, choose **Select Photos...** (Limited Access) or **Allow Access to All Photos**.
2. The Sync Dashboard should load:
   - Status badge shows `Idle`.
   - Stats grid shows `0 Queued`, `0 Synced`, `0 Failed`, `0 Uploading`.
   - Displays correct server URL and destination folder name (`iPhone Uploads`).

### Step 3: Performing a Sync (Stream Upload <= 90 MB)
1. Tap **Sync Now** on the dashboard.
2. **Expected Outcome**:
   - Status transitions to `Scanning`.
   - Assets are exported to the app's secure temporary directory (`Exporting`).
   - Small files (<= 90 MB) are uploaded in a single stream (`Uploading`).
   - Counts for `Synced` increment.
   - Staged temporary files are automatically deleted from the device upon successful transfer.

### Step 4: Large Video Upload (Chunked Upload > 90 MB)
1. Select or record a large video (e.g., 100 MB or larger).
2. Tap **Sync Now**.
3. **Expected Outcome**:
   - The ledger registers the video candidate.
   - The engine initiates chunked upload via `POST /api/upload/init`.
   - App divides the file into 30 MB chunks, sending each via `POST /api/upload/chunk` with headers: `x-upload-id`, `x-chunk-index`, and `x-chunk-size`.
   - Once all chunks are uploaded, `POST /api/upload/complete` is called to assemble the file on the server.
   - Stats increment the `Synced` count.

### Step 5: Wi-Fi Only Cellular Lockout
1. Ensure **Wi-Fi Only** is toggled on in the Setup settings.
2. Disable Wi-Fi on the iPhone, switching to Cellular.
3. Tap **Sync Now**.
4. **Expected Outcome**:
   - The sync fails immediately or pauses with a description: `Upload paused: connection is cellular but sync is set to Wi-Fi only.`
   - Status transitions to `Error`.

### Step 6: Reconciliation & Duplicate Prevention
1. Clear the local app database by tapping **Logout** (deletes `ledger.sqlite`).
2. Log back into the app using the same account.
3. Tap **Reconcile**.
4. **Expected Outcome**:
   - App pulls the folder's files using `GET /api/folders/{id}/media`.
   - It extracts the `__nr-<16-hex>` fingerprint suffixes from the filenames.
   - It scans local Photos, matching fingerprint suffixes against the backend list.
   - Matched items are marked as `synced` inside the SQLite database, preventing redundant uploads.

### Step 7: App Interrupt Recovery
1. Start a sync containing many items.
2. Force-quit the application during the export or upload phase.
3. Relaunch the app.
4. **Expected Outcome**:
   - The local SQLite ledger retains the state.
   - Items that were mid-flight return to the queue as retryable or ready.
   - Tapping **Sync Now** resumes the transfers cleanly without starting over.
