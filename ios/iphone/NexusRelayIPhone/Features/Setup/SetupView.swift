import SwiftUI

struct SetupView: View {
    @StateObject var viewModel = SetupViewModel()
    var onSetupSuccess: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.09, blue: 0.15), Color(red: 0.15, green: 0.18, blue: 0.28)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 25) {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.up.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 70, height: 70)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("NexusRelay")
                            .font(.system(.largeTitle, design: .rounded))
                            .bold()
                            .foregroundColor(.white)
                        
                        Text("iPhone Photos Uploader Setup")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 40)

                    VStack(spacing: 15) {
                        HStack {
                            Image(systemName: "link")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            TextField("", text: $viewModel.serverURL, prompt: Text("Server URL (e.g. https://relay.xuantruong.org)").foregroundColor(.gray))
                                .foregroundColor(.white)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        .padding()
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(12)

                        HStack {
                            Image(systemName: "person")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            TextField("", text: $viewModel.username, prompt: Text("Username").foregroundColor(.gray))
                                .foregroundColor(.white)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        .padding()
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(12)

                        HStack {
                            Image(systemName: "lock")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            SecureField("", text: $viewModel.password, prompt: Text("Password").foregroundColor(.gray))
                                .foregroundColor(.white)
                        }
                        .padding()
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(12)
                    }
                    .padding()
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Preferences")
                            .font(.system(.headline, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.bottom, 5)

                        Toggle(isOn: $viewModel.wifiOnly) {
                            HStack {
                                Image(systemName: "wifi")
                                    .foregroundColor(.cyan)
                                VStack(alignment: .leading) {
                                    Text("Wi-Fi Only")
                                        .foregroundColor(.white)
                                    Text("Uploads pause on cellular networks")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .tint(.blue)
                        
                        Divider().background(Color.white.opacity(0.1))

                        Toggle(isOn: $viewModel.includeVideos) {
                            HStack {
                                Image(systemName: "video")
                                    .foregroundColor(.cyan)
                                VStack(alignment: .leading) {
                                    Text("Sync Videos")
                                        .foregroundColor(.white)
                                    Text("Include video files in photo queue")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .tint(.blue)
                        
                        Divider().background(Color.white.opacity(0.1))

                        Toggle(isOn: $viewModel.includeLivePhotos) {
                            HStack {
                                Image(systemName: "livephoto")
                                    .foregroundColor(.cyan)
                                VStack(alignment: .leading) {
                                    Text("Sync Live Photo Video")
                                        .foregroundColor(.white)
                                    Text("Export paired video resources")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .tint(.blue)
                    }
                    .padding()
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.system(.callout, design: .rounded))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Button {
                        Task {
                            await viewModel.saveAndLogin()
                            if viewModel.isSetupComplete {
                                onSetupSuccess()
                            }
                        }
                    } label: {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .padding(.trailing, 5)
                            }
                            Text("Connect and Login")
                                .bold()
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(12)
                    }
                    .disabled(viewModel.isLoading)
                    .padding(.bottom, 30)
                }
                .padding(.horizontal)
            }
        }
    }
}
