import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    var onLogout: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    LabeledContent("Server", value: viewModel.serverURLString)
                    Button(role: .destructive) {
                        onLogout()
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Section("Library") {
                    LabeledContent("Destination Folder", value: viewModel.folderName)
                    LabeledContent("Photos Access", value: viewModel.photosAccessText)
                }

                Section("Sync") {
                    Toggle("Wi-Fi Only", isOn: $viewModel.wifiOnly)
                    Toggle("Include Videos", isOn: $viewModel.includeVideos)
                    Toggle("Live Photo Video", isOn: $viewModel.includeLivePhotoVideo)
                }

                Section {
                    Text("Background sync is best effort. Open the app and tap Sync for the most reliable upload.")
                        .font(.caption)
                        .foregroundStyle(NRDesign.ColorToken.secondaryText)
                }
            }
            .navigationTitle("Settings")
            .scrollContentBackground(.hidden)
            .nrPageBackground()
            .onChange(of: viewModel.wifiOnly) { _, _ in viewModel.saveSyncPreferences() }
            .onChange(of: viewModel.includeVideos) { _, _ in viewModel.saveSyncPreferences() }
            .onChange(of: viewModel.includeLivePhotoVideo) { _, _ in viewModel.saveSyncPreferences() }
        }
    }
}
