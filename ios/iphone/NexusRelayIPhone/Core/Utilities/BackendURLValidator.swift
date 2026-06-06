import Foundation

enum BackendURLValidator {
    static func isValid(_ rawValue: String) -> Bool {
        guard let url = URL(string: rawValue) else { return false }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        return url.host?.isEmpty == false
    }
}
