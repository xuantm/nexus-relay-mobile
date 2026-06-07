# iOS Google Login And Fixed Backend Plan

Date: 2026-06-07

## Goal

Move the iOS iPhone app from manual server URL plus username/password setup to Google account login, using the fixed backend:

`https://relay.xuantruong.org`

The backend URL must not be editable or shown in the UI.

Android Pixel is explicitly out of scope for this plan.

## Current iOS State

- Setup UI asks for `Server`, `Username`, and `Password`.
- `AppSettings.backendBaseURL` is optional and is used to decide whether setup is complete.
- API clients are created from the saved `backendBaseURL`.
- Auth uses cookie-based backend session stored through `CookieSessionStore`.
- Unsafe requests use `/api/auth/csrf` and `X-NexusRelay-CSRF`.
- Settings UI currently shows `Server`.
- Background sync fails if `settings.backendBaseURL` is missing.

Relevant files:

- `ios/iphone/NexusRelayIPhone/Features/Setup/SetupView.swift`
- `ios/iphone/NexusRelayIPhone/Features/Setup/SetupViewModel.swift`
- `ios/iphone/NexusRelayIPhone/Features/Setup/SetupChecklistModels.swift`
- `ios/iphone/NexusRelayIPhone/Features/Settings/SettingsView.swift`
- `ios/iphone/NexusRelayIPhone/Features/Settings/SettingsViewModel.swift`
- `ios/iphone/NexusRelayIPhone/App/NexusRelayIPhoneApp.swift`
- `ios/iphone/NexusRelayIPhone/App/AppDelegate.swift`
- `ios/iphone/NexusRelayIPhone/Core/API/NexusRelayAPIClient.swift`
- `ios/iphone/NexusRelayIPhone/Core/API/HTTPClient.swift`
- `ios/iphone/NexusRelayIPhone/Core/Auth/AuthSession.swift`
- `ios/iphone/NexusRelayIPhone/Core/Auth/CookieSessionStore.swift`
- `ios/iphone/NexusRelayIPhone/Core/Utilities/AppSettings.swift`
- `ios/iphone/NexusRelayIPhone/Core/Utilities/SettingsStore.swift`

## Backend Contract Needed

The backend already exposes web Google login at:

`GET /api/auth/google/login`

That endpoint redirects to Google and returns to:

`/api/auth/google/callback`

For native iOS, the app cannot directly use HttpOnly cookies created inside the browser login session. The backend needs a mobile bridge so the app can complete Google login and receive a session in the app's own networking context.

### Recommended Backend Flow

1. iOS starts login with `ASWebAuthenticationSession`.
2. App opens:

   `GET /api/auth/google/login?mobile=ios&redirect_uri=nexusrelay%3A%2F%2Fauth%2Fgoogle%2Fcallback&state=<state>`

3. Backend performs normal Google OAuth.
4. Backend callback validates Google OAuth result.
5. Backend creates a short-lived one-time mobile login code.
6. Backend redirects browser to:

   `nexusrelay://auth/google/callback?code=<one_time_code>&state=<state>`

7. iOS receives callback URL.
8. iOS calls backend exchange endpoint from `URLSession`:

   `POST /api/auth/mobile/google/exchange`

9. Backend validates one-time code and returns the normal authenticated user response. The response also sets auth cookies for `relay.xuantruong.org`.
10. iOS stores those cookies in `CookieSessionStore` and continues using the existing cookie plus CSRF API client.

This keeps iOS upload/folder API changes small because the existing client already supports backend cookies and CSRF.

### Backend Endpoint 1: Start Google Login

Method:

`GET /api/auth/google/login`

Required mobile query parameters:

- `mobile=ios`
- `redirect_uri=nexusrelay://auth/google/callback`
- `state=<opaque_random_state_from_ios>`

Expected behavior:

- Continue using Google OAuth provider.
- Preserve the mobile redirect URI and state through the Google callback.
- After successful Google auth, do not finish with a web-only cookie page for mobile.
- Create a one-time exchange code and redirect to the iOS custom scheme.

Success redirect:

`302 nexusrelay://auth/google/callback?code=<one_time_code>&state=<same_state>`

Failure redirect:

`302 nexusrelay://auth/google/callback?error=<code>&error_description=<short_message>&state=<same_state>`

Security requirements:

- `state` must round-trip unchanged.
- `one_time_code` should expire quickly, recommended 2 minutes.
- `one_time_code` must be single-use.
- Store code server-side hashed if practical.
- Bind code to user ID and expected platform `ios`.

### Backend Endpoint 2: Exchange Mobile Code

Method:

`POST /api/auth/mobile/google/exchange`

Request:

```json
{
  "code": "one_time_code_from_callback",
  "state": "same_state_generated_by_ios",
  "platform": "ios"
}
```

Success response:

Status:

`200 OK`

Headers:

- `Set-Cookie: <normal backend auth cookie>; HttpOnly; Secure; SameSite=None|Lax`
- `Set-Cookie: <refresh cookie if backend uses one>; HttpOnly; Secure; SameSite=None|Lax`

Body:

