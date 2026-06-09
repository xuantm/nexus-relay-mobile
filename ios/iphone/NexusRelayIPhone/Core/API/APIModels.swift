import Foundation

// MARK: - Auth DTOs
struct LoginRequest: Encodable {
    let username: String
    let password: String
}

struct IosSessionExchangeRequest: Encodable {
    let code: String
}

struct BrowserAuthResponse: Codable, Equatable {
    let id: UUID
    let username: String
    let email: String?
    let role: String
    let authProvider: String?
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
    case buffering = "Buffering"
    case relaying = "Relaying"
    case uploading = "Uploading"
    case processing = "Processing"
    case completed = "Completed"
    case failed = "Failed"
}

enum UploadStatus: String, Codable, Equatable {
    case Pending = "Pending"
    case Uploading = "Uploading"
    case Uploaded = "Uploaded"
    case Failed = "Failed"
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
    let uploadStatus: UploadStatus?
    let mediaType: MediaType
    let durationSeconds: Double?
    let thumbnailGenerated: Bool
    let videoCodec: String?
    let createdAt: Date
    let completedAt: Date?

    init(
        id: UUID,
        folderId: UUID?,
        fileName: String,
        size: Int64,
        mimeType: String,
        width: Int?,
        height: Int?,
        status: MediaItemStatus,
        uploadStatus: UploadStatus? = nil,
        mediaType: MediaType,
        durationSeconds: Double?,
        thumbnailGenerated: Bool,
        videoCodec: String?,
        createdAt: Date,
        completedAt: Date?
    ) {
        self.id = id
        self.folderId = folderId
        self.fileName = fileName
        self.size = size
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.status = status
        self.uploadStatus = uploadStatus
        self.mediaType = mediaType
        self.durationSeconds = durationSeconds
        self.thumbnailGenerated = thumbnailGenerated
        self.videoCodec = videoCodec
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

struct CursorPageDTO<T: Codable & Equatable>: Codable, Equatable {
    let items: [T]
    let pageSize: Int
    let hasMore: Bool
    let nextCursor: String?
}

struct OffsetPageDTO<T: Codable & Equatable>: Codable, Equatable {
    let items: [T]
    let page: Int
    let pageSize: Int
    let hasMore: Bool
    let nextPage: Int?
}

struct BreadcrumbDTO: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
}

struct FolderContentDTO: Codable, Equatable {
    let folder: FolderDTO
    let subFolders: [FolderDTO]
    let mediaItems: [MediaItemDTO]?
    let media: CursorPageDTO<MediaItemDTO>?
    let breadcrumbs: [BreadcrumbDTO]?
    let page: Int?
    let pageSize: Int?
    let hasMore: Bool?
    let nextPage: Int?
    let folders: OffsetPageDTO<FolderDTO>?
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
