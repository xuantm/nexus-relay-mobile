import Foundation

enum UserFacingSyncIssue: Equatable {
    case signInRequired
    case waitingForWiFi
    case waitingForConnection(String)
    case serverUnavailable
    case needsICloudDownload
    case photosAccessRequired
    case generic(String)

    var message: String {
        switch self {
        case .signInRequired:
            return "Sign in required"
        case .waitingForWiFi:
            return "Waiting for Wi-Fi"
        case .waitingForConnection(let details):
            return "Waiting for connection: \(details)"
        case .serverUnavailable:
            return "Server unavailable"
        case .needsICloudDownload:
            return "Needs iCloud download"
        case .photosAccessRequired:
            return "Photos access required"
        case .generic(let message):
            return message
        }
    }

    var requiresRepairAction: Bool {
        if case .signInRequired = self {
            return true
        }
        return false
    }

    static func from(error: Error) -> UserFacingSyncIssue {
        if let syncError = error as? SyncError {
            switch syncError {
            case .cellularConnectionBlocked:
                return .waitingForWiFi
            case .photosPermissionRequired:
                return .photosAccessRequired
            case .missingFolder:
                return .generic(syncError.localizedDescription)
            }
        }

        if let exportError = error as? ExportError {
            switch exportError {
            case .networkAccessRequired:
                return .needsICloudDownload
            default:
                return .generic(exportError.localizedDescription)
            }
        }

        if let apiError = error as? APIError {
            switch apiError {
            case .loginFailed:
                return .generic(apiError.localizedDescription)
            case .requestFailed(let statusCode, _):
                if statusCode == 401 || statusCode == 403 {
                    return .signInRequired
                }
                if statusCode >= 500 {
                    return .serverUnavailable
                }
                return .generic(apiError.localizedDescription)
            case .invalidURL:
                return .generic(apiError.localizedDescription)
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotParseResponse,
                 NSURLErrorNotConnectedToInternet:
                return .waitingForConnection(error.localizedDescription)
            default:
                break
            }
        }

        return fromStoredMessage(error.localizedDescription) ?? .generic(error.localizedDescription)
    }

    static func fromStoredMessage(_ message: String?) -> UserFacingSyncIssue? {
        guard let rawMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines), !rawMessage.isEmpty else {
            return nil
        }

        let normalized = rawMessage.lowercased()
        if normalized.contains("sign in required") ||
            normalized.contains("failed to get current user") ||
            normalized.contains("unauthorized") ||
            normalized.contains("forbidden") {
            return .signInRequired
        }
        if normalized.contains("wi-fi only") ||
            normalized.contains("waiting for wi-fi") ||
            normalized.contains("connection is cellular") {
            return .waitingForWiFi
        }
        if normalized.contains("not connected to internet") ||
            normalized.contains("internet connection appears to be offline") ||
            normalized.contains("network connection was lost") ||
            normalized.contains("cannot connect to host") ||
            normalized.contains("cannot find host") ||
            normalized.contains("waiting for connection") {
            return .waitingForConnection(rawMessage)
        }
        if normalized.contains("server unavailable") ||
            normalized.contains("status code 500") ||
            normalized.contains("status code 502") ||
            normalized.contains("status code 503") {
            return .serverUnavailable
        }
        if normalized.contains("icloud download required") ||
            normalized.contains("needs icloud download") {
            return .needsICloudDownload
        }
        if normalized.contains("photos access is required") ||
            normalized.contains("photos access required") {
            return .photosAccessRequired
        }
        return .generic(rawMessage)
    }
}
