import Foundation

enum APIError: Error, LocalizedError {
    case loginFailed(statusCode: Int)
    case requestFailed(statusCode: Int, message: String)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .loginFailed(let statusCode):
            return "Sign in failed"
        case .requestFailed(let statusCode, let message):
            if statusCode == 401 || statusCode == 403 {
                return UserFacingSyncIssue.signInRequired.message
            }
            if statusCode >= 500 {
                return UserFacingSyncIssue.serverUnavailable.message
            }
            return message
        case .invalidURL:
            return "Invalid server URL"
        }
    }
}

protocol NexusRelayAPI {
    func login(username: String, password: String) async throws -> AuthSession
    func exchangeIosSession(code: String) async throws -> AuthSession
    func currentUser() async throws -> BrowserAuthResponse
    func getAccountSyncDashboard() async throws -> AccountSyncDashboardDTO
    func getAccountSucceededDeviceSyncJobs(targetId: UUID, take: Int, cursor: String?) async throws -> CursorPageDTO<AccountSyncSucceededJobDTO>
    func listRootFolders() async throws -> [FolderDTO]
    func createFolder(name: String, parentId: UUID?) async throws -> FolderDTO
    func listFolderMedia(folderId: UUID, pageSize: Int, cursor: String?) async throws -> FolderContentDTO
    func streamUpload(
        fileURL: URL,
        fileName: String,
        folderId: UUID,
        mimeType: String,
        fileSize: Int64,
        progress: HTTPUploadProgressHandler?
    ) async throws -> StreamUploadResponse
    func initUpload(folderId: UUID, fileName: String, totalSize: Int64, totalChunks: Int) async throws -> InitUploadResponse
    func uploadChunk(
        uploadId: UUID,
        chunkIndex: Int,
        chunkSize: Int64,
        chunkFileURL: URL,
        progress: HTTPUploadProgressHandler?
    ) async throws
    func completeUpload(uploadId: UUID, fileHash: String?) async throws
}

extension NexusRelayAPI {
    func streamUpload(fileURL: URL, fileName: String, folderId: UUID, mimeType: String, fileSize: Int64) async throws -> StreamUploadResponse {
        try await streamUpload(
            fileURL: fileURL,
            fileName: fileName,
            folderId: folderId,
            mimeType: mimeType,
            fileSize: fileSize,
            progress: nil
        )
    }

    func uploadChunk(uploadId: UUID, chunkIndex: Int, chunkSize: Int64, chunkFileURL: URL) async throws {
        try await uploadChunk(
            uploadId: uploadId,
            chunkIndex: chunkIndex,
            chunkSize: chunkSize,
            chunkFileURL: chunkFileURL,
            progress: nil
        )
    }
}

extension JSONDecoder {
    static let apiDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ss"
        ]
        
        let formatters: [DateFormatter] = formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter
        }
        
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)
            
            for formatter in formatters {
                if let date = formatter.date(from: dateStr) {
                    return date
                }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateStr)")
        }
        return decoder
    }()
}

final class SystemNexusRelayAPIClient: NexusRelayAPI {
    private let baseURL: URL
    private let httpClient: HTTPClient
    private let sessionStore: SessionStore
    private let cookieStore: SessionCookieStore?

    init(
        baseURL: URL,
        httpClient: HTTPClient,
        sessionStore: SessionStore,
        cookieStore: SessionCookieStore? = nil
    ) {
        self.baseURL = baseURL
        self.httpClient = httpClient
        self.sessionStore = sessionStore
        self.cookieStore = cookieStore
    }

    func login(username: String, password: String) async throws -> AuthSession {
        clearBootstrapAuthArtifacts()
        let req = LoginRequest(username: username, password: password)
        let body = try JSONEncoder().encode(req)
        let request = HTTPRequest(method: "POST", path: "api/auth/login", headers: [:], body: body)
        let response = try await httpClient.send(request)
        
        guard response.statusCode == 200 else {
            throw APIError.loginFailed(statusCode: response.statusCode)
        }
        
        let decoder = JSONDecoder.apiDecoder
        let authResponse = try decoder.decode(BrowserAuthResponse.self, from: response.body)
        
        let responseCookies = Self.cookies(from: response.headers, for: baseURL)
        let cookies = responseCookies.isEmpty ? fallbackCookies() : responseCookies
        let session = AuthSession(userId: authResponse.id, username: authResponse.username, role: authResponse.role, cookies: cookies)
        try sessionStore.saveSession(session)
        return session
    }

