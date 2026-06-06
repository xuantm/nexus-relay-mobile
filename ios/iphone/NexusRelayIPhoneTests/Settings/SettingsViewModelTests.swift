import Foundation
import XCTest
@testable import NexusRelayIPhone

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testLoadShowsCurrentUsernameAndPhotosAccess() {
        let settingsStore = MockSettingsStore()
        settingsStore.settings.backendBaseURL = URL(string: "https://relay.example.com")
        settingsStore.settings.destinationFolderName = "Uploads"

        let sessionStore = MockSessionStore()
        sessionStore.currentSession = AuthSession(
            userId: UUID(),
            username: "xuan",
            role: "Admin",
            cookies: [makeCookie()]
        )

        let viewModel = SettingsViewModel(
            settingsStore: settingsStore,
            photosScanner: SettingsTestPhotoLibraryClient(status: .limited),
            sessionStore: sessionStore
        )

        XCTAssertEqual(viewModel.username, "xuan")
        XCTAssertEqual(viewModel.photosAccessText, "Limited access")
        XCTAssertEqual(viewModel.folderName, "Uploads")
    }

    private func makeCookie() -> HTTPCookie {
        HTTPCookie(properties: [
            .domain: "relay.example.com",
            .path: "/",
            .name: "access_token",
            .value: "token",
            .secure: "TRUE"
        ])!
    }
}

private final class SettingsTestPhotoLibraryClient: PhotoLibraryClient {
    private let status: PhotoLibraryAuthorizationStatus

    init(status: PhotoLibraryAuthorizationStatus) {
        self.status = status
    }

    func authorizationStatus() -> PhotoLibraryAuthorizationStatus {
        status
    }

    func requestAuthorization() async -> PhotoLibraryAuthorizationStatus {
        status
    }

    func fetchCandidates(includeVideos: Bool, includeLivePhotoVideo: Bool) async throws -> [PhotoAssetCandidate] {
        []
    }
}
