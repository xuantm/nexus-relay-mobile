import XCTest
@testable import NexusRelayIPhone

final class SettingsStoreTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var store: UserDefaultsSettingsStore!

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: "test_suite")
        userDefaults.removePersistentDomain(forName: "test_suite")
        store = UserDefaultsSettingsStore(userDefaults: userDefaults)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: "test_suite")
        userDefaults = nil
        store = nil
        super.tearDown()
    }

    func testDefaultSettings() {
        let settings = store.settings
        XCTAssertEqual(settings, AppSettings.defaults)
        XCTAssertNil(settings.backendBaseURL)
        XCTAssertNil(settings.destinationFolderId)
        XCTAssertEqual(settings.destinationFolderName, "iPhone Uploads")
        XCTAssertTrue(settings.wifiOnly)
        XCTAssertTrue(settings.includeVideos)
        XCTAssertFalse(settings.includeLivePhotoVideo)
    }

    func testSaveAndLoadSettings() {
        var settings = store.settings
        settings.backendBaseURL = URL(string: "https://relay.xuantruong.org")
        settings.destinationFolderId = UUID()
        settings.destinationFolderName = "Test Destination"
        settings.wifiOnly = false
        settings.includeVideos = false
        settings.includeLivePhotoVideo = true

        store.settings = settings

        let loadedStore = UserDefaultsSettingsStore(userDefaults: userDefaults)
        let loadedSettings = loadedStore.settings

        XCTAssertEqual(loadedSettings, settings)
        XCTAssertEqual(loadedSettings.backendBaseURL, URL(string: "https://relay.xuantruong.org"))
        XCTAssertEqual(loadedSettings.destinationFolderName, "Test Destination")
        XCTAssertFalse(loadedSettings.wifiOnly)
        XCTAssertFalse(loadedSettings.includeVideos)
        XCTAssertTrue(loadedSettings.includeLivePhotoVideo)
    }
}
