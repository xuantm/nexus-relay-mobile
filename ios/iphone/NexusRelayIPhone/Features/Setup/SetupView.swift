import SwiftUI

struct SetupView: View {
    @StateObject var viewModel = SetupViewModel()
    var onSetupSuccess: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                NRDesign.ColorToken.appBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: NRDesign.Spacing.section) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NexusRelay")
                                .font(.title.bold())
                                .foregroundStyle(NRDesign.ColorToken.primaryText)
                            Text("Set up photo relay from this iPhone")
                                .font(.subheadline)
                                .foregroundStyle(NRDesign.ColorToken.secondaryText)
                        }
                        .padding(.top, 20)

                        SetupChecklistView(rows: viewModel.checklistRows)
                        setupPreferences

                        if let error = viewModel.errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(NRDesign.ColorToken.error)
                        }

                        Text("Google sign-in opens in the system browser. NexusRelay stores only its own session cookies.")
                            .font(.caption)
                            .foregroundStyle(NRDesign.ColorToken.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, NRDesign.Spacing.page)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .navigationBarTitleDisplayMode(.inline)
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

    private var actionBar: some View {
        VStack(spacing: 10) {
            Button {
                Task {
                    await viewModel.saveAndLogin()
                    if viewModel.isSetupComplete {
                        onSetupSuccess()
                    }
                }
            } label: {
                Label(viewModel.isLoading ? "Connecting..." : "Continue with Google", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(NRDesign.ColorToken.accent)
            .disabled(viewModel.isLoading)
        }
        .padding(.horizontal, NRDesign.Spacing.page)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }
}
