import SwiftUI
import UIKit

struct PhotoMosaicView: View {
    let items: [LibraryPreviewItem]
    let selectedItemID: String?
    let onSelect: (LibraryPreviewItem) -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                tile(index: 0)
                tile(index: 1)
                    .layoutPriority(1)
                tile(index: 2)
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 6) {
                tile(index: 3)
                tile(index: 4)
                    .layoutPriority(1)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 218)
        .clipShape(RoundedRectangle(cornerRadius: NRDesign.Radius.row, style: .continuous))
    }

    @ViewBuilder
    private func tile(index: Int) -> some View {
        if items.indices.contains(index) {
            let item = items[index]
            let isSelected = selectedItemID == item.id

            Button {
                onSelect(item)
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: item.image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()

                    if item.mediaType == .video {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(.black.opacity(0.42), in: Circle())
                            .padding(8)
                    }

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(NRDesign.ColorToken.accent)
                            .background(
                                Circle()
                                    .fill(.white)
                                    .frame(width: 22, height: 22)
                            )
                            .padding(8)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: NRDesign.Radius.row, style: .continuous)
                        .stroke(isSelected ? NRDesign.ColorToken.accent : Color.clear, lineWidth: 2)
                )
                .clipShape(RoundedRectangle(cornerRadius: NRDesign.Radius.row, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(accessibilityLabel(for: item, isSelected: isSelected))
            .accessibilityHint("Opens a larger preview with actions")
        } else {
            RoundedRectangle(cornerRadius: NRDesign.Radius.row, style: .continuous)
                .fill(NRDesign.ColorToken.hairline)
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(NRDesign.ColorToken.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func accessibilityLabel(for item: LibraryPreviewItem, isSelected: Bool) -> Text {
        var pieces = [item.mediaType.accessibilityLabel]

        if let filename = item.filename, !filename.isEmpty {
            pieces.append(filename)
        }

        if isSelected {
            pieces.append("Selected")
        }

        return Text(pieces.joined(separator: ", "))
    }
}
