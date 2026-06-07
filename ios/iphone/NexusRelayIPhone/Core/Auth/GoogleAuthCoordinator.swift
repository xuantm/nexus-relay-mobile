import Foundation
import AuthenticationServices
import UIKit

protocol WebAuthenticationSession {
    func start(url: URL, callbackScheme: String) async throws -> URL
}

@MainActor
class SystemWebAuthenticationSession: NSObject, WebAuthenticationSession, ASWebAuthenticationPresentationContextProviding {
    func start(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let callbackURL = callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: NSError(domain: "SystemWebAuthenticationSession", code: -1, userInfo: [NSLocalizedDescriptionKey: "No URL or error returned"]))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
            return window
        }
        return ASPresentationAnchor()
    }
}

protocol GoogleAuthCoordinating {
    func signIn(baseURL: URL) async throws -> AuthCallbackResult
}

final class GoogleAuthCoordinator: GoogleAuthCoordinating {
    private let session: WebAuthenticationSession
    private let callbackScheme = "nexusrelay"

    init(session: WebAuthenticationSession = SystemWebAuthenticationSession()) {
        self.session = session
    }

    func signIn(baseURL: URL) async throws -> AuthCallbackResult {
        let loginURL = baseURL.appendingPathComponent("api/auth/google/login")
        var components = URLComponents(url: loginURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client", value: "ios"),
            URLQueryItem(name: "returnUrl", value: "nexusrelay://auth/success")
        ]
        
        guard let finalURL = components?.url else {
            throw APIError.invalidURL
        }
        
        let callbackURL = try await session.start(url: finalURL, callbackScheme: callbackScheme)
        return AuthCallbackURL.parse(callbackURL)
    }
}
