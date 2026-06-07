import Foundation

enum AuthCallbackResult: Equatable {
    case success(code: String)
    case pending
    case denied(reason: String?)
    case invalid
}

struct AuthCallbackURL {
    static func parse(_ url: URL) -> AuthCallbackResult {
        guard url.scheme == "nexusrelay" else {
            return .invalid
        }
        
        let host = url.host
        let path = url.path
        
        guard host == "auth" else {
            return .invalid
        }
        
        if path == "/success" {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let queryItems = components.queryItems,
                  let codeItem = queryItems.first(where: { $0.name == "code" }),
                  let code = codeItem.value,
                  !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .invalid
            }
            return .success(code: code)
        } else if path == "/pending" {
            return .pending
        } else if path == "/denied" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let reason = components?.queryItems?.first(where: { $0.name == "reason" })?.value
            return .denied(reason: reason)
        }
        
        return .invalid
    }
}
