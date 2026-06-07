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
    let email: String?
    let authProvider: String?

    var isAuthenticated: Bool {
        !codableCookies.isEmpty
    }

    var cookies: [HTTPCookie] {
        codableCookies.compactMap { $0.toHTTPCookie() }
    }

    init(userId: UUID, username: String, role: String, cookies: [HTTPCookie], email: String? = nil, authProvider: String? = nil) {
        self.userId = userId
        self.username = username
        self.role = role
        self.codableCookies = cookies.map { CodableCookie(cookie: $0) }
        self.email = email
        self.authProvider = authProvider
    }

    enum CodingKeys: String, CodingKey {
        case userId
        case username
        case role
        case codableCookies
        case email
        case authProvider
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.userId = try container.decode(UUID.self, forKey: .userId)
        self.username = try container.decode(String.self, forKey: .username)
        self.role = try container.decode(String.self, forKey: .role)
        self.codableCookies = try container.decode([CodableCookie].self, forKey: .codableCookies)
        self.email = try container.decodeIfPresent(String.self, forKey: .email)
        self.authProvider = try container.decodeIfPresent(String.self, forKey: .authProvider)
    }
}
