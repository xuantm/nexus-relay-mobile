import SwiftUI

@MainActor
struct UploadQueueView: View {
    @StateObject private var viewModel = UploadQueueViewModel()
    @ObservedObject private var syncStatusViewModel: SyncStatusViewModel
    private let thumbnailProvider: PhotoThumbnailProvider = PhotoKitThumbnailProvider()
    @State private var selectedItem: UploadQueueItem?

    init(syncStatusViewModel: SyncStatusViewModel? = nil) {
        _syncStatusViewModel = ObservedObject(wrappedValue: syncStatusViewModel ?? SyncStatusViewModel())
    }

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

                if viewModel.items.isEmpty {
                    ContentUnavailableView(
                        viewModel.selectedSegment == .failed ? "No failed uploads" : "Queue is clear",
                        systemImage: viewModel.selectedSegment == .failed ? "checkmark.circle" : "tray",
                        description: Text(viewModel.selectedSegment == .failed ? "Uploads needing attention will appear here." : "New uploads appear here after scanning.")
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 40)
                } else {
                    ForEach(viewModel.items) { item in
                        UploadQueueRow(
                            item: item,
                            thumbnailProvider: thumbnailProvider,
                            onSelect: {
                                selectedItem = item
                            },
                            onRetry: item.canRetry ? {
                                Task { await viewModel.retry(id: item.id) }
                            } : nil
                        )
                    }
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
            .onReceive(syncStatusViewModel.$queuedCount) { _ in
                Task { await viewModel.load() }
            }
            .onReceive(syncStatusViewModel.$failedCount) { _ in
                Task { await viewModel.load() }
            }
            .onReceive(syncStatusViewModel.$exportingCount) { _ in
                Task { await viewModel.load() }
            }
            .onReceive(syncStatusViewModel.$uploadingCount) { _ in
                Task { await viewModel.load() }
            }
            .sheet(item: $selectedItem) { item in
                UploadQueueDetailView(
                    item: item,
                    destinationFolderName: viewModel.destinationFolderName,
                    onRetry: item.canRetry ? {
                        Task { await viewModel.retry(id: item.id) }
                    } : nil
                )
            }
        }
    }
}

private struct UploadQueueRow: View {
    let item: UploadQueueItem
    let thumbnailProvider: PhotoThumbnailProvider
    let onSelect: () -> Void
    let onRetry: (() -> Void)?
    @State private var thumbnail: UIImage? = nil

    var body: some View {
        if item.canRetry {
            baseRow
                .accessibilityAction(named: Text("Show details")) {
                    onSelect()
                }
                .accessibilityAction(named: Text("Retry")) {
                    onRetry?()
                }
        } else {
            baseRow
                .accessibilityAction(named: Text("Show details")) {
                    onSelect()
                }
        }
    }

    private var baseRow: some View {
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
                    .foregroundStyle(item.status == .Failed ? NRDesign.ColorToken.error : NRDesign.ColorToken.secondaryText)
                ProgressView(value: item.progressFraction)
                    .tint(item.status == .Failed ? NRDesign.ColorToken.error : NRDesign.ColorToken.accent)
            }

            if item.canRetry {
                Button {
                    onRetry?()
                } label: {
                    Image(systemName: "arrow.clockwise.circle")
                        .font(.title2)
                        .foregroundStyle(NRDesign.ColorToken.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry upload")
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(item.filename), \(item.statusText)")
        .accessibilityHint(item.canRetry ? "Double tap for details. Retry action available." : "Double tap for details.")
    }
}

private struct UploadQueueDetailView: View {
    let item: UploadQueueItem
    let destinationFolderName: String
    let onRetry: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Upload") {
                    LabeledContent("Filename", value: item.filename)
                    LabeledContent("Status", value: item.statusText)
                    LabeledContent("Size", value: item.sizeText)
                    LabeledContent("Upload Mode", value: item.uploadModeText)
                    LabeledContent("Destination", value: destinationFolderName)
                }

                if let lastError = item.lastErrorText {
                    Section("Last Error") {
                        Text(lastError)
                            .foregroundStyle(NRDesign.ColorToken.primaryText)
                    }
                }

                if let onRetry {
                    Section {
                        Button("Retry Upload") {
                            onRetry()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Upload Details")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
