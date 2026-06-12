# iOS Auth Session Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make iOS auth cookies, refresh, and CSRF tokens share one session boundary so uploads cannot send a request token for a different claims user than the current auth cookies.

**Architecture:** Add an iOS auth runtime that owns a private cookie store, URLSession, HTTP client, and CSRF provider for one backend URL. Bind CSRF cache to the current session fingerprint and clear all app auth artifacts atomically on refresh failure, session exchange, and logout. Add backend cleanup for `nexus_csrf` on refresh failure/logout.

**Tech Stack:** Swift 5.10, URLSession, HTTPCookieStorage, XCTest, .NET 10 Minimal API, ASP.NET Core antiforgery.

---

## File Structure

- Modify `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhone/Core/Auth/CSRFTokenProvider.swift`: cache CSRF by session fingerprint and use the runtime URLSession.
- Create `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhone/Core/Auth/SessionCookieStore.swift`: private app cookie jar wrapper.
- Create `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhone/Core/Auth/AuthSessionRuntime.swift`: shared factory for URLSession, CSRF provider, HTTP client, and API client.
- Modify `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhone/Core/API/HTTPClient.swift`: replace shared cookie storage with `SessionCookieStore` and call atomic clear on refresh failure.
- Modify `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhone/Core/API/NexusRelayAPIClient.swift`: ensure session exchange purges stale runtime cookies before saving new session cookies.
- Modify `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhone/App/AppDelegate.swift`: build background sync API client through `AuthSessionRuntime`.
- Modify `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhone/Features/Setup/SetupViewModel.swift`: build setup API client through `AuthSessionRuntime`.
- Modify `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhone/Features/SyncStatus/SyncStatusViewModel.swift`: build foreground sync and logout cleanup through `AuthSessionRuntime`.
- Modify `G:/workspace/nexus-relay/backend/src/NexusRelay.Backend.Api/Endpoints/AuthEndpoints.cs`: delete `nexus_csrf` on refresh failure and logout.
- Test `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhoneTests/Auth/CSRFTokenProviderTests.swift`.
- Test `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhoneTests/API/NexusRelayAPIClientTests.swift`.
- Test `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhoneTests/API/NexusRelayAPIClientExchangeTests.swift`.

### Task 1: CSRF Cache Bound To Session Fingerprint

**Files:**
- Modify: `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhone/Core/Auth/CSRFTokenProvider.swift`
- Test: `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhoneTests/Auth/CSRFTokenProviderTests.swift`

- [ ] **Step 1: Write the failing test**

Add this test to `CSRFTokenProviderTests`:

```swift
func testCSRFTokenCacheInvalidatesWhenSessionFingerprintChanges() async throws {
    let baseURL = URL(string: "https://relay.xuantruong.org")!
    var fingerprint = "session-a"
    var requestCount = 0
    csrfProvider = SystemCSRFTokenProvider(
        urlSession: session,
        sessionFingerprint: { fingerprint }
    )

    MockURLProtocol.requestHandler = { request in
        requestCount += 1
        let json = "{\"token\": \"token-\(requestCount)\"}".data(using: .utf8)!
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, json)
    }

    let first = try await csrfProvider.getCSRFToken(baseURL: baseURL, forceRefresh: false)
    let second = try await csrfProvider.getCSRFToken(baseURL: baseURL, forceRefresh: false)
    fingerprint = "session-b"
    let third = try await csrfProvider.getCSRFToken(baseURL: baseURL, forceRefresh: false)

    XCTAssertEqual(first, "token-1")
    XCTAssertEqual(second, "token-1")
    XCTAssertEqual(third, "token-2")
    XCTAssertEqual(requestCount, 2)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/ios/iphone
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/CSRFTokenProviderTests/testCSRFTokenCacheInvalidatesWhenSessionFingerprintChanges
```

Expected: FAIL to compile because `SystemCSRFTokenProvider` does not accept `sessionFingerprint`.

- [ ] **Step 3: Implement minimal CSRF fingerprint cache**

