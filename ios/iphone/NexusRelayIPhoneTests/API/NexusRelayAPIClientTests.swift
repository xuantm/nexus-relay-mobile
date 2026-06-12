import XCTest
@testable import NexusRelayIPhone

final class MockSessionStore: SessionStore {
    var currentSession: AuthSession?
    func saveSession(_ session: AuthSession) throws {
        currentSession = session
    }
    func loadSession() -> AuthSession? {
        return currentSession
    }
    func clearSession() throws {
        currentSession = nil
    }
}

final class MockCSRFTokenProvider: CSRFTokenProvider {
    var tokenValue = "mock-csrf-token"
    var clearCount = 0
    func getCSRFToken(baseURL: URL, forceRefresh: Bool) async throws -> String {
        return tokenValue
    }
    func clearToken() {
        clearCount += 1
    }
}

actor ProgressRecorder {
    private(set) var events: [HTTPUploadProgress] = []

    func record(_ progress: HTTPUploadProgress) {
        events.append(progress)
    }
}

final class RecordingHTTPClient: HTTPClient {
    var uploadResponse = HTTPResponse(
        statusCode: 200,
        headers: [:],
        body: Data(#"{"uploadId":"00000000-0000-0000-0000-000000000001"}"#.utf8)
    )
    var receivedUploadProgressHandler: HTTPUploadProgressHandler?
    var uploadRequests: [HTTPRequest] = []

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        fatalError("send() is not used in this test")
    }

    func uploadFile(
        _ request: HTTPRequest,
        fileURL: URL,
        progress: HTTPUploadProgressHandler?
    ) async throws -> HTTPResponse {
        uploadRequests.append(request)
        receivedUploadProgressHandler = progress
        if let progress {
            await progress(HTTPUploadProgress(bytesSent: 128, totalBytes: 256))
        }
        return uploadResponse
    }

    func clearCSRFToken() {}
}

final class NexusRelayAPIClientTests: XCTestCase {
    private var baseURL: URL!
    private var sessionStore: MockSessionStore!
    private var csrfProvider: MockCSRFTokenProvider!
    private var httpClient: SystemHTTPClient!
    private var apiClient: SystemNexusRelayAPIClient!
    private var urlSession: URLSession!

    override func setUp() {
        super.setUp()
        baseURL = URL(string: "https://relay.xuantruong.org")!
        sessionStore = MockSessionStore()
        csrfProvider = MockCSRFTokenProvider()
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        urlSession = URLSession(configuration: config)
        
        httpClient = SystemHTTPClient(baseURL: baseURL, sessionStore: sessionStore, csrfProvider: csrfProvider, urlSession: urlSession)
        apiClient = SystemNexusRelayAPIClient(baseURL: baseURL, httpClient: httpClient, sessionStore: sessionStore)
    }

    override func tearDown() {
        baseURL = nil
        sessionStore = nil
        csrfProvider = nil
        httpClient = nil
        apiClient = nil
        urlSession = nil
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testLoginSuccess() async throws {
        let authResponseJSON = """
        {
            "id": "3a3fa2f3-2953-4a8e-8d55-6689cb299e90",
            "username": "xuan",
            "role": "Admin"
        }
        """
        
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/auth/login")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-NexusRelay-CSRF"), "mock-csrf-token")
            