```json
{
  "id": "user_uuid",
  "username": "display_or_google_username",
  "email": "user@example.com",
  "role": "User"
}
```

Error responses:

- `400` for missing code/state/platform.
- `401` for invalid, expired, or already used code.
- `409` if Google account is valid but not allowed to create/use a NexusRelay account.
- `500` only for unexpected server errors.

Important:

- The response must set cookies on the exchange response itself, because that request is made by the native app.
- Cookies set only during the browser OAuth flow are not enough for `URLSession`.

### Existing Backend Endpoints iOS Still Needs

These can stay as-is if they already work with the exchanged cookie session:

- `GET /api/auth/me`
- `POST /api/auth/refresh`
- `POST /api/auth/csrf`
- `GET /api/folders`
- `POST /api/folders`
- `GET /api/folders/{folderId}/media`
- `POST /api/upload/stream`
- `POST /api/upload/init`
- `POST /api/upload/chunk`
- `POST /api/upload/complete`

Optional but useful:

- `POST /api/auth/logout`

## iOS Implementation Plan

### Phase 1: Fixed Backend Environment

Create a central environment file:

`ios/iphone/NexusRelayIPhone/Core/Utilities/AppEnvironment.swift`

Content:

- `static let backendBaseURL = URL(string: "https://relay.xuantruong.org")!`
- Optional constants for OAuth callback scheme and callback URL.

Update all iOS API construction to use `AppEnvironment.backendBaseURL`:

- `SetupViewModel`
- `AppDelegate.resolveSyncOrchestrator`
- Any folder picker or sync code that reads `settings.backendBaseURL`

Keep `AppSettings.backendBaseURL` temporarily for backward-compatible decoding, but stop writing and reading it for active behavior.

Later cleanup can remove the property after migrations are stable.

### Phase 2: App Setup Completion Logic

Current setup complete check:

- backend URL exists
- destination folder exists
- photos access exists

New setup complete check:

- valid `AuthSession` exists
- destination folder exists
- photos access exists

Update:

- `NexusRelayIPhoneApp`
- setup tests
- settings tests

Recommended helper:

`AppSetupStateResolver`

Inputs:

- `SettingsStore`
- `SessionStore`
- `PhotoLibraryClient`

Output:

- `isSetupComplete: Bool`

This keeps the setup completion rule testable and avoids duplicating logic.

### Phase 3: Google Auth Service

Add:

`ios/iphone/NexusRelayIPhone/Core/Auth/GoogleAuthService.swift`

Responsibilities:

- Generate cryptographically random `state`.
- Build login URL:

  `https://relay.xuantruong.org/api/auth/google/login?mobile=ios&redirect_uri=nexusrelay://auth/google/callback&state=<state>`

- Start `ASWebAuthenticationSession`.
- Receive callback URL for `nexusrelay://auth/google/callback`.
- Validate callback state.
- Handle `error` callback values.
- Call `POST /api/auth/mobile/google/exchange`.
- Save cookies from exchange response into `CookieSessionStore`.
- Return `AuthSession`.

Implementation notes:

- Use `AuthenticationServices`.
- Set `callbackURLScheme = "nexusrelay"`.
- Prefer `prefersEphemeralWebBrowserSession = false` so the user can reuse Google login state.
- Use `URLComponents` for query construction and parsing.
- Keep the service behind a protocol for tests.

Suggested protocol:

```swift
protocol GoogleAuthServicing {
    func signInWithGoogle() async throws -> AuthSession
}
```

### Phase 4: API Client Auth Additions

Add an API method for mobile Google exchange:

```swift
func exchangeGoogleMobileCode(code: String, state: String) async throws -> AuthSession
```

This can live in `SystemNexusRelayAPIClient` or a focused `GoogleAuthExchangeClient`.

Recommended request:

`POST api/auth/mobile/google/exchange`

After response:

- Decode `BrowserAuthResponse`.
- Read response cookies from headers for `AppEnvironment.backendBaseURL`.
- If headers do not expose cookies but `HTTPCookieStorage` has them, use storage fallback.
- Save `AuthSession`.

Do not remove existing username/password `login` method immediately if tests or internal mocks still rely on it. Mark it as legacy and stop using it from setup UI.

### Phase 5: iOS URL Scheme

Update:

`ios/iphone/NexusRelayIPhone/Resources/Info.plist`

Add URL type:

- Scheme: `nexusrelay`
- Role: Editor

The callback URL will be:

`nexusrelay://auth/google/callback`

No associated domain is required for the first implementation because `ASWebAuthenticationSession` supports custom URL schemes.

### Phase 6: Setup UI

Update:

- `SetupView`
- `SetupViewModel`
- `SetupChecklistModels`

Remove from UI:

- Server field
- Username field
- Password field
- Password storage hint

Add:

- `Continue with Google` button
- Loading state: `Signing in...`
- Error display for cancelled login, invalid state, exchange failure, backend unavailable

Checklist rows should become:

- Account: pending/complete based on `sessionStore.currentSession`
- Photos Access: existing behavior
- Destination Folder: existing behavior

Remove `Server` checklist row.

Setup flow after Google login:

1. Run Google sign-in.
2. Save auth session.
3. Call `listRootFolders`.
4. Create or reuse destination folder named `iPhone Uploads`.
5. Save `destinationFolderId`.
6. Request Photos permission.
7. Mark setup complete.

### Phase 7: Settings UI

Update:

- `SettingsView`
- `SettingsViewModel`

Remove:

- `Server` row
- `serverURLString`

Keep:

- Account
- Destination Folder
- Photos Access
- Wi-Fi Only
- Include Videos
- Live Photo Video
- Sign out

Sign out behavior:

- Clear `CookieSessionStore`.
- Clear destination folder ID if we want setup to force account/folder revalidation.
- Keep sync preferences.
- Optional: call backend `POST /api/auth/logout` if endpoint exists.

### Phase 8: Settings Migration

Keep decoding older settings that include `backendBaseURL`.

When saving settings after this change:

- Do not set `backendBaseURL`.
- Do not show or validate old server URL values.

If an old user had a valid destination folder but no session:

- App should show setup and ask Google login.

If an old user has a session and destination folder:

- App can enter main shell after Photos permission check.

### Phase 9: Background Sync

Update:

`AppDelegate.resolveSyncOrchestrator`

Change:

- Stop reading `settings.backendBaseURL`.
- Always use `AppEnvironment.backendBaseURL`.
- Still require session cookies and destination folder as part of sync startup.

Expected behavior:

- Missing auth session should fail gracefully and leave app requiring setup/login when opened.
- Missing destination folder should fail with existing setup-required behavior.

### Phase 10: Tests

Update existing tests:

- `NexusRelayIPhoneTests/Setup/SetupChecklistModelTests.swift`
- `NexusRelayIPhoneTests/Settings/SettingsViewModelTests.swift`
- `NexusRelayIPhoneTests/Utilities/SettingsStoreTests.swift`
- Any tests assuming `backendBaseURL` is required.

Add tests:

- Google auth URL includes fixed backend, mobile flag, redirect URI, and state.
- Callback rejects missing code.
- Callback rejects state mismatch.
- Exchange saves cookies into `CookieSessionStore`.
- Setup completion requires auth session, folder, and Photos permission.
- Settings no longer exposes backend URL.
- Background sync creates API client using fixed backend URL.

Manual verification:

1. Fresh install opens setup.
2. Tap `Continue with Google`.
3. Google login opens in browser session.
4. Successful login returns to app.
5. App creates or finds `iPhone Uploads`.
6. App requests Photos permission.
7. App enters main shell.
8. Settings does not show backend URL.
9. Relaunch keeps signed-in state.
10. Sign out returns to setup.

## Implementation Order

1. Add `AppEnvironment`.
2. Add backend exchange DTOs and client method.
3. Add `GoogleAuthService` with protocol.
4. Add URL scheme to `Info.plist`.
5. Refactor setup completion to session-based.
6. Replace setup form with Google button.
7. Remove server display from settings.
8. Update background sync to fixed backend.
9. Update unit tests.
10. Run iOS tests.

## Acceptance Criteria

- iOS app never asks for backend URL.
- iOS settings never displays backend URL.
- iOS uses `https://relay.xuantruong.org` for all API calls.
- User can sign in with Google.
- Native API calls after login are authenticated.
- Existing folder and upload flows keep working.
- Setup complete state no longer depends on `AppSettings.backendBaseURL`.
- Username/password login is no longer reachable from the UI.

## Backend Checklist For Anh

Please add or confirm these:

- `GET /api/auth/google/login` accepts mobile params:
  - `mobile=ios`
  - `redirect_uri=nexusrelay://auth/google/callback`
  - `state=<ios_state>`
- Google callback can detect mobile login and redirect to:
  - `nexusrelay://auth/google/callback?code=<one_time_code>&state=<same_state>`
- `POST /api/auth/mobile/google/exchange` accepts:
  - `code`
  - `state`
  - `platform=ios`
- Exchange response returns:
  - `200`
  - normal user JSON matching `BrowserAuthResponse`
  - auth cookies in `Set-Cookie`
- Exchange code is:
  - short-lived
  - single-use
  - bound to the Google-authenticated user
- Existing cookie session works with:
  - `/api/auth/me`
  - `/api/auth/csrf`
  - `/api/auth/refresh`
  - folder APIs
  - upload APIs

Recommended response body for exchange:

```json
{
  "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "username": "xuan",
  "email": "xuan@example.com",
  "role": "User"
}
```

## Open Questions

1. Should Google login auto-create a NexusRelay account when the email is new, or only allow pre-approved users?
2. Should iOS sign out call `POST /api/auth/logout`, or only clear local cookies/session?
3. Should the mobile exchange return cookies only, or should backend introduce bearer tokens for native clients later?
4. Should callback scheme be `nexusrelay://auth/google/callback` or a bundle-specific scheme like `com.nexusrelay.iphone://auth/google/callback`?

Recommendation:

Use `nexusrelay://auth/google/callback` for the first implementation and cookie exchange for the first implementation. This matches the current iOS API client and keeps the upload/folder API surface stable.
