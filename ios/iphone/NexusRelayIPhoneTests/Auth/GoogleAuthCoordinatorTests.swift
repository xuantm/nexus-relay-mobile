import XCTest
@testable import NexusRelayIPhone

final class MockWebAuthenticationSession: WebAuthenticationSession {
    var startCalledUrl: URL?
    var startCalledCallbackScheme: String?
    var resultURL: URL?
    var errorToThrow: Error?
    
    func start(url: URL, callbackScheme: String) async throws -> URL {
        startCalledUrl = url
        startCalledCallbackScheme = callbackScheme
        
        if let error = errorToThrow {
            throw error
        }
        
        return resultURL ?? URL(string: "nexusrelay://auth/invalid")!
    }
}

final class GoogleAuthCoordinatorTests: XCTestCase {
    func testSignInBuildsCorrectURLAndReturnsResult() async throws {
        let mockSession = MockWebAuthenticationSession()
        mockSession.resultURL = URL(string: "nexusrelay://auth/success?code=code_123")
        
        let coordinator = GoogleAuthCoordinator(session: mockSession)
        let baseURL = URL(string: "https://relay.example.com")!
        
        let result = try await coordinator.signIn(baseURL: baseURL)
        
        XCTAssertEqual(mockSession.startCalledCallbackScheme, "nexusrelay")
        XCTAssertNotNil(mockSession.startCalledUrl)
        XCTAssertEqual(mockSession.startCalledUrl?.host, "relay.example.com")
        XCTAssertEqual(mockSession.startCalledUrl?.path, "/api/auth/google/login")
        
        let components = URLComponents(url: mockSession.startCalledUrl!, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "client" })?.value, "ios")
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "returnUrl" })?.value, "nexusrelay://auth/success")
        
        XCTAssertEqual(result, .success(code: "code_123"))
    }
}