            let json = authResponseJSON.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Set-Cookie": "access_token=jwt_token_here; Path=/; HttpOnly"]
            )!
            return (response, json)
        }

        let session = try await apiClient.login(username: "xuan", password: "password")
        XCTAssertEqual(session.userId, UUID(uuidString: "3a3fa2f3-2953-4a8e-8d55-6689cb299e90"))
        XCTAssertEqual(session.username, "xuan")
        XCTAssertEqual(session.role, "Admin")
        XCTAssertTrue(session.isAuthenticated)
        XCTAssertEqual(session.cookies.count, 1)
        XCTAssertEqual(session.cookies.first?.name, "access_token")
        XCTAssertEqual(sessionStore.currentSession, session)
    }

    func testListRootFoldersSuccess() async throws {
        sessionStore.currentSession = AuthSession(
            userId: UUID(),
            username: "xuan",
            role: "Admin",
            cookies: []
        )
        
        let foldersJSON = """
        [
            {
                "id": "1f16e90d-6ddb-43fc-8e30-61a71e2e5005",
                "name": "iPhone Uploads",
                "parentId": null,
                "googleDriveFolderId": "drive-id",
                "createdAt": "2026-06-05T12:00:00Z",
                "childCount": 0,
                "mediaCount": 5
            }
        ]
        """
        
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/folders")
            XCTAssertEqual(request.httpMethod, "GET")
            // GET request doesn't need CSRF token header
            XCTAssertNil(request.value(forHTTPHeaderField: "X-NexusRelay-CSRF"))
            
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, foldersJSON.data(using: .utf8)!)
        }

        let folders = try await apiClient.listRootFolders()
        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders.first?.name, "iPhone Uploads")
        XCTAssertEqual(folders.first?.id, UUID(uuidString: "1f16e90d-6ddb-43fc-8e30-61a71e2e5005"))
    }

    func testListFolderMediaDecodesFolderContentDto() async throws {
        sessionStore.currentSession = AuthSession(
            userId: UUID(),
            username: "xuan",
            role: "Admin",
            cookies: []
        )
        
        let folderContentJSON = """
        {
            "folder": {
                "id": "1f16e90d-6ddb-43fc-8e30-61a71e2e5005",
                "name": "iPhone Uploads",
                "parentId": null,
                "googleDriveFolderId": "drive-id",
                "createdAt": "2026-06-05T12:00:00Z",
                "childCount": 0,
                "mediaCount": 1
            },
            "subFolders": [],
            "mediaItems": [
                {
                    "id": "94aa00ac-219a-4d65-8ff4-11ffc7a042e1",
                    "folderId": "1f16e90d-6ddb-43fc-8e30-61a71e2e5005",
                    "fileName": "IMG_1001__nr-a3f91c0d8e74b210.HEIC",
                    "size": 4820131,
                    "mimeType": "image/heic",
                    "status": "Buffering",
                    "uploadStatus": "Uploaded",
                    "mediaType": "Image",
                    "thumbnailGenerated": true,
                    "createdAt": "2026-06-05T12:00:00Z"
                }
            ],
            "breadcrumbs": [],
            "page": 1,
            "pageSize": 60,
            "hasMore": false,
            "nextCursor": null,
            "media": {
                "items": [
                    {
                        "id": "94aa00ac-219a-4d65-8ff4-11ffc7a042e1",
                        "folderId": "1f16e90d-6ddb-43fc-8e30-61a71e2e5005",
                        "fileName": "IMG_1001__nr-a3f91c0d8e74b210.HEIC",
                        "size": 4820131,
                        "mimeType": "image/heic",
                        "status": "Relaying",
                        "uploadStatus": "Uploaded",
                        "mediaType": "Image",
                        "thumbnailGenerated": true,
                        "createdAt": "2026-06-05T12:00:00Z"
                    }
                ],
                "pageSize": 60,
                "hasMore": false,
                "nextCursor": null
            },
            "folders": {
                "items": [],
                "page": 1,
                "pageSize": 60,
                "hasMore": false,
                "nextPage": null
            }
        }
        """
        
        let folderId = UUID(uuidString: "1f16e90d-6ddb-43fc-8e30-61a71e2e5005")!
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/folders/\(folderId.uuidString.lowercased())/media")
            XCTAssertEqual(request.url?.query, "mediaPageSize=60")
            
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, folderContentJSON.data(using: .utf8)!)
        }

        let content = try await apiClient.listFolderMedia(folderId: folderId, pageSize: 60, cursor: nil)
        XCTAssertEqual(content.folder.name, "iPhone Uploads")
        XCTAssertEqual(content.mediaItems?.count, 1)
        XCTAssertEqual(content.mediaItems?.first?.fileName, "IMG_1001__nr-a3f91c0d8e74b210.HEIC")
        XCTAssertEqual(content.mediaItems?.first?.status, .buffering)
        XCTAssertEqual(content.mediaItems?.first?.uploadStatus, .Uploaded)
        XCTAssertEqual(content.media?.items.count, 1)
        XCTAssertEqual(content.media?.items.first?.fileName, "IMG_1001__nr-a3f91c0d8e74b210.HEIC")
        XCTAssertEqual(content.media?.items.first?.status, .relaying)
        XCTAssertEqual(content.media?.items.first?.uploadStatus, .Uploaded)
    }

    func testListFolderMediaUsesMediaCursorQueryParameter() async throws {
        sessionStore.currentSession = AuthSession(
            userId: UUID(),
            username: "xuan",
            role: "Admin",
            cookies: []
        )

        let folderId = UUID(uuidString: "1f16e90d-6ddb-43fc-8e30-61a71e2e5005")!
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/folders/\(folderId.uuidString.lowercased())/media")
            XCTAssertEqual(request.url?.query, "mediaPageSize=60&mediaCursor=cursor-token")

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = """
            {
                "folder": {
                    "id": "1f16e90d-6ddb-43fc-8e30-61a71e2e5005",
                    "name": "iPhone Uploads",
                    "parentId": null,
                    "googleDriveFolderId": null,
                    "createdAt": "2026-06-05T12:00:00Z",
                    "childCount": 0,
                    "mediaCount": 0
                },
                "subFolders": [],
                "mediaItems": [],
                "media": {
                    "items": [],
                    "pageSize": 60,
                    "hasMore": false,
                    "nextCursor": null
                }
            }
            """
            return (response, json.data(using: .utf8)!)
        }

        _ = try await apiClient.listFolderMedia(folderId: folderId, pageSize: 60, cursor: "cursor-token")
    }

    func testGetAccountSyncDashboardDecodesCurrentJobOnEachDevice() async throws {
        sessionStore.currentSession = AuthSession(
            userId: UUID(),
            username: "xuan",
            role: "Admin",
            cookies: []
        )

        let dashboardJSON = """
        {
            "overview": {
                "completedUploads": 12,
                "failedUploads": 1,
                "syncedToDevices": 42,
                "failedDeviceSyncJobs": 2,
                "stalledDeviceSyncJobs": 1,
                "activeDeviceSyncJobs": 3,
                "activeDevices": 1
            },
            "devices": [
                {
                    "targetId": "2d6c4f66-5be2-4f31-8c2f-02ac2e1a55ee",
                    "deviceName": "Pixel 8",
                    "platform": "Android",
                    "enabled": true,
                    "wifiOnly": true,
                    "syncScope": "AccountUploads",
                    "scopedFolderId": null,
                    "lastSeenAt": "2026-06-11T09:00:00Z",
                    "isActive": true,
                    "pendingJobs": 0,
                    "syncingJobs": 1,
                    "stalledJobs": 0,
                    "failedJobs": 0,
                    "syncedJobs": 18,
                    "currentJob": {
                        "jobId": "11111111-1111-1111-1111-111111111111",
                        "mediaId": "22222222-2222-2222-2222-222222222222",
                        "fileName": "IMG_1001.HEIC",
                        "mimeType": "image/heic",
                        "mediaType": "Image",
                        "sizeBytes": 4820131,
                        "attemptNumber": 2,
                        "stage": "Downloading",
                        "progressBytes": 2410065,
                        "totalBytes": 4820131,
                        "claimedAt": "2026-06-11T08:55:00Z",
                        "lastHeartbeatAt": "2026-06-11T09:01:00Z",
                        "leaseExpiresAt": "2026-06-11T09:16:00Z",
                        "workerRunId": "run-1"
                    }
                }
            ],
            "failedJobs": [],
            "stalledJobs": [],
            "failedUploads": []
        }
        """

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/device-sync/dashboard")
            XCTAssertEqual(request.httpMethod, "GET")

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, dashboardJSON.data(using: .utf8)!)
        }

        let dashboard = try await apiClient.getAccountSyncDashboard()
        XCTAssertEqual(dashboard.overview.completedUploads, 12)
        XCTAssertEqual(dashboard.devices.count, 1)
        XCTAssertEqual(dashboard.devices.first?.deviceName, "Pixel 8")
        XCTAssertEqual(dashboard.devices.first?.syncScope, .AccountUploads)
        XCTAssertEqual(
            dashboard.devices.first?.currentJob?.jobId,
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")
        )
        XCTAssertEqual(dashboard.devices.first?.currentJob?.displayStateText, "Downloading")
        XCTAssertEqual(dashboard.devices.first?.currentJob?.progressFraction ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(dashboard.devices.first?.pendingJobs, 0)
    }

    func testStreamUploadForwardsProgressHandlerToHTTPClient() async throws {
        let recordingHTTPClient = RecordingHTTPClient()
        let apiClient = SystemNexusRelayAPIClient(baseURL: baseURL, httpClient: recordingHTTPClient, sessionStore: sessionStore)

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("dummy-content".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let recorder = ProgressRecorder()
        let response = try await apiClient.streamUpload(
            fileURL: fileURL,
            fileName: "IMG_1001.HEIC",
            folderId: UUID(),
            mimeType: "image/heic",
            fileSize: 12_345,
            progress: { progress in
                await recorder.record(progress)
            }
        )

        XCTAssertEqual(response.uploadId, UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        XCTAssertNotNil(recordingHTTPClient.receivedUploadProgressHandler)
        let events = await recorder.events
        XCTAssertEqual(events, [HTTPUploadProgress(bytesSent: 128, totalBytes: 256)])
    }

    func testUploadChunkForwardsProgressHandlerToHTTPClient() async throws {
        let recordingHTTPClient = RecordingHTTPClient()
        recordingHTTPClient.uploadResponse = HTTPResponse(statusCode: 200, headers: [:], body: Data())
        let apiClient = SystemNexusRelayAPIClient(baseURL: baseURL, httpClient: recordingHTTPClient, sessionStore: sessionStore)

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("chunk-content".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let recorder = ProgressRecorder()
        try await apiClient.uploadChunk(
            uploadId: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            chunkIndex: 3,
            chunkSize: 13,
            chunkFileURL: fileURL,
            progress: { progress in
                await recorder.record(progress)
            }
        )

        XCTAssertEqual(recordingHTTPClient.uploadRequests.first?.path, "api/upload/chunk")
        XCTAssertNotNil(recordingHTTPClient.receivedUploadProgressHandler)
        let events = await recorder.events
        XCTAssertEqual(events, [HTTPUploadProgress(bytesSent: 128, totalBytes: 256)])
    }

    func testHTTPClientTransparent401RefreshSuccess() async throws {
        sessionStore.currentSession = AuthSession(
            userId: UUID(),
            username: "xuan",
            role: "Admin",
            cookies: [HTTPCookie(properties: [.name: "access_token", .value: "old_jwt", .domain: "relay.xuantruong.org", .path: "/"])!]
        )
        
        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            
            if request.url?.path == "/api/folders" {
                if requestCount == 1 {
                    // Fail with 401 Unauthorized
                    let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                    return (response, Data())
                } else {
                    // Retry succeeds
                    let json = "[]".data(using: .utf8)!
                    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (response, json)
                }
            } else if request.url?.path == "/api/auth/refresh" {
                XCTAssertEqual(request.httpMethod, "POST")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Set-Cookie": "access_token=new_jwt; Path=/; HttpOnly"]
                )!
                return (response, Data())
            } else {
                XCTFail("Unexpected request: \(request.url?.path ?? "")")
                throw NSError(domain: "test", code: -1)
            }
        }

        let folders = try await apiClient.listRootFolders()
        XCTAssertTrue(folders.isEmpty)
        XCTAssertEqual(requestCount, 3) // 1: GET folders (401), 2: POST refresh (200), 3: GET folders (200)
        XCTAssertEqual(sessionStore.currentSession?.cookies.first?.value, "new_jwt")
    }

    func testHTTPClientTransparent401RefreshPreservesOtherCookies() async throws {
        sessionStore.currentSession = AuthSession(
            userId: UUID(),
            username: "xuan",
            role: "Admin",
            cookies: [
                HTTPCookie(properties: [.name: "access_token", .value: "old_jwt", .domain: "relay.xuantruong.org", .path: "/"])!,
                HTTPCookie(properties: [.name: "refresh_token", .value: "my_refresh_token", .domain: "relay.xuantruong.org", .path: "/"])!
            ]
        )
        
        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            
            if request.url?.path == "/api/folders" {
                if requestCount == 1 {
                    // Fail with 401 Unauthorized
                    let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                    return (response, Data())
                } else {
                    // Retry succeeds
                    let json = "[]".data(using: .utf8)!
                    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (response, json)
                }
            } else if request.url?.path == "/api/auth/refresh" {
                XCTAssertEqual(request.httpMethod, "POST")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Set-Cookie": "access_token=new_jwt; Path=/; HttpOnly"]
                )!
                return (response, Data())
            } else {
                XCTFail("Unexpected request: \(request.url?.path ?? "")")
                throw NSError(domain: "test", code: -1)
            }
        }

        let folders = try await apiClient.listRootFolders()
        XCTAssertTrue(folders.isEmpty)
        XCTAssertEqual(requestCount, 3)
        
        let cookies = sessionStore.currentSession?.cookies ?? []
        XCTAssertEqual(cookies.count, 2)
        XCTAssertTrue(cookies.contains(where: { $0.name == "access_token" && $0.value == "new_jwt" }))
        XCTAssertTrue(cookies.contains(where: { $0.name == "refresh_token" && $0.value == "my_refresh_token" }))
    }

    func testHTTPClientTransparent401RefreshRetryFailurePreservesOtherCookies() async throws {
        sessionStore.currentSession = AuthSession(
            userId: UUID(),
            username: "xuan",
            role: "Admin",
            cookies: [
                HTTPCookie(properties: [.name: "access_token", .value: "old_jwt", .domain: "relay.xuantruong.org", .path: "/"])!,
                HTTPCookie(properties: [.name: "refresh_token", .value: "my_refresh_token", .domain: "relay.xuantruong.org", .path: "/"])!
            ]
        )
        
        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            
            if request.url?.path == "/api/folders" {
                if requestCount == 1 {
                    // Fail with 401 Unauthorized
                    let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                    return (response, Data())
                } else {
                    // Retry fails with network error
                    throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost, userInfo: nil)
                }
            } else if request.url?.path == "/api/auth/refresh" {
                XCTAssertEqual(request.httpMethod, "POST")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Set-Cookie": "access_token=new_jwt; Path=/; HttpOnly"]
                )!
                return (response, Data())
            } else {
                XCTFail("Unexpected request: \(request.url?.path ?? "")")
                throw NSError(domain: "test", code: -1)
            }
        }

        do {
            _ = try await apiClient.listRootFolders()
            XCTFail("Should have thrown 500 error")
        } catch {
            // Expected
        }
        
        XCTAssertEqual(requestCount, 3)
        
        let cookies = sessionStore.currentSession?.cookies ?? []
        XCTAssertEqual(cookies.count, 2)
        XCTAssertTrue(cookies.contains(where: { $0.name == "access_token" && $0.value == "new_jwt" }))
        XCTAssertTrue(cookies.contains(where: { $0.name == "refresh_token" && $0.value == "my_refresh_token" }))
    }



    func testHTTPClientTransparentUploadNetworkErrorRefreshSuccess() async throws {
        sessionStore.currentSession = AuthSession(
            userId: UUID(),
            username: "xuan",
            role: "Admin",
            cookies: [HTTPCookie(properties: [.name: "access_token", .value: "old_jwt", .domain: "relay.xuantruong.org", .path: "/"])!]
        )
        
        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            
            if request.url?.path == "/api/upload/stream" {
                if requestCount == 1 {
                    // Fail with Cannot Parse Response (-1017)
                    throw NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotParseResponse, userInfo: nil)
                } else {
                    // Retry succeeds
                    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (response, "{\"uploadId\":\"\(UUID().uuidString)\"}".data(using: .utf8)!)
                }
            } else if request.url?.path == "/api/auth/refresh" {
                XCTAssertEqual(request.httpMethod, "POST")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Set-Cookie": "access_token=new_jwt; Path=/; HttpOnly"]
                )!
                return (response, Data())
            } else {
                XCTFail("Unexpected request: \(request.url?.path ?? "")")
                throw NSError(domain: "test", code: -1)
            }
        }

        // We need a dummy file to upload
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "dummy-content".data(using: .utf8)!.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let req = HTTPRequest(method: "POST", path: "api/upload/stream", headers: [:], body: nil)
        let recorder = ProgressRecorder()
        let response = try await httpClient.uploadFile(
            req,
            fileURL: fileURL,
            progress: { progress in
                await recorder.record(progress)
            }
        )
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(requestCount, 3) // 1: POST upload (fail -1017), 2: POST refresh (200), 3: POST upload (200)
        XCTAssertEqual(sessionStore.currentSession?.cookies.first?.value, "new_jwt")
    }

    func testHTTPClientRefreshFailureClearsSessionCookiesAndCSRF() async throws {
        let access = HTTPCookie(properties: [
            .name: "access_token",
            .value: "old_jwt",
            .domain: "relay.xuantruong.org",
            .path: "/"
        ])!
        let refresh = HTTPCookie(properties: [
            .name: "refresh_token",
            .value: "bad_refresh",
            .domain: "relay.xuantruong.org",
            .path: "/"
        ])!
        let cookieStore = SessionCookieStore(storage: URLSessionConfiguration.ephemeral.httpCookieStorage)
        sessionStore.currentSession = AuthSession(userId: UUID(), username: "xuan", role: "Admin", cookies: [access, refresh])
        csrfProvider.tokenValue = "stale-csrf"
        httpClient = SystemHTTPClient(
            baseURL: baseURL,
            sessionStore: sessionStore,
            csrfProvider: csrfProvider,
            urlSession: urlSession,
            cookieStore: cookieStore
        )
        apiClient = SystemNexusRelayAPIClient(baseURL: baseURL, httpClient: httpClient, sessionStore: sessionStore)

        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            if request.url?.path == "/api/folders" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            if request.url?.path == "/api/auth/refresh" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            XCTFail("Unexpected request: \(request.url?.path ?? "")")
            throw NSError(domain: "test", code: -1)
        }

        do {
            _ = try await apiClient.listRootFolders()
            XCTFail("Expected request failure")
        } catch {
            XCTAssertNil(sessionStore.currentSession)
            XCTAssertTrue(cookieStore.cookies(for: baseURL).isEmpty)
            XCTAssertEqual(csrfProvider.clearCount, 1)
        }
        XCTAssertEqual(requestCount, 2)
    }
}
