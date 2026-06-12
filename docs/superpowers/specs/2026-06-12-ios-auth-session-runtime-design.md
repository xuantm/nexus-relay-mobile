# iOS Auth Session Runtime Design

## Problem

iOS upload requests can combine stale refresh tokens, auth cookies, and CSRF request tokens from different session snapshots. Backend logs show uploads and Pixel streaming continue to work, then refresh fails with `Invalid refresh token`, followed by antiforgery validation errors where the CSRF token belongs to a different claims-based user than the current request user.

The current iOS implementation stores the persisted session in Keychain, mirrors cookies through `HTTPCookieStorage.shared`, caches a CSRF request token in each `SystemCSRFTokenProvider` instance, and creates multiple independent HTTP/CSRF providers for setup, foreground sync, and background sync. Those pieces do not share one authoritative session boundary.

## Goals

- Give iOS one app-owned auth runtime per backend base URL.
- Stop using `HTTPCookieStorage.shared` for NexusRelay API auth traffic.
- Bind CSRF cache entries to the current session identity and cookie fingerprint.
- Clear persisted session, runtime cookies, and CSRF cache atomically on refresh failure and logout.
- Preserve backend auth contracts and upload API behavior.
- Add a small backend hardening change so auth failure cleanup also removes the CSRF cookie.

## Non-Goals

- Changing Google Drive upload, chunk size, Pixel download, or backend media processing behavior.
- Replacing cookie authentication with bearer tokens.
- Broad dependency injection rewrites outside the iOS API/auth construction points.
- Changing API response DTO contracts.

## Recommended Architecture

Introduce an iOS `AuthSessionRuntime` that owns the app-managed cookie jar, URLSession, CSRF provider, and session lifecycle helpers for one backend URL. UI setup, foreground sync, reconciliation, and background sync should create API clients through this runtime instead of constructing independent `SystemHTTPClient` and `SystemCSRFTokenProvider` instances.

`SystemHTTPClient` should depend on a runtime cookie store instead of `HTTPCookieStorage.shared`. Before each request, it should install only the persisted session cookies into the runtime cookie store after purging app-managed cookies for the backend host. After each response, it should merge `Set-Cookie` values back into the persisted session and runtime cookie store. Refresh failure should call a single reset method that clears Keychain session state, runtime cookies for the backend host, and CSRF cache.

`SystemCSRFTokenProvider` should cache by a session fingerprint, not merely by object lifetime. The fingerprint should include stable identity and cookie values relevant to auth, such as user id plus auth cookie names/values. When the session is absent or changes, cached CSRF is not reused. CSRF fetches should use the same runtime URLSession and cookie store as the request that will use the token.

Backend cleanup should delete `nexus_csrf` along with `access_token` and `refresh_token` on refresh failure and logout. This is a guardrail, not the primary fix.

## Components

- `AuthSessionRuntime`: Builds and owns `HTTPCookieStorage`, `URLSession`, `SystemCSRFTokenProvider`, `SystemHTTPClient`, and `SystemNexusRelayAPIClient` for one base URL and session store.
- `SessionCookieStore`: Small wrapper around a private `HTTPCookieStorage` that purges and writes app-managed cookies for a backend URL.
- `SessionFingerprint`: Value derived from `AuthSession` identity and auth cookies. Used as the CSRF cache key.
- `SystemCSRFTokenProvider`: Updated to accept a session fingerprint provider and cache token per fingerprint.
- `SystemHTTPClient`: Updated to use private cookie storage and atomic session reset on refresh failure.
- Backend auth endpoints: Updated to delete `nexus_csrf` on auth cleanup paths.

## Data Flow

1. App creates an `AuthSessionRuntime` for the configured backend URL.
2. HTTP client prepares a request by syncing the current persisted session cookies into the runtime cookie jar.
3. Unsafe methods ask the CSRF provider for a token keyed by the current session fingerprint.
4. CSRF provider fetches `/api/auth/csrf` using the same runtime URLSession and cookies.
5. The request is sent with matching cookies and `X-NexusRelay-CSRF`.
6. Response cookies are merged into persisted session state and runtime cookie storage.
7. A 401 triggers one refresh attempt.
8. Successful refresh stores new auth cookies, invalidates old CSRF, and retries once.
9. Failed refresh clears session, runtime cookies, and CSRF, then returns sign-in required behavior to the caller.

## Error Handling

- `401` response: refresh once, then retry once if refresh succeeds.
- Refresh non-200 or thrown error: clear all app auth artifacts for the backend URL and return failure.
- `400` or `403` on unsafe method: clear CSRF cache and retry once with a fresh token for the current fingerprint.
- Logout: clear session store, runtime cookies, CSRF cache, local settings, ledger, and view-model state.

## Testing

- Unit test that refresh failure clears Keychain session, runtime cookies, and cached CSRF.
- Unit test that CSRF cache is reused only for the same session fingerprint.
- Unit test that CSRF fetch uses the same runtime cookie store as the API request.
- Unit test that session exchange clears stale runtime cookies before saving the new session.
- Unit test or focused backend verification that refresh failure and logout delete `nexus_csrf`.

## Rollout

This is backwards-compatible with the backend API. Existing users may have stale cookies in `HTTPCookieStorage.shared`; the new runtime ignores that shared store. On first launch after update, the app should rely on Keychain session cookies only. If those cookies are invalid, refresh failure will clear the app-owned runtime and ask the user to sign in again.
