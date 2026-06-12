import Foundation

protocol CSRFTokenProvider: AnyObject {
    func getCSRFToken(baseURL: URL, forceRefresh: Bool) async throws -> String
    func clearToken()
}

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

        let decoder = JSONDecoder()
        let csrfResponse = try decoder.decode(CSRFResponse.self, from: data)
        
        lock.lock()
        self.cachedToken = csrfResponse.token
        self.cachedFingerprint = fingerprint
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

enum CSRFError: Error {
    case invalidResponse
}
