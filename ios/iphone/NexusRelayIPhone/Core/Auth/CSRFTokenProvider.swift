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
    private var activeFetchTask: Task<String, Error>?
    private var activeFetchId: UUID?

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
        if forceRefresh {
            cachedToken = nil
            activeFetchTask = nil
            activeFetchId = nil
        } else if let cached = cachedToken, cachedFingerprint == fingerprint {
            lock.unlock()
            return cached
        }

        if let activeTask = activeFetchTask {
            lock.unlock()
            return try await activeTask.value
        }

        let fetchId = UUID()
        self.activeFetchId = fetchId

        let task = Task<String, Error> { [weak self] in
            guard let self = self else { throw CSRFError.invalidResponse }
            do {
                let csrfURL = baseURL.appendingPathComponent("api/auth/csrf")
                var request = URLRequest(url: csrfURL)
                request.httpMethod = "GET"

                let (data, response) = try await self.urlSession.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw CSRFError.invalidResponse
                }

                let decoder = JSONDecoder()
                let csrfResponse = try decoder.decode(CSRFResponse.self, from: data)
                
                self.lock.lock()
                self.cachedToken = csrfResponse.token
                self.cachedFingerprint = fingerprint
                if self.activeFetchId == fetchId {
                    self.activeFetchTask = nil
                    self.activeFetchId = nil
                }
                self.lock.unlock()
                
                return csrfResponse.token
            } catch {
                self.lock.lock()
                if self.activeFetchId == fetchId {
                    self.activeFetchTask = nil
                    self.activeFetchId = nil
                }
                self.lock.unlock()
                throw error
            }
        }

        self.activeFetchTask = task
        lock.unlock()

        return try await task.value
    }

    func clearToken() {
        lock.lock()
        cachedToken = nil
        cachedFingerprint = nil
        activeFetchTask = nil
        activeFetchId = nil
        lock.unlock()
    }
}

enum CSRFError: Error {
    case invalidResponse
}
