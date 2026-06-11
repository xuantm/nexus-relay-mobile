import Foundation
import SwiftUI

@MainActor
final class PixelDeliveryViewModel: ObservableObject {
    private static let succeededJobsPageSize = 10

    @Published var devices: [AccountSyncDeviceDTO] = []
    @Published var overview: AccountSyncOverviewDTO? = nil
    @Published var succeededJobs: [AccountSyncSucceededJobDTO] = []
    @Published var isLoadingMoreSucceededJobs = false
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    @Published var lastRefreshDate: Date? = nil

    private let settingsStore: SettingsStore
    private let apiClient: NexusRelayAPI?
    private var pollingTask: Task<Void, Never>? = nil
    private var activeTargetId: UUID? = nil
    private var nextSucceededCursor: String? = nil
    private var hasMoreSucceededJobs = false
    private var lastLoadedSucceededCursor: String? = nil

    init(
        settingsStore: SettingsStore = UserDefaultsSettingsStore(),
        apiClient: NexusRelayAPI? = nil
    ) {
        self.settingsStore = settingsStore
        self.apiClient = apiClient
    }

    func startPolling() {
        guard pollingTask == nil else { return }

        pollingTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                await self.refresh()
                let delaySeconds: UInt64 = (self.overview?.activeDeviceSyncJobs ?? 0) > 0 ? 3 : 30
                try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let client = try resolvedAPIClient()
            let dashboard = try await client.getAccountSyncDashboard()
            overview = dashboard.overview
            devices = dashboard.devices

            let nextTargetId = dashboard.devices.first?.targetId
            let targetChanged = nextTargetId != activeTargetId
            activeTargetId = nextTargetId

            if let nextTargetId {
                let firstPage = try await client.getAccountSucceededDeviceSyncJobs(
                    targetId: nextTargetId,
                    take: Self.succeededJobsPageSize,
                    cursor: nil
                )
                if targetChanged || succeededJobs.isEmpty {
                    nextSucceededCursor = firstPage.nextCursor
                    hasMoreSucceededJobs = firstPage.hasMore
                    lastLoadedSucceededCursor = nil
                    succeededJobs = firstPage.items
                } else {
                    succeededJobs = mergeRecentSucceededJobs(latest: firstPage.items, existing: succeededJobs)
                    if nextSucceededCursor == nil {
                        nextSucceededCursor = firstPage.nextCursor
                    }
                    if !hasMoreSucceededJobs {
                        hasMoreSucceededJobs = firstPage.hasMore
                    }
                }
            } else {
                succeededJobs = []
                nextSucceededCursor = nil
                hasMoreSucceededJobs = false
                lastLoadedSucceededCursor = nil
            }

            errorMessage = nil
            lastRefreshDate = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreSucceededJobsIfNeeded(currentJob: AccountSyncSucceededJobDTO) async {
        guard let activeTargetId,
              hasMoreSucceededJobs,
              !isLoadingMoreSucceededJobs,
              succeededJobs.last?.id == currentJob.id,
              let cursor = nextSucceededCursor,
              lastLoadedSucceededCursor != cursor else {
            return
        }

        isLoadingMoreSucceededJobs = true
        lastLoadedSucceededCursor = cursor
        defer { isLoadingMoreSucceededJobs = false }

        do {
            let client = try resolvedAPIClient()
            let page = try await client.getAccountSucceededDeviceSyncJobs(
                targetId: activeTargetId,
                take: Self.succeededJobsPageSize,
                cursor: cursor
            )
            let seen = Set(succeededJobs.map(\.id))
            let nextItems = page.items.filter { !seen.contains($0.id) }
            succeededJobs.append(contentsOf: nextItems)
            nextSucceededCursor = page.nextCursor
            hasMoreSucceededJobs = page.hasMore
        } catch {
            lastLoadedSucceededCursor = nil
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

    private func mergeRecentSucceededJobs(
        latest: [AccountSyncSucceededJobDTO],
        existing: [AccountSyncSucceededJobDTO]
    ) -> [AccountSyncSucceededJobDTO] {
        var seen = Set<UUID>()
        var merged: [AccountSyncSucceededJobDTO] = []

        for item in latest where seen.insert(item.id).inserted {
            merged.append(item)
        }

        for item in existing where seen.insert(item.id).inserted {
            merged.append(item)
        }

        return merged
    }
}
