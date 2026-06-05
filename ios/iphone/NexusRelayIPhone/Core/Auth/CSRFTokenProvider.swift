import Foundation

protocol CSRFTokenProvider: AnyObject {
    func getCSRFToken(baseURL: URL, forceRefresh: Bool) async throws -> String
    func clearToken()
}

final class SystemCSRFTokenProvider: CSRFTokenProvider {
    private var cachedToken: String?
    private let urlSession: URLSession
    private let lock = NSLock()

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func getCSRFToken(baseURL: URL, forceRefresh: Bool = false) async throws -> String {
        lock.lock()
        if !forceRefresh, let cached = cachedToken {
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
        lock.unlock()
        
        return csrfResponse.token
    }

    func clearToken() {
        lock.lock()
        cachedToken = nil
        lock.unlock()
    }
}

enum CSRFError: Error {
    case invalidResponse
}