    func exchangeIosSession(code: String) async throws -> AuthSession {
        clearBootstrapAuthArtifacts()
        let req = IosSessionExchangeRequest(code: code)
        let body = try JSONEncoder().encode(req)
        let request = HTTPRequest(method: "POST", path: "api/auth/ios/session-exchange", headers: [:], body: body)
        let response = try await httpClient.send(request)
        
        guard response.statusCode == 200 else {
            throw APIError.requestFailed(statusCode: response.statusCode, message: "Session exchange failed")
        }
        
        let decoder = JSONDecoder.apiDecoder
        let authResponse = try decoder.decode(BrowserAuthResponse.self, from: response.body)
        
        let responseCookies = Self.cookies(from: response.headers, for: baseURL)
        let cookies = responseCookies.isEmpty ? fallbackCookies() : responseCookies
        
        guard !cookies.isEmpty else {
            throw APIError.loginFailed(statusCode: response.statusCode)
        }
        
        let session = AuthSession(
            userId: authResponse.id,
            username: authResponse.username,
            role: authResponse.role,
            cookies: cookies,
            email: authResponse.email,
            authProvider: authResponse.authProvider
        )
        try sessionStore.saveSession(session)
        httpClient.clearCSRFToken()
        return session
    }

    func currentUser() async throws -> BrowserAuthResponse {
        let request = HTTPRequest(method: "GET", path: "api/auth/me", headers: [:], body: nil)
        let response = try await httpClient.send(request)
        
        guard response.statusCode == 200 else {
            throw APIError.requestFailed(statusCode: response.statusCode, message: "Failed to get current user")
        }
        
        return try JSONDecoder.apiDecoder.decode(BrowserAuthResponse.self, from: response.body)
    }

    func getAccountSyncDashboard() async throws -> AccountSyncDashboardDTO {
        let request = HTTPRequest(method: "GET", path: "api/device-sync/dashboard", headers: [:], body: nil)
        let response = try await httpClient.send(request)

        guard response.statusCode == 200 else {
            throw APIError.requestFailed(statusCode: response.statusCode, message: "Failed to get account sync dashboard")
        }

        return try JSONDecoder.apiDecoder.decode(AccountSyncDashboardDTO.self, from: response.body)
    }

