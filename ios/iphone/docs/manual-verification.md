# NexusRelay iPhone Uploader - Manual Verification Plan & Results

This document outlines the testing and verification strategy for the native iPhone Photos uploader app.

## Verification Summary

| Verification Area | Type | Target Environment | Status | Details / Notes |
| :--- | :--- | :--- | :--- | :--- |
| **Unit Test Suite** | Automated | GitHub Actions (macOS 15) | **NOT RUN IN THIS REPO SESSION** | Intended command is `xcodebuild ... test`; verify on macOS or CI |
| **Simulator Compilation** | Automated | GitHub Actions (macOS 15) | **NOT RUN IN THIS REPO SESSION** | Intended command is `xcodegen generate` + `xcodebuild ... build` |
| **Auth & CSRF Handling** | Manual/Faked | iOS Simulator & Local Backend | **PLANNED** | Covered by code/tests, but still needs a real verification pass |
| **Photos Upload Flow** | Manual | Physical iPhone / Simulator | **PLANNED** | Requires device/simulator run against a live NexusRelay deployment |
| **Duplicate Prevention** | Manual | Physical iPhone / Simulator | **PLANNED** | Requires reconciliation test against real backend folder data |
| **Network Constraints** | Manual | Physical iPhone / Simulator | **PLANNED** | Requires controlled Wi-Fi/cellular switching on device |

---

## Automated Verification (CI Pipeline)

The project utilizes a GitHub Actions workflow defined at `/.github/workflows/ios-iphone.yml`. Use that workflow on a macOS runner to verify the commands below.

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

### Apple Photos Native UI Checks

1. First launch opens the `NexusRelay` setup checklist.
2. Setup rows show `Server`, `Sign in`, `Photos Access`, and `Destination Folder`.
3. Completing setup opens the three-tab shell: `Sync`, `Queue`, and `Settings`.
4. `Library Sync` shows a photo mosaic, progress text, a progress bar, and a primary `Sync` action.
5. `Queue` shows segmented filters for `All`, `Active`, and `Failed`.
6. `Settings` shows account, server, destination folder, Photos access, and sync toggles.
7. The app uses a light Apple-style UI, not the old dark gradient dashboard.

### Blocked State Checks

1. With Wi-Fi only enabled on cellular, the sync home should show `Waiting for Wi-Fi` or trigger a cellular-lockout error description.
2. With expired auth cookies, the app should pause sync, show `Sign in required`, and offer `Repair Sign-In`.
3. With failed rows in the queue, the `Failed` filter should expose `Retry all`.

### Step 1: Authentication & Setup View
1. Launch the app for the first time. The **Setup Screen** checklist should appear.
2. Enter the NexusRelay server URL (e.g. `https://relay.xuantruong.org`).
3. Keep **Wi-Fi Only** and **Sync Videos** toggled **On**.
4. Tap **Continue with Google**.
5. **Expected Outcome**:
   - The app opens a system browser session (`ASWebAuthenticationSession`) pointing to the backend's Google OAuth page.
   - Complete Google login. If the user is pending admin approval, the browser redirects back to `nexusrelay://auth/pending` and the app displays the pending message: "Access request sent. An admin must approve this Google account before uploads can start."
   - If the user is approved, the browser redirects back to `nexusrelay://auth/success?code=...` with a one-time session exchange code. The app captures it, exchanges it for session cookies, saves the session, and proceeds.
   - The checklist rows update: `Server` host updates, `Sign in` displays the user's Google email (e.g. `Google: user@gmail.com`), `Photos Access` prompts and updates to `Full access`/`Limited access`, `Destination Folder` shows the folder name.
   - On login success, Keychain and settings are updated and the view routes to the three-tab **App Shell**.

### Step 2: Tab Navigation & App Shell
1. Navigate between **Sync**, **Queue**, and **Settings** tabs at the bottom.
2. **Expected Outcome**:
   - The selected tab lights up in the primary accent color.
   - Headers and content switch smoothly.

### Step 3: Performing a Sync
1. Tap **Sync** on the `Library Sync` tab.
2. **Expected Outcome**:
   - The progress percentage text and bar update reactively.
   - Recent photos load in the Photo Mosaic grid dynamically.
   - While active, the primary action changes from **Sync** to **Pause**.
   - The `Queue` list registers items, showing preparing and upload progress.
   - Synced items automatically clear out from active queues.

### Step 4: Settings & Preferences
1. Tap the **Settings** tab.
2. Toggle **Wi-Fi Only** or **Include Videos** on/off.
3. **Expected Outcome**:
   - Toggles persist instantly to UserDefaults.
   - Tapping **Sign out** deletes cookies, deletes `ledger.sqlite`, and brings the user back to the Setup checklist.

### Step 5: Failed Queue Row Retries
1. With failed items present in the upload queue:
2. Tap the **Failed** segment filter in the **Queue** tab.
3. Tap **Retry all** or the retry icon next to a failed item.
4. **Expected Outcome**:
   - The items return to `Waiting to upload` (discovered) status in the ledger, with attempt counts reset to 0.
   - The item reload immediately refreshes in the list.
   - Tapping a queue row opens a detail sheet with status, size, upload mode, destination, and retry action.

