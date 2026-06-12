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
