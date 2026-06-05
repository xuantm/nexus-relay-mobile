import Foundation

// MARK: - Auth DTOs
struct LoginRequest: Encodable {
    let username: String
    let password: String
}

struct BrowserAuthResponse: Codable, Equatable {
    let id: UUID
    let username: String
    let email: String?
    let role: String
}

struct CSRFResponse: Codable {
    let token: String
}

// MARK: - Folder DTOs
struct FolderDTO: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let parentId: UUID?
    let googleDriveFolderId: String?
    let createdAt: Date
    let childCount: Int
    let mediaCount: Int
}

struct CreateFolderRequest: Encodable {
    let name: String
    let parentId: UUID?
}

// MARK: - Media DTOs
enum MediaItemStatus: String, Codable {
    case pending = "Pending"
    case uploading = "Uploading"
    case processing = "Processing"
    case completed = "Completed"
    case failed = "Failed"
}

enum MediaType: String, Codable {
    case image = "Image"
    case video = "Video"
}

struct MediaItemDTO: Codable, Equatable, Identifiable {
    let id: UUID
    let folderId: UUID?
    let fileName: String
    let size: Int64
    let mimeType: String
    let width: Int?
    let height: Int?
    let status: MediaItemStatus
    let mediaType: MediaType
    let durationSeconds: Double?
    let thumbnailGenerated: Bool
    let videoCodec: String?
    let createdAt: Date
    let completedAt: Date?
}

struct CursorPageDTO<T: Codable & Equatable>: Codable, Equatable {
    let items: [T]
    let pageSize: Int
    let hasMore: Bool
    let nextCursor: String?
}

struct FolderContentDTO: Codable, Equatable {
    let folder: FolderDTO
    let subFolders: [FolderDTO]
    let mediaItems: [MediaItemDTO]
    let media: CursorPageDTO<MediaItemDTO>
}

// MARK: - Upload DTOs
struct InitUploadRequest: Encodable {
    let folderId: UUID?
    let fileName: String
    let totalSize: Int64
    let totalChunks: Int
}

struct InitUploadResponse: Codable {
    let uploadId: UUID
}

struct CompleteUploadRequest: Encodable {
    let uploadId: UUID
    let fileHash: String?
}

struct StreamUploadResponse: Codable {
    let uploadId: UUID
}
