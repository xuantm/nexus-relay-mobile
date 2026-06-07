import Foundation
import SwiftUI

enum SetupChecklistState: Equatable {
    case complete
    case pending
    case failed

    var iconName: String {
        switch self {
        case .complete: return "checkmark.circle.fill"
        case .pending: return "circle"
        case .failed: return "exclamationmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .complete: return NRDesign.ColorToken.success
        case .pending: return NRDesign.ColorToken.accent
        case .failed: return NRDesign.ColorToken.error
        }
    }
}

struct SetupChecklistRow: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let state: SetupChecklistState

    static func makeRows(
        serverURL: String,
        isSignedIn: Bool,
        userEmail: String?,
        photosStatus: PhotoLibraryAuthorizationStatus,
        destinationFolderName: String
    ) -> [SetupChecklistRow] {
        [
            SetupChecklistRow(
                id: "server",
                title: "Server",
                subtitle: BackendURLValidator.isValid(serverURL)
                    ? (URL(string: serverURL)?.host ?? "Add server URL")
                    : "Add server URL",
                systemImage: "server.rack",
                state: BackendURLValidator.isValid(serverURL) ? .complete : .pending
            ),
            SetupChecklistRow(
                id: "signin",
                title: "Sign in",
                subtitle: isSignedIn ? (userEmail ?? "Signed in") : "Google account",
                systemImage: "person.crop.circle",
                state: isSignedIn ? .complete : .pending
            ),
            SetupChecklistRow(
                id: "photos",
                title: "Photos Access",
                subtitle: photosSubtitle(photosStatus),
                systemImage: "photo.on.rectangle",
                state: photosStatus == .authorized || photosStatus == .limited ? .complete
                     : (photosStatus == .denied || photosStatus == .restricted ? .failed : .pending)
            ),
            SetupChecklistRow(
                id: "folder",
                title: "Destination Folder",
                subtitle: destinationFolderName.isEmpty ? "Not configured" : destinationFolderName,
                systemImage: "folder",
                state: destinationFolderName.isEmpty ? .pending : .complete
            )
        ]
    }

    private static func photosSubtitle(_ status: PhotoLibraryAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "Full access"
        case .limited: return "Limited access"
        case .denied: return "Access denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Choose access"
        }
    }
}
