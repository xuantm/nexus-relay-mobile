import SwiftUI

struct SetupView: View {
    @StateObject var viewModel = SetupViewModel()
    var onSetupSuccess: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NRDesign.Spacing.section) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NexusRelay")
                            .font(.largeTitle.bold())
                            .foregroundStyle(NRDesign.ColorToken.primaryText)
                        Text("Set up photo relay from this iPhone")
                            .font(.subheadline)
                            .foregroundStyle(NRDesign.ColorToken.secondaryText)
                    }
                    .padding(.top, 24)

                    SetupChecklistView(rows: viewModel.checklistRows)

                    setupFields
                    setupPreferences

                    if let error = viewModel.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(NRDesign.ColorToken.error)
                    }

                    Text("Password is not stored after login. Photos stay local until upload starts.")
                        .font(.caption)
                        .foregroundStyle(NRDesign.ColorToken.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Button {
                        Task {
                            await viewModel.saveAndLogin()
                            if viewModel.isSetupComplete {
                                onSetupSuccess()
                            }
                        }
                    } label: {
                        Label(viewModel.isLoading ? "Connecting..." : "Continue", systemImage: "arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(NRDesign.ColorToken.accent)
                    .disabled(viewModel.isLoading)
                }
                .padding(.horizontal, NRDesign.Spacing.page)
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .nrPageBackground()
        }
    }

    private var setupFields: some View {
        VStack(spacing: 0) {
            LabeledContent("Server") {
                TextField("https://relay.example.com", text: $viewModel.serverURL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 12)
            
            Divider()
            
            LabeledContent("Username") {
                TextField("xuan", text: $viewModel.username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 12)
            
            Divider()
            
            LabeledContent("Password") {
                SecureField("Required", text: $viewModel.password)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 16)
        .background(NRDesign.ColorToken.surface)
        .clipShape(RoundedRectangle(cornerRadius: NRDesign.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NRDesign.Radius.row, style: .continuous)
                .stroke(NRDesign.ColorToken.hairline, lineWidth: 1)
        )
    }

    private var setupPreferences: some View {
        VStack(spacing: 0) {
            Toggle("Wi-Fi Only", isOn: $viewModel.wifiOnly)
                .padding(.vertical, 12)
            
            Divider()
            
            Toggle("Include Videos", isOn: $viewModel.includeVideos)
                .padding(.vertical, 12)
            
            Divider()
            
            Toggle("Live Photo Video", isOn: $viewModel.includeLivePhotos)
                .padding(.vertical, 12)
        }
        .padding(.horizontal, 16)
        .background(NRDesign.ColorToken.surface)
        .clipShape(RoundedRectangle(cornerRadius: NRDesign.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NRDesign.Radius.row, style: .continuous)
                .stroke(NRDesign.ColorToken.hairline, lineWidth: 1)
        )
    }
}