Update `SystemCSRFTokenProvider` to store `cachedFingerprint` with `cachedToken`:

```swift
final class SystemCSRFTokenProvider: CSRFTokenProvider {
    private var cachedToken: String?
    private var cachedFingerprint: String?
    private let urlSession: URLSession
    private let sessionFingerprint: () -> String?
    private let lock = NSLock()

    init(
        urlSession: URLSession = .shared,
        sessionFingerprint: @escaping () -> String? = { nil }
    ) {
        self.urlSession = urlSession
        self.sessionFingerprint = sessionFingerprint
    }

    func getCSRFToken(baseURL: URL, forceRefresh: Bool = false) async throws -> String {
        let fingerprint = sessionFingerprint()
        lock.lock()
        if !forceRefresh, let cached = cachedToken, cachedFingerprint == fingerprint {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let csrfURL = baseURL.appendingPathComponent("api/auth/csrf")
        var request = URLRequest(url: csrfURL)
        request.httpMethod = "GET"

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CSRFError.invalidResponse
        }

        let csrfResponse = try JSONDecoder().decode(CSRFResponse.self, from: data)

        lock.lock()
        cachedToken = csrfResponse.token
        cachedFingerprint = fingerprint
        lock.unlock()

        return csrfResponse.token
    }

    func clearToken() {
        lock.lock()
        cachedToken = nil
        cachedFingerprint = nil
        lock.unlock()
    }
}
```

