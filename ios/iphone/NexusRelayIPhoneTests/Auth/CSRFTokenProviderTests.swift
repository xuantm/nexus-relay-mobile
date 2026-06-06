import XCTest
@testable import NexusRelayIPhone

final class CSRFTokenProviderTests: XCTestCase {
    private var csrfProvider: SystemCSRFTokenProvider!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        csrfProvider = SystemCSRFTokenProvider(urlSession: session)
    }

    override func tearDown() {
        csrfProvider = nil
        session = nil
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testGetCSRFTokenSuccess() async throws {
        let expectedToken = "test-csrf-token"
        let baseURL = URL(string: "https://relay.xuantruong.org")!
        
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/auth/csrf")
            XCTAssertEqual(request.httpMethod, "GET")
            
            let json = "{\"token\": \"\(expectedToken)\"}".data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let token = try await csrfProvider.getCSRFToken(baseURL: baseURL, forceRefresh: false)
        XCTAssertEqual(token, expectedToken)
    }

    func testGetCSRFTokenCaches() async throws {
        let expectedToken = "test-csrf-token"
        let baseURL = URL(string: "https://relay.xuantruong.org")!
        var requestCount = 0
        
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            let json = "{\"token\": \"\(expectedToken)\"}".data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let token1 = try await csrfProvider.getCSRFToken(baseURL: baseURL, forceRefresh: false)
        let token2 = try await csrfProvider.getCSRFToken(baseURL: baseURL, forceRefresh: false)
        
        XCTAssertEqual(token1, expectedToken)
        XCTAssertEqual(token2, expectedToken)
        XCTAssertEqual(requestCount, 1)
    }

    func testGetCSRFTokenForceRefresh() async throws {
        let expectedToken = "test-csrf-token"
        let baseURL = URL(string: "https://relay.xuantruong.org")!
        var requestCount = 0
        
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            let json = "{\"token\": \"\(expectedToken)-\(requestCount)\"}".data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let token1 = try await csrfProvider.getCSRFToken(baseURL: baseURL, forceRefresh: false)
        let token2 = try await csrfProvider.getCSRFToken(baseURL: baseURL, forceRefresh: true)
        
        XCTAssertEqual(token1, "test-csrf-token-1")
        XCTAssertEqual(token2, "test-csrf-token-2")
        XCTAssertEqual(requestCount, 2)
    }
}

// MARK: - MockURLProtocol for Testing
final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("Handler is not set.")
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
