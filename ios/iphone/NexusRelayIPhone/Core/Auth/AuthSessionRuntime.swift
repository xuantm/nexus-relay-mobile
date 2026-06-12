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

        let sharedCookieStorage = cookieStore.httpCookieStorage

        // Control session: CSRF fetch, token refresh, lightweight API queries.
        // Fast timeout so stale control-plane requests fail quickly and don't
        // block the upload pipeline.
        let controlConfig = URLSessionConfiguration.ephemeral
        controlConfig.httpCookieStorage = sharedCookieStorage
        controlConfig.httpCookieAcceptPolicy = .always
        controlConfig.httpShouldSetCookies = true
        controlConfig.httpMaximumConnectionsPerHost = 2
        controlConfig.timeoutIntervalForRequest = 15.0
        controlConfig.timeoutIntervalForResource = 300.0
        let controlDelegate = SessionDelegateRouter()
        let controlSession = URLSession(configuration: controlConfig, delegate: controlDelegate, delegateQueue: nil)

        // Upload session: file uploads only.
        // Generous idle timeout prevents connection-pool cleanup from
        // killing active transfers. Per-request overrides in HTTPClient
        // (90s) provide the real upload-level timeout.
        let uploadConfig = URLSessionConfiguration.ephemeral
        uploadConfig.httpCookieStorage = sharedCookieStorage
        uploadConfig.httpCookieAcceptPolicy = .always
        uploadConfig.httpShouldSetCookies = true
        uploadConfig.httpMaximumConnectionsPerHost = 12
        uploadConfig.timeoutIntervalForRequest = 300.0
        uploadConfig.timeoutIntervalForResource = 3600.0
        let uploadDelegate = SessionDelegateRouter()
        let uploadSession = URLSession(configuration: uploadConfig, delegate: uploadDelegate, delegateQueue: nil)

        let csrfProvider = SystemCSRFTokenProvider(
            urlSession: controlSession,
            sessionFingerprint: {
                Self.sessionFingerprint(for: sessionStore.currentSession)
            }
        )
        self.csrfProvider = csrfProvider

        let httpClient = SystemHTTPClient(
            baseURL: baseURL,
            sessionStore: sessionStore,
            csrfProvider: csrfProvider,
            controlSession: controlSession,
            uploadSession: uploadSession,
            cookieStore: cookieStore,
            uploadDelegate: uploadDelegate,
            controlDelegate: controlDelegate
        )
        self.httpClient = httpClient
        self.apiClient = SystemNexusRelayAPIClient(
            baseURL: baseURL,
            httpClient: httpClient,
            sessionStore: sessionStore,
            cookieStore: cookieStore
        )
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
