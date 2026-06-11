import Foundation
import SwiftUI

@MainActor
final class PixelDeliveryViewModel: ObservableObject {
    @Published var devices: [AccountSyncDeviceDTO] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    @Published var lastRefreshDate: Date? = nil

    private let settingsStore: SettingsStore
    private let apiClient: NexusRelayAPI?

    init(
        settingsStore: SettingsStore = UserDefaultsSettingsStore(),
        apiClient: NexusRelayAPI? = nil
    ) {
        self.settingsStore = settingsStore
        self.apiClient = apiClient
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let client = try resolvedAPIClient()
            let dashboard = try await client.getAccountSyncDashboard()
            devices = dashboard.devices
            errorMessage = nil
            lastRefreshDate = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolvedAPIClient() throws -> NexusRelayAPI {
        if let apiClient {
            return apiClient
        }

        guard let baseURL = settingsStore.settings.backendBaseURL else {
            throw APIError.invalidURL
        }

        let keychain = SystemKeychainStore()
        let sessionStore = CookieSessionStore(keychain: keychain)
        let csrfProvider = SystemCSRFTokenProvider()
        let httpClient = SystemHTTPClient(baseURL: baseURL, sessionStore: sessionStore, csrfProvider: csrfProvider)
        return SystemNexusRelayAPIClient(baseURL: baseURL, httpClient: httpClient, sessionStore: sessionStore)
    }
}
