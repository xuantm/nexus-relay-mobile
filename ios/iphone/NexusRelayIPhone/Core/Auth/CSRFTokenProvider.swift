import Foundation

protocol CSRFTokenProvider: AnyObject {
    func getCSRFToken(baseURL: URL, forceRefresh: Bool) async throws -> String
    func clearToken()
}

final class SystemCSRFTokenProvider: CSRFTokenProvider {
    private var cachedToken: String?
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func getCSRFToken(baseURL: URL, forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, let cached = cachedToken {
            return cached
        }

        let csrfURL = baseURL.appendingPathComponent("api/auth/csrf")
        var request = URLRequest(url: csrfURL)
        request.httpMethod = "GET"

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CSRFError.invalidResponse
        }

        let decoder = JSONDecoder()
        let csrfResponse = try decoder.decode(CSRFResponse.self, from: data)
        self.cachedToken = csrfResponse.token
        return csrfResponse.token
    }

    func clearToken() {
        cachedToken = nil
    }
}

enum CSRFError: Error {
    case invalidResponse
}
