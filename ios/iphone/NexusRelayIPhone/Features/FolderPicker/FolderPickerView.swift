import SwiftUI

@MainActor
final class FolderPickerViewModel: ObservableObject {
    @Published var folders: [FolderDTO] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedFolderId: UUID?
    
    private let apiClient: NexusRelayAPI
    private let settingsStore: SettingsStore

    init(apiClient: NexusRelayAPI, settingsStore: SettingsStore) {
        self.apiClient = apiClient
        self.settingsStore = settingsStore
        self.selectedFolderId = settingsStore.settings.destinationFolderId
    }

    func loadFoldersAndAutoSetup() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetchedFolders = try await apiClient.listRootFolders()
            self.folders = fetchedFolders
            
            // Check if default folder exists
            let defaultName = settingsStore.settings.destinationFolderName
            if let existing = fetchedFolders.first(where: { $0.name.lowercased() == defaultName.lowercased() }) {
                selectFolder(existing)
            } else {
                // Not found, create it automatically
                let newFolder = try await apiClient.createFolder(name: defaultName, parentId: nil)
                self.folders.append(newFolder)
                selectFolder(newFolder)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func selectFolder(_ folder: FolderDTO) {
        var s = settingsStore.settings
        s.destinationFolderId = folder.id
        s.destinationFolderName = folder.name
        settingsStore.settings = s
        self.selectedFolderId = folder.id
    }
}

struct FolderPickerView: View {
    @StateObject var viewModel: FolderPickerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Loading folders...")
                        Spacer()
                    }
                } else if let error = viewModel.errorMessage {
                    Section {
                        Text("Error: \(error)")
                            .foregroundColor(.red)
                        Button("Retry") {
                            Task {
                                await viewModel.loadFoldersAndAutoSetup()
                            }
                        }
                    }
                } else {
                    Section("Available Folders") {
                        ForEach(viewModel.folders) { folder in
                            HStack {
                                Text(folder.name)
                                Spacer()
                                if folder.id == viewModel.selectedFolderId {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectFolder(folder)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await viewModel.loadFoldersAndAutoSetup()
            }
        }
    }
}
