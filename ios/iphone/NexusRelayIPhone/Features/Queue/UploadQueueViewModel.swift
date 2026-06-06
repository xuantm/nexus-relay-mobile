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
        isLoading = true
        errorMessage = nil
        destinationFolderName = settingsStore.settings.destinationFolderName
        do {
            let records = try await ledger.listQueueRecords(filter: selectedSegment.ledgerFilter, limit: 100)
            items = records.map(UploadQueueItem.init(record:))
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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
