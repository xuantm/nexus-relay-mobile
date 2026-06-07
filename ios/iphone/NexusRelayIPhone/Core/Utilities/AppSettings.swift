import Foundation

struct AppSettings: Codable, Equatable {
    var backendBaseURL: URL?
    var destinationFolderId: UUID?
    var destinationFolderName: String
    var wifiOnly: Bool
    var includeVideos: Bool
    var includeLivePhotoVideo: Bool

    static let defaults = AppSettings(
        backendBaseURL: URL(string: "https://relay.xuantruong.org"),
        destinationFolderId: nil,
        destinationFolderName: "iPhone Uploads",
        wifiOnly: true,
        includeVideos: true,
        includeLivePhotoVideo: false
    )
}