    func getAccountSucceededDeviceSyncJobs(targetId: UUID, take: Int, cursor: String?) async throws -> CursorPageDTO<AccountSyncSucceededJobDTO> {
        var path = "api/device-sync/me/jobs/synced?targetId=\(targetId.uuidString.lowercased())&take=\(take)"
        if let cursor, !cursor.isEmpty {
            let queryValueAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))
            if let encodedCursor = cursor.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) {
                path += "&cursor=\(encodedCursor)"
            }
        }

        let request = HTTPRequest(method: "GET", path: path, headers: [:], body: nil)
        let response = try await httpClient.send(request)

        guard response.statusCode == 200 else {
            throw APIError.requestFailed(statusCode: response.statusCode, message: "Failed to get succeeded device sync jobs")
        }

        return try JSONDecoder.apiDecoder.decode(CursorPageDTO<AccountSyncSucceededJobDTO>.self, from: response.body)
    }

    func listRootFolders() async throws -> [FolderDTO] {
        let request = HTTPRequest(method: "GET", path: "api/folders", headers: [:], body: nil)
        let response = try await httpClient.send(request)
        
        guard response.statusCode == 200 else {
            throw APIError.requestFailed(statusCode: response.statusCode, message: "Failed to list folders")
        }
        
        return try JSONDecoder.apiDecoder.decode([FolderDTO].self, from: response.body)
    }

    func createFolder(name: String, parentId: UUID?) async throws -> FolderDTO {
        let req = CreateFolderRequest(name: name, parentId: parentId)
        let body = try JSONEncoder().encode(req)
        let request = HTTPRequest(method: "POST", path: "api/folders", headers: [:], body: body)
        let response = try await httpClient.send(request)
        
        guard response.statusCode == 201 else {
            throw APIError.requestFailed(statusCode: response.statusCode, message: "Failed to create folder")
        }
        
        return try JSONDecoder.apiDecoder.decode(FolderDTO.self, from: response.body)
    }

    func listFolderMedia(folderId: UUID, pageSize: Int, cursor: String?) async throws -> FolderContentDTO {
        var path = "api/folders/\(folderId.uuidString.lowercased())/media?mediaPageSize=\(pageSize)"
        if let cursor = cursor, !cursor.isEmpty {
            let queryValueAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))
            if let encodedCursor = cursor.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) {
                path += "&mediaCursor=\(encodedCursor)"
            }
        }
        let request = HTTPRequest(method: "GET", path: path, headers: [:], body: nil)
        let response = try await httpClient.send(request)
        
        guard response.statusCode == 200 else {
            throw APIError.requestFailed(statusCode: response.statusCode, message: "Failed to list folder media")
        }
        
        return try JSONDecoder.apiDecoder.decode(FolderContentDTO.self, from: response.body)
    }

    func streamUpload(
        fileURL: URL,
        fileName: String,
        folderId: UUID,
        mimeType: String,
        fileSize: Int64,
        progress: HTTPUploadProgressHandler?
    ) async throws -> StreamUploadResponse {
        // Percent encode file name for header
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: ":/"))
        let encodedName = fileName.addingPercentEncoding(withAllowedCharacters: allowed) ?? fileName
        
        let headers = [
            "x-file-name": encodedName,
            "x-folder-id": folderId.uuidString.lowercased(),
            "x-file-size": String(fileSize),
            "Content-Type": mimeType
        ]
        
        let request = HTTPRequest(method: "POST", path: "api/upload/stream", headers: headers, body: nil)
        let response = try await httpClient.uploadFile(request, fileURL: fileURL, progress: progress)
        
        guard response.statusCode == 200 else {
            throw APIError.requestFailed(statusCode: response.statusCode, message: "Stream upload failed")
        }
        
        return try JSONDecoder.apiDecoder.decode(StreamUploadResponse.self, from: response.body)
    }

    func initUpload(folderId: UUID, fileName: String, totalSize: Int64, totalChunks: Int) async throws -> InitUploadResponse {
        let req = InitUploadRequest(folderId: folderId, fileName: fileName, totalSize: totalSize, totalChunks: totalChunks)
        let body = try JSONEncoder().encode(req)
        let request = HTTPRequest(method: "POST", path: "api/upload/init", headers: [:], body: body)
        let response = try await httpClient.send(request)
        
        guard response.statusCode == 200 else {
            throw APIError.requestFailed(statusCode: response.statusCode, message: "Init chunked upload failed")
        }
        
        return try JSONDecoder.apiDecoder.decode(InitUploadResponse.self, from: response.body)
    }

    func uploadChunk(
        uploadId: UUID,
        chunkIndex: Int,
        chunkSize: Int64,
        chunkFileURL: URL,
        progress: HTTPUploadProgressHandler?
    ) async throws {
        let headers = [
            "x-upload-id": uploadId.uuidString.lowercased(),
            "x-chunk-index": String(chunkIndex),
            "x-chunk-size": String(chunkSize),
            "Content-Type": "application/octet-stream"
        ]
        
        let request = HTTPRequest(method: "POST", path: "api/upload/chunk", headers: headers, body: nil)
        let response = try await httpClient.uploadFile(request, fileURL: chunkFileURL, progress: progress)
        
        guard response.statusCode == 200 else {
            throw APIError.requestFailed(statusCode: response.statusCode, message: "Upload chunk failed")
        }
    }

    func completeUpload(uploadId: UUID, fileHash: String?) async throws {
        let req = CompleteUploadRequest(uploadId: uploadId, fileHash: fileHash)
        let body = try JSONEncoder().encode(req)
        let request = HTTPRequest(method: "POST", path: "api/upload/complete", headers: [:], body: body)
        let response = try await httpClient.send(request)
        
        guard response.statusCode == 200 else {
            throw APIError.requestFailed(statusCode: response.statusCode, message: "Complete chunked upload failed")
        }
    }

    private static func cookies(from headers: [AnyHashable: Any], for url: URL) -> [HTTPCookie] {
        var headerFields: [String: String] = [:]

        for (key, value) in headers {
            guard let headerName = key as? String else { continue }
            if let headerValue = value as? String {
                headerFields[headerName] = headerValue
            }
        }

        return HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
            .filter { $0.name == "access_token" || $0.name == "refresh_token" }
    }

    private func fallbackCookies() -> [HTTPCookie] {
        if let cookieStore {
            return cookieStore.sessionCookies(for: baseURL)
        }

        return []
    }

    private func clearBootstrapAuthArtifacts() {
        try? sessionStore.clearSession()
        cookieStore?.clearManagedCookies(for: baseURL)
        httpClient.clearCSRFToken()
    }
}
