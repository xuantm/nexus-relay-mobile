import Foundation

@MainActor
final class UploadQueueViewModel: ObservableObject {
    @Published var selectedSegment: UploadQueueSegment = .all
    @Published var items: [UploadQueueItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var destinationFolderName: String = ""

    private let ledger: UploadLedger
    private let settingsStore: SettingsStore
    private var needsReloadAfterCurrentLoad = false

    init(ledger: UploadLedger? = nil, settingsStore: SettingsStore = UserDefaultsSettingsStore()) {
        self.settingsStore = settingsStore
        self.destinationFolderName = settingsStore.settings.destinationFolderName
        if let ledger {
            self.ledger = ledger
        } else {
            let dbURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ledger.sqlite")
            var isCorrupt = false
            self.ledger = LedgerFactory.createOrRecoverLedger(dbURL: dbURL, isCorrupted: &isCorrupt)
        }
    }

    func load() async {
        if isLoading {
            needsReloadAfterCurrentLoad = true
            return
        }

        repeat {
            needsReloadAfterCurrentLoad = false
            isLoading = true
            await loadCurrentSelection()
            isLoading = false
        } while needsReloadAfterCurrentLoad
    }

    private func loadCurrentSelection() async {
        let requestedSegment = selectedSegment
        errorMessage = nil
        destinationFolderName = settingsStore.settings.destinationFolderName
        do {
            let records = try await ledger.listQueueRecords(filter: requestedSegment.ledgerFilter, limit: 100)
            if requestedSegment == selectedSegment {
                items = records.map(UploadQueueItem.init(record:))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func retryAll() async {
        let ids = items.filter(\.canRetry).map(\.id)
        await retry(ids: ids)
    }

    func retry(id: String) async {
        await retry(ids: [id])
    }

    private func retry(ids: [String]) async {
        guard !ids.isEmpty else { return }
        do {
            try await ledger.retryFailed(ids: ids)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
