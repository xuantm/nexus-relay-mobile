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
                    "status": "Completed",
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
                        "status": "Completed",
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
        XCTAssertEqual(content.media?.items.count, 1)
        XCTAssertEqual(content.media?.items.first?.fileName, "IMG_1001__nr-a3f91c0d8e74b210.HEIC")
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
}
