import XCTest
@testable import NexusRelayIPhone

@MainActor
final class SetupViewModelTests: XCTestCase {
    func testInitFallsBackToDefaultBackendURLWhenStoredURLIsMissing() {
        let settingsStore = SetupTestSettingsStore()
        settingsStore.settings.backendBaseURL = nil

        let viewModel = SetupViewModel(
            settingsStore: settingsStore,
            photosScanner: SetupTestPhotoLibraryClient(),
            sessionStore: MockSessionStore(),
            authCoordinator: SetupTestAuthCoordinator()
        )

        XCTAssertEqual(viewModel.serverURL, "https://relay.xuantruong.org")
    }
}

private final class SetupTestSettingsStore: SettingsStore {
    var settings: AppSettings = .defaults
}

private final class SetupTestPhotoLibraryClient: PhotoLibraryClient {
    func authorizationStatus() -> PhotoLibraryAuthorizationStatus {
        .notDetermined
    }

    func requestAuthorization() async -> PhotoLibraryAuthorizationStatus {
        .notDetermined
    }

    func fetchCandidates(includeVideos: Bool, includeLivePhotoVideo: Bool) async throws -> [PhotoAssetCandidate] {
        []
    }
}

private final class SetupTestAuthCoordinator: GoogleAuthCoordinating {
    func signIn(baseURL: URL) async throws -> AuthCallbackResult {
        .invalid
    }
}
