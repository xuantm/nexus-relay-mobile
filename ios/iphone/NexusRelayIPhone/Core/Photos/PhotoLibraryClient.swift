import Foundation
import Photos

enum PhotoLibraryAuthorizationStatus {
    case authorized
    case limited
    case denied
    case restricted
    case notDetermined
}

protocol PhotoLibraryClient {
    func authorizationStatus() -> PhotoLibraryAuthorizationStatus
    func requestAuthorization() async -> PhotoLibraryAuthorizationStatus
    func fetchCandidates(includeVideos: Bool, includeLivePhotoVideo: Bool, existingResources: [String: Set<PhotoResourceKind>]?) async throws -> [PhotoAssetCandidate]
}
