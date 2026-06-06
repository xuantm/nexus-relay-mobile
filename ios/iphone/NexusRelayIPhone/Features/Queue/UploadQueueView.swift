import SwiftUI

struct UploadQueueView: View {
    @StateObject private var viewModel = UploadQueueViewModel()

    var body: some View {
        NavigationStack {
            List {
                Picker("Queue Filter", selection: $viewModel.selectedSegment) {
                    ForEach(UploadQueueSegment.allCases) { segment in
                        Text(segment.rawValue).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(NRDesign.ColorToken.appBackground)

                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(NRDesign.ColorToken.error)
                }

                ForEach(viewModel.items) { item in
                    UploadQueueRow(item: item)
                }

                if viewModel.selectedSegment == .failed && viewModel.items.contains(where: \.canRetry) {
                    Button("Retry all") {
                        Task { await viewModel.retryAll() }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle(viewModel.selectedSegment == .failed ? "Needs Attention" : "Upload Queue")
            .nrPageBackground()
            .task { await viewModel.load() }
            .onChange(of: viewModel.selectedSegment) { _, _ in
                Task { await viewModel.load() }
            }
        }
    }
}

private struct UploadQueueRow: View {
    let item: UploadQueueItem
    @State private var thumbnail: UIImage? = nil
    private let thumbnailProvider: PhotoThumbnailProvider = PhotoKitThumbnailProvider()

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image = thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: NRDesign.Radius.thumbnail, style: .continuous)
                        .fill(NRDesign.ColorToken.hairline)
                        .overlay(
                            Image(systemName: item.resourceKind == .video ? "video" : "photo")
                                .foregroundStyle(NRDesign.ColorToken.secondaryText)
                        )
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: NRDesign.Radius.thumbnail, style: .continuous))
            .task {
                thumbnail = await thumbnailProvider.thumbnail(forAssetLocalIdentifier: item.assetLocalIdentifier, targetSize: CGSize(width: 120, height: 120))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(item.filename)
                    .font(.headline)
                    .foregroundStyle(NRDesign.ColorToken.primaryText)
                    .lineLimit(1)
                Text(item.statusText)
                    .font(.caption)
                    .foregroundStyle(item.status == .failed ? NRDesign.ColorToken.error : NRDesign.ColorToken.secondaryText)
                ProgressView(value: item.progressFraction)
                    .tint(item.status == .failed ? NRDesign.ColorToken.error : NRDesign.ColorToken.accent)
            }

            if item.canRetry {
                Image(systemName: "arrow.clockwise.circle")
                    .font(.title2)
                    .foregroundStyle(NRDesign.ColorToken.accent)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.filename), \(item.statusText)")
        .accessibilityHint(item.canRetry ? "Double tap to retry this upload" : "")
    }
}