- [ ] **Step 4: Run focused CSRF tests**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/ios/iphone
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/CSRFTokenProviderTests
```

Expected: PASS.

### Task 2: Private Session Cookie Store

**Files:**
- Create: `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhone/Core/Auth/SessionCookieStore.swift`
- Modify: `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhone/Core/API/HTTPClient.swift`
- Test: `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhoneTests/API/NexusRelayAPIClientTests.swift`

- [ ] **Step 1: Write the failing refresh-failure cleanup test**

Add this test to `NexusRelayAPIClientTests`:

```swift
func testHTTPClientRefreshFailureClearsSessionCookiesAndCSRF() async throws {
    let access = HTTPCookie(properties: [.name: "access_token", .value: "old_jwt", .domain: "relay.xuantruong.org", .path: "/"])!
    let refresh = HTTPCookie(properties: [.name: "refresh_token", .value: "bad_refresh", .domain: "relay.xuantruong.org", .path: "/"])!
    let cookieStore = SessionCookieStore(storage: URLSessionConfiguration.ephemeral.httpCookieStorage)
    sessionStore.currentSession = AuthSession(userId: UUID(), username: "xuan", role: "Admin", cookies: [access, refresh])
    csrfProvider.tokenValue = "stale-csrf"
    httpClient = SystemHTTPClient(
        baseURL: baseURL,
        sessionStore: sessionStore,
        csrfProvider: csrfProvider,
        urlSession: urlSession,
        cookieStore: cookieStore
    )
    apiClient = SystemNexusRelayAPIClient(baseURL: baseURL, httpClient: httpClient, sessionStore: sessionStore)

    var requestCount = 0
    MockURLProtocol.requestHandler = { request in
        requestCount += 1
        if request.url?.path == "/api/folders" {
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        if request.url?.path == "/api/auth/refresh" {
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        XCTFail("Unexpected request: \(request.url?.path ?? "")")
        throw NSError(domain: "test", code: -1)
    }

    do {
        _ = try await apiClient.listRootFolders()
        XCTFail("Expected request failure")
    } catch {
        XCTAssertNil(sessionStore.currentSession)
        XCTAssertTrue(cookieStore.cookies(for: baseURL).isEmpty)
        XCTAssertEqual(csrfProvider.clearCount, 1)
    }
    XCTAssertEqual(requestCount, 2)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/ios/iphone
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/NexusRelayAPIClientTests/testHTTPClientRefreshFailureClearsSessionCookiesAndCSRF
```

Expected: FAIL to compile because `SessionCookieStore` and `cookieStore` initializer argument do not exist.

- [ ] **Step 3: Implement `SessionCookieStore`**

Create `SessionCookieStore.swift`:

```swift
import Foundation

final class SessionCookieStore {
    private let storage: HTTPCookieStorage
    private let managedCookieNames: Set<String>

    init(
        storage: HTTPCookieStorage? = nil,
        managedCookieNames: Set<String> = ["access_token", "refresh_token", "nexus_csrf"]
    ) {
        self.storage = storage ?? URLSessionConfiguration.ephemeral.httpCookieStorage ?? .shared
        self.managedCookieNames = managedCookieNames
    }

    var httpCookieStorage: HTTPCookieStorage {
        storage
    }

    func replaceSessionCookies(_ cookies: [HTTPCookie], for url: URL) {
        clearManagedCookies(for: url)
        for cookie in cookies {
            storage.setCookie(cookie)
        }
    }

    func storeResponseCookies(from response: HTTPURLResponse, for url: URL) {
        let responseCookies = HTTPCookie.cookies(
            withResponseHeaderFields: headerFields(from: response.allHeaderFields),
            for: url
        )
        for cookie in responseCookies {
            storage.setCookie(cookie)
        }
    }

    func cookies(for url: URL) -> [HTTPCookie] {
        storage.cookies(for: url) ?? []
    }

    func clearManagedCookies(for url: URL) {
        guard let host = url.host?.lowercased() else { return }
        for cookie in storage.cookies ?? [] {
            let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            guard domain == host || host.hasSuffix("." + domain) else { continue }
            guard managedCookieNames.contains(cookie.name) else { continue }
            storage.deleteCookie(cookie)
        }
    }

    private func headerFields(from headers: [AnyHashable: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in headers {
            guard let headerName = key as? String else { continue }
            if let headerValue = value as? String {
                result[headerName] = headerValue
            }
        }
        return result
    }
}
```

- [ ] **Step 4: Update `SystemHTTPClient` to use `SessionCookieStore`**

Add a `cookieStore` parameter and replace all `HTTPCookieStorage.shared` usage:

```swift
private let cookieStore: SessionCookieStore

init(
    baseURL: URL,
    sessionStore: SessionStore,
    csrfProvider: CSRFTokenProvider,
    urlSession: URLSession = .shared,
    cookieStore: SessionCookieStore? = nil
) {
    self.baseURL = baseURL
    self.sessionStore = sessionStore
    self.csrfProvider = csrfProvider
    self.urlSession = urlSession
    self.cookieStore = cookieStore ?? SessionCookieStore(storage: urlSession.configuration.httpCookieStorage)
}

private func syncCookies(for url: URL) {
    if let session = sessionStore.currentSession {
        cookieStore.replaceSessionCookies(session.cookies, for: url)
    } else {
        cookieStore.clearManagedCookies(for: url)
    }
}

private func saveCookies(for url: URL) {
    guard let session = sessionStore.currentSession else { return }
    let cookies = cookieStore.cookies(for: url)
    let newSession = AuthSession(userId: session.userId, username: session.username, role: session.role, cookies: cookies)
    try? sessionStore.saveSession(newSession)
}

private func saveCookies(from response: HTTPURLResponse) {
    cookieStore.storeResponseCookies(from: response, for: baseURL)
    saveCookies(for: baseURL)
}

private func clearSessionArtifacts() {
    try? sessionStore.clearSession()
    cookieStore.clearManagedCookies(for: baseURL)
    csrfProvider.clearToken()
}
```

In `performRefresh`, replace refresh failure cleanup with:

```swift
clearSessionArtifacts()
return false
```

- [ ] **Step 5: Run focused API tests**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/ios/iphone
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/NexusRelayAPIClientTests
```

Expected: PASS after updating existing tests to pass the private `SessionCookieStore` where they inspect cookies.

### Task 3: Shared Auth Runtime Factory

**Files:**
- Create: `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhone/Core/Auth/AuthSessionRuntime.swift`
- Modify: `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhone/App/AppDelegate.swift`
- Modify: `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhone/Features/Setup/SetupViewModel.swift`
- Modify: `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhone/Features/SyncStatus/SyncStatusViewModel.swift`

- [ ] **Step 1: Create runtime factory**

Add `AuthSessionRuntime.swift`:

```swift
import Foundation

final class AuthSessionRuntime {
    let baseURL: URL
    let sessionStore: SessionStore
    let cookieStore: SessionCookieStore
    let csrfProvider: CSRFTokenProvider
    let httpClient: HTTPClient
    let apiClient: NexusRelayAPI

    init(
        baseURL: URL,
        sessionStore: SessionStore = CookieSessionStore(),
        cookieStore: SessionCookieStore = SessionCookieStore()
    ) {
        self.baseURL = baseURL
        self.sessionStore = sessionStore
        self.cookieStore = cookieStore

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = cookieStore.httpCookieStorage
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        let urlSession = URLSession(configuration: configuration)

        let csrfProvider = SystemCSRFTokenProvider(
            urlSession: urlSession,
            sessionFingerprint: {
                Self.sessionFingerprint(for: sessionStore.currentSession)
            }
        )
        self.csrfProvider = csrfProvider

        let httpClient = SystemHTTPClient(
            baseURL: baseURL,
            sessionStore: sessionStore,
            csrfProvider: csrfProvider,
            urlSession: urlSession,
            cookieStore: cookieStore
        )
        self.httpClient = httpClient
        self.apiClient = SystemNexusRelayAPIClient(baseURL: baseURL, httpClient: httpClient, sessionStore: sessionStore)
    }

    func clearAuthArtifacts() {
        try? sessionStore.clearSession()
        cookieStore.clearManagedCookies(for: baseURL)
        csrfProvider.clearToken()
    }

    static func sessionFingerprint(for session: AuthSession?) -> String? {
        guard let session else { return nil }
        let authCookies = session.cookies
            .filter { $0.name == "access_token" || $0.name == "refresh_token" }
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: ";")
        return "\(session.userId.uuidString)|\(authCookies)"
    }
}
```

- [ ] **Step 2: Replace local setup construction**

In `SetupViewModel.saveAndLogin`, replace manual keychain/csrf/http/api construction with:

```swift
let runtime = AuthSessionRuntime(baseURL: backendURL, sessionStore: sessionStore)
let apiClient = runtime.apiClient
```

- [ ] **Step 3: Replace foreground sync construction**

In `SyncStatusViewModel.initializeServices`, replace manual keychain/csrf/http/api construction with:

```swift
let sessionStore = CookieSessionStore(keychain: SystemKeychainStore())
let runtime = AuthSessionRuntime(baseURL: url, sessionStore: sessionStore)
let apiClient = runtime.apiClient
```

In `logout`, call:

```swift
if let url = settingsStore.settings.backendBaseURL {
    let runtime = AuthSessionRuntime(baseURL: url, sessionStore: sessionStore)
    runtime.clearAuthArtifacts()
} else {
    try? sessionStore.clearSession()
}
```

- [ ] **Step 4: Replace background sync construction**

In `AppDelegate.resolveSyncOrchestrator`, replace manual keychain/csrf/http/api construction with:

```swift
let sessionStore = CookieSessionStore(keychain: SystemKeychainStore())
let runtime = AuthSessionRuntime(baseURL: url, sessionStore: sessionStore)
let apiClient = runtime.apiClient
```

- [ ] **Step 5: Build iOS app**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/ios/iphone
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected: PASS.

### Task 4: Session Exchange Purges Stale Runtime Cookies

**Files:**
- Modify: `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhone/Core/API/NexusRelayAPIClient.swift`
- Test: `G:/workspace/nexus-relay-mobile/ios/iphone/NexusRelayIPhoneTests/API/NexusRelayAPIClientExchangeTests.swift`

- [ ] **Step 1: Write failing exchange cleanup test**

Add a test that creates `SessionCookieStore`, seeds stale `access_token` and `nexus_csrf`, performs session exchange with new cookies, and asserts the saved session contains only the new auth cookies from the response.

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/ios/iphone
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/NexusRelayAPIClientExchangeTests
```

Expected: FAIL before `SystemNexusRelayAPIClient` can use the runtime cookie store.

- [ ] **Step 3: Update API client cookie fallback**

Add an optional `cookieStore` dependency to `SystemNexusRelayAPIClient`. Use `cookieStore.cookies(for: baseURL)` instead of `HTTPCookieStorage.shared.cookies(for: baseURL)` when response headers do not include cookies. For session exchange, clear CSRF after saving the new session.

- [ ] **Step 4: Run exchange tests**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/ios/iphone
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/NexusRelayAPIClientExchangeTests
```

Expected: PASS.

### Task 5: Backend CSRF Cookie Cleanup

**Files:**
- Modify: `G:/workspace/nexus-relay/backend/src/NexusRelay.Backend.Api/Endpoints/AuthEndpoints.cs`

- [ ] **Step 1: Implement shared delete helper**

In `AuthEndpoints.cs`, add a private helper near `SetAuthCookies`:

```csharp
private static void DeleteAuthCookies(HttpContext httpContext, bool secureCookies)
{
    var deleteOptions = new CookieOptions
    {
        Path = "/",
        HttpOnly = true,
        Secure = secureCookies,
        SameSite = secureCookies ? SameSiteMode.Strict : SameSiteMode.Lax
    };

    httpContext.Response.Cookies.Delete("access_token", deleteOptions);
    httpContext.Response.Cookies.Delete("refresh_token", deleteOptions);
    httpContext.Response.Cookies.Delete("nexus_csrf", deleteOptions);
}
```

- [ ] **Step 2: Use helper in refresh failure**

Replace the inline delete block in `/refresh` catch with:

```csharp
DeleteAuthCookies(httpContext, secureCookies);
throw;
```

- [ ] **Step 3: Use helper in logout**

Replace logout's inline auth cookie deletion with:

```csharp
DeleteAuthCookies(httpContext, secureCookies);
```

- [ ] **Step 4: Run backend build**

Run:

```powershell
Set-Location G:/workspace/nexus-relay
dotnet build backend/NexusRelay.Backend.slnx
```

Expected: PASS.

### Task 6: Final Verification

**Files:**
- Verify all modified files.

- [ ] **Step 1: Run focused iOS auth/API tests**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/ios/iphone
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/CSRFTokenProviderTests -only-testing:NexusRelayIPhoneTests/NexusRelayAPIClientTests -only-testing:NexusRelayIPhoneTests/NexusRelayAPIClientExchangeTests
```

Expected: PASS.

- [ ] **Step 2: Run iOS build**

Run:

```powershell
Set-Location G:/workspace/nexus-relay-mobile/ios/iphone
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected: PASS.

- [ ] **Step 3: Run backend build**

Run:

```powershell
Set-Location G:/workspace/nexus-relay
dotnet build backend/NexusRelay.Backend.slnx
```

Expected: PASS.

- [ ] **Step 4: Inspect git diffs**

Run:

```powershell
git -C G:/workspace/nexus-relay-mobile diff -- ios/iphone/NexusRelayIPhone ios/iphone/NexusRelayIPhoneTests docs/superpowers
git -C G:/workspace/nexus-relay diff -- backend/src/NexusRelay.Backend.Api/Endpoints/AuthEndpoints.cs
```

Expected: Diffs only touch auth/session/runtime and backend cookie cleanup.

## Self-Review

- Spec coverage: covered iOS private cookie jar, CSRF fingerprint cache, refresh failure cleanup, shared runtime construction, logout/session exchange cleanup, and backend CSRF deletion.
- Placeholder scan: no `TBD`, `TODO`, or unspecified implementation steps remain.
- Type consistency: planned new names are `SessionCookieStore`, `AuthSessionRuntime`, `sessionFingerprint`, `clearAuthArtifacts`, and `cookieStore`.
