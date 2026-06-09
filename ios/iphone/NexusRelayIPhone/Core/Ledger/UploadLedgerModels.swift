import Foundation

enum UploadLedgerStatus: String, Codable, Equatable {
    case discovered
    case exporting
    case readyToUpload
    case uploading
    case uploaded
    case synced
    case failed
    case skipped
}

extension UploadLedgerStatus {
    var uploadStatus: UploadStatus {
        switch self {
        case .discovered, .readyToUpload, .skipped:
            return .Pending
        case .exporting, .uploading:
            return .Uploading
        case .uploaded, .synced:
            return .Uploaded
        case .failed:
            return .Failed
        }
    }
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
    let status: UploadLedgerStatus
    let backendFolderId: UUID?
    let backendUploadId: UUID?
    let localStagedFileURL: URL?
    let attemptCount: Int
    let lastAttemptAt: Date?
    let lastError: String?

    var uploadStatus: UploadStatus {
        status.uploadStatus
    }
}
