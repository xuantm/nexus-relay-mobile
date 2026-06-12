import Foundation

final class SessionCookieStore {
    private let storage: HTTPCookieStorage
    private let authCookieNames: Set<String>
    private let csrfCookieNames: Set<String>

    init(
        storage: HTTPCookieStorage? = nil,
        authCookieNames: Set<String> = ["access_token", "refresh_token"],
        csrfCookieNames: Set<String> = ["nexus_csrf"]
    ) {
        self.storage = storage ?? URLSessionConfiguration.ephemeral.httpCookieStorage ?? .shared
        self.authCookieNames = authCookieNames
        self.csrfCookieNames = csrfCookieNames
    }

    var httpCookieStorage: HTTPCookieStorage {
        storage
    }

    func replaceSessionCookies(_ cookies: [HTTPCookie], for url: URL) {
        clearAuthCookies(for: url)
        for cookie in cookies where authCookieNames.contains(cookie.name) {
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

    func sessionCookies(for url: URL) -> [HTTPCookie] {
        cookies(for: url).filter { authCookieNames.contains($0.name) }
    }

    func clearAuthCookies(for url: URL) {
        clearCookies(named: authCookieNames, for: url)
    }

    func clearCSRFCookies(for url: URL) {
        clearCookies(named: csrfCookieNames, for: url)
    }

    func clearManagedCookies(for url: URL) {
        clearCookies(named: authCookieNames.union(csrfCookieNames), for: url)
    }

    private func clearCookies(named names: Set<String>, for url: URL) {
        guard let host = url.host?.lowercased() else { return }
        for cookie in storage.cookies ?? [] {
            let domain = cookie.domain
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                .lowercased()
            guard domain == host || host.hasSuffix("." + domain) else { continue }
            guard names.contains(cookie.name) else { continue }
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
