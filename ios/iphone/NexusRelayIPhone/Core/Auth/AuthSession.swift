import Foundation

struct CodableCookie: Codable, Equatable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let isSecure: Bool
    let isHTTPOnly: Bool
    let expiresDate: Date?

    init(cookie: HTTPCookie) {
        self.name = cookie.name
        self.value = cookie.value
        self.domain = cookie.domain
        self.path = cookie.path
        self.isSecure = cookie.isSecure
        self.isHTTPOnly = cookie.isHTTPOnly
        self.expiresDate = cookie.expiresDate
    }

    func toHTTPCookie() -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path
        ]
        if isSecure { properties[.secure] = "TRUE" }
        if isHTTPOnly { properties[.init("HTTPOnly")] = "TRUE" }
        if let expiresDate = expiresDate { properties[.expires] = expiresDate }
        return HTTPCookie(properties: properties)
    }
}

struct AuthSession: Codable, Equatable {
    let userId: UUID
    let username: String
    let role: String
    let codableCookies: [CodableCookie]

    var isAuthenticated: Bool {
        !codableCookies.isEmpty
    }

    var cookies: [HTTPCookie] {
        codableCookies.compactMap { $0.toHTTPCookie() }
    }

    init(userId: UUID, username: String, role: String, cookies: [HTTPCookie]) {
        self.userId = userId
        self.username = username
        self.role = role
        self.codableCookies = cookies.map { CodableCookie(cookie: $0) }
    }
}
