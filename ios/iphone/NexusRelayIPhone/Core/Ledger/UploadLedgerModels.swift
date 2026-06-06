import Foundation

enum UploadStatus: String, Codable, Equatable {
    case discovered
    case exporting
    case readyToUpload
    case uploading
    case uploaded
    case synced
    case failed
    case skipped
}

struct UploadLedgerRecord: Codable, Equatable, Identifiable {
    let id: String
    let assetLocalIdentifier: String
    let resourceKind: PhotoResourceKind
    let fingerprintSuffix: String
    let originalFilename: String
    let uploadedFileName: String
    let mimeType: String
    let sizeBytes: Int64?
    let status: UploadStatus
    let backendFolderId: UUID?
    let backendUploadId: UUID?
    let localStagedFileURL: URL?
    let attemptCount: Int
    let lastAttemptAt: Date?
    let lastError: String?
}
