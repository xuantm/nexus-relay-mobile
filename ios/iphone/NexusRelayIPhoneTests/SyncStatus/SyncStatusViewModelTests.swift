import XCTest
@testable import NexusRelayIPhone

@MainActor
final class SyncStatusViewModelTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var settingsStore: UserDefaultsSettingsStore!
    private var tempDir: URL!
    private var dbURL: URL!

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: "test_suite_status")
        userDefaults.removePersistentDomain(forName: "test_suite_status")
        settingsStore = UserDefaultsSettingsStore(userDefaults: userDefaults)
        
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dbURL = tempDir.appendingPathComponent("test_ledger.sqlite")
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: "test_suite_status")
        userDefaults = nil
        settingsStore = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testInitializationAndDefaults() {
        var s = settingsStore.settings
        s.backendBaseURL = URL(string: "https://relay.xuantruong.org")
        s.destinationFolderId = UUID()
        s.destinationFolderName = "iPhone Uploads"
        settingsStore.settings = s

        let viewModel = SyncStatusViewModel(settingsStore: settingsStore, dbURL: dbURL)
        
        XCTAssertEqual(viewModel.serverURLString, "https://relay.xuantruong.org")
        XCTAssertEqual(viewModel.folderName, "iPhone Uploads")
        XCTAssertEqual(viewModel.activeStatus, .idle)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLogoutClearsSettings() {
        var s = settingsStore.settings
        s.backendBaseURL = URL(string: "https://relay.xuantruong.org")
        s.destinationFolderId = UUID()
        s.destinationFolderName = "Custom Folder"
        settingsStore.settings = s

        let viewModel = SyncStatusViewModel(settingsStore: settingsStore, dbURL: dbURL)
        viewModel.logout()

        XCTAssertTrue(viewModel.isLoggedOut)
        XCTAssertEqual(viewModel.serverURLString, "")
        XCTAssertEqual(viewModel.folderName, "")
        XCTAssertEqual(settingsStore.settings, AppSettings.defaults)
    }

    func testDashboardRuntimeSnapshotStartsEmpty() {
        let viewModel = SyncStatusViewModel(settingsStore: settingsStore, dbURL: dbURL)

        XCTAssertEqual(viewModel.dashboardRuntimeSnapshot, .empty)
    }
}
