import XCTest
@testable import NexusRelayIPhone

final class NexusRelayAPIClientExchangeTests: XCTestCase {
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
        
        httpClient = SystemHTTPClient(baseURL: baseURL, sessionStore: sessionStore, csrfProvider: csrfProvider, controlSession: urlSession)
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

    func testExchangeIosSessionSuccess() async throws {
        let exchangeResponseJSON = """
        {
            "id": "3a3fa2f3-2953-4a8e-8d55-6689cb299e90",
            "username": "google_user",
            "email": "user@gmail.com",
            "role": "User",
            "authProvider": "Google"
        }
        """
        
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/auth/ios/session-exchange")
            XCTAssertEqual(request.httpMethod, "POST")
            
            let json = exchangeResponseJSON.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Set-Cookie": "access_token=google_jwt; Path=/; HttpOnly"]
            )!
            return (response, json)
        }

        let session = try await apiClient.exchangeIosSession(code: "exchange_code_123")
        XCTAssertEqual(session.userId, UUID(uuidString: "3a3fa2f3-2953-4a8e-8d55-6689cb299e90"))
        XCTAssertEqual(session.username, "google_user")
        XCTAssertEqual(session.email, "user@gmail.com")
        XCTAssertEqual(session.role, "User")
        XCTAssertEqual(session.authProvider, "Google")
        XCTAssertTrue(session.isAuthenticated)
        XCTAssertEqual(session.cookies.count, 1)
        XCTAssertEqual(session.cookies.first?.name, "access_token")
        XCTAssertEqual(session.cookies.first?.value, "google_jwt")
        XCTAssertEqual(sessionStore.currentSession, session)
        XCTAssertEqual(csrfProvider.clearCount, 2)
    }

    func testExchangeIosSessionClearsStaleRuntimeCookiesBeforeSavingNewSession() async throws {
        let oldAccess = HTTPCookie(properties: [
            .name: "access_token",
            .value: "old_jwt",
            .domain: "relay.xuantruong.org",
            .path: "/"
        ])!
        let oldCsrf = HTTPCookie(properties: [
            .name: "nexus_csrf",
            .value: "old_csrf",
            .domain: "relay.xuantruong.org",
            .path: "/"
        ])!
        let cookieStore = SessionCookieStore(storage: URLSessionConfiguration.ephemeral.httpCookieStorage)
        cookieStore.replaceSessionCookies([oldAccess], for: baseURL)
        let csrfResponse = HTTPURLResponse(
            url: baseURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Set-Cookie": "\(oldCsrf.name)=\(oldCsrf.value); Path=/; HttpOnly"]
        )!
        cookieStore.storeResponseCookies(from: csrfResponse, for: baseURL)
        sessionStore.currentSession = AuthSession(userId: UUID(), username: "old_user", role: "User", cookies: [oldAccess])

        httpClient = SystemHTTPClient(
            baseURL: baseURL,
            sessionStore: sessionStore,
            csrfProvider: csrfProvider,
            controlSession: urlSession,
            cookieStore: cookieStore
        )
        apiClient = SystemNexusRelayAPIClient(
            baseURL: baseURL,
            httpClient: httpClient,
            sessionStore: sessionStore,
            cookieStore: cookieStore
        )

        let exchangeResponseJSON = """
        {
            "id": "3a3fa2f3-2953-4a8e-8d55-6689cb299e90",
            "username": "google_user",
            "email": "user@gmail.com",
            "role": "User",
            "authProvider": "Google"
        }
        """

        MockURLProtocol.requestHandler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            let json = exchangeResponseJSON.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Set-Cookie": "access_token=google_jwt; Path=/; HttpOnly"]
            )!
            return (response, json)
        }

        let session = try await apiClient.exchangeIosSession(code: "exchange_code_123")

        XCTAssertEqual(session.cookies.map(\.name), ["access_token"])
        XCTAssertEqual(session.cookies.first?.value, "google_jwt")
        XCTAssertFalse(cookieStore.cookies(for: baseURL).contains(where: { $0.value == "old_jwt" || $0.value == "old_csrf" }))
    }

    func testExchangeIosSessionFailsWithoutCookies() async throws {
        let exchangeResponseJSON = """
        {
            "id": "3a3fa2f3-2953-4a8e-8d55-6689cb299e90",
            "username": "google_user",
            "role": "User"
        }
        """
        
        MockURLProtocol.requestHandler = { request in
            let json = exchangeResponseJSON.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [:] // Empty headers/no cookies
            )!
            return (response, json)
        }

        do {
            _ = try await apiClient.exchangeIosSession(code: "code")
            XCTFail("Should throw loginFailed error due to missing cookies")
        } catch {
            // Expected error
        }
    }
}
