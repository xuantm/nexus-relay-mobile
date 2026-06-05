import Foundation

enum PhotoResourceKind: String, Codable {
    case image
    case video
    case livePhotoVideo
}

struct PhotoAssetCandidate: Codable, Equatable, Identifiable {
    var id: String { assetLocalIdentifier + ":" + resourceKind.rawValue }
    let assetLocalIdentifier: String
    let resourceKind: PhotoResourceKind
    let originalFilename: String
    let uniformTypeIdentifier: String
    let mimeType: String
    let creationDate: Date?
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let durationSeconds: Double?
    let resourceFileSize: Int64?
}
