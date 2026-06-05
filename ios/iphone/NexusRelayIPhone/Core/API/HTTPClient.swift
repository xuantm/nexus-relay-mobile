import Foundation

struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data?
}

struct HTTPResponse {
    let statusCode: Int
    let headers: [AnyHashable: Any]
    let body: Data
}

protocol HTTPClient {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
    func uploadFile(_ request: HTTPRequest, fileURL: URL) async throws -> HTTPResponse
}

final class SystemHTTPClient: HTTPClient {
    private let baseURL: URL
    private let sessionStore: SessionStore
    private let csrfProvider: CSRFTokenProvider
    private let urlSession: URLSession

    init(
        baseURL: URL,
        sessionStore: SessionStore,
        csrfProvider: CSRFTokenProvider,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.sessionStore = sessionStore
        self.csrfProvider = csrfProvider
        self.urlSession = urlSession
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        return try await sendWithRetry(request, fileURL: nil)
    }

    func uploadFile(_ request: HTTPRequest, fileURL: URL) async throws -> HTTPResponse {
        return try await sendWithRetry(request, fileURL: fileURL)
    }

    private func sendWithRetry(_ request: HTTPRequest, fileURL: URL?, isRetry: Bool = false) async throws -> HTTPResponse {
        let urlRequest = try await prepareRequest(request)
        let response: HTTPResponse

        if let fileURL = fileURL {
            let (data, urlResponse) = try await urlSession.upload(for: urlRequest, fromFile: fileURL)
            let httpResponse = urlResponse as? HTTPURLResponse ?? HTTPURLResponse()
            response = HTTPResponse(statusCode: httpResponse.statusCode, headers: httpResponse.allHeaderFields, body: data)
        } else {
            let (data, urlResponse) = try await urlSession.data(for: urlRequest)
            let httpResponse = urlResponse as? HTTPURLResponse ?? HTTPURLResponse()
            response = HTTPResponse(statusCode: httpResponse.statusCode, headers: httpResponse.allHeaderFields, body: data)
        }

        saveCookies(for: baseURL)

        if response.statusCode == 401 && !isRetry && request.path != "api/auth/refresh" && request.path != "api/auth/login" {
            let refreshSuccess = try await performRefresh()
            if refreshSuccess {
                // Retry once
                return try await sendWithRetry(request, fileURL: fileURL, isRetry: true)
            }
        }

        // If CSRF expired/invalid (often returns 400 or 403), retry once with forced fresh CSRF
        if (response.statusCode == 400 || response.statusCode == 403) && !isRetry && isUnsafeMethod(request.method) && request.path != "api/auth/csrf" {
            csrfProvider.clearToken()
            return try await sendWithRetry(request, fileURL: fileURL, isRetry: true)
        }

        return response
    }

    private func prepareRequest(_ request: HTTPRequest) async throws -> URLRequest {
        let fullURL = baseURL.appendingPathComponent(request.path)
        var urlRequest = URLRequest(url: fullURL)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body

        // Set default headers
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, val) in request.headers {
            urlRequest.setValue(val, forHTTPHeaderField: key)
        }

        // Auto-set Content-Type for JSON body requests when not already provided
        if request.body != nil && urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // Sync session cookies to URLSession configuration / cookie storage
        syncCookies(for: baseURL)

        // Add CSRF token for unsafe methods
        if isUnsafeMethod(request.method) && request.path != "api/auth/csrf" {
            let csrfToken = try await csrfProvider.getCSRFToken(baseURL: baseURL, forceRefresh: false)
            urlRequest.setValue(csrfToken, forHTTPHeaderField: "X-NexusRelay-CSRF")
        }

        return urlRequest
    }

    private func isUnsafeMethod(_ method: String) -> Bool {
        let upper = method.uppercased()
        return upper == "POST" || upper == "PUT" || upper == "DELETE"
    }

    private func syncCookies(for url: URL) {
        if let session = sessionStore.currentSession {
            let storage = HTTPCookieStorage.shared
            for cookie in session.cookies {
                storage.setCookie(cookie)
            }
        }
    }

    private func saveCookies(for url: URL) {
        guard let session = sessionStore.currentSession else { return }
        let storage = HTTPCookieStorage.shared
        if let cookies = storage.cookies(for: url) {
            let newSession = AuthSession(userId: session.userId, username: session.username, role: session.role, cookies: cookies)
            try? sessionStore.saveSession(newSession)
        }
    }

    private func performRefresh() async throws -> Bool {
        guard let session = sessionStore.currentSession else { return false }
        let refreshURL = baseURL.appendingPathComponent("api/auth/refresh")
        var refreshRequest = URLRequest(url: refreshURL)
        refreshRequest.httpMethod = "POST"

        // Fetch new CSRF
        csrfProvider.clearToken()
        if let csrf = try? await csrfProvider.getCSRFToken(baseURL: baseURL, forceRefresh: true) {
            refreshRequest.setValue(csrf, forHTTPHeaderField: "X-NexusRelay-CSRF")
        }

        syncCookies(for: baseURL)

        let (_, response) = try await urlSession.data(for: refreshRequest)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            saveCookies(for: baseURL)
            return true
        } else {
            try? sessionStore.clearSession()
            return false
        }
    }
}
