import SwiftUI
import UIKit

struct PhotoMosaicView: View {
    let images: [UIImage]

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                tile(index: 0).gridCellRows(2)
                tile(index: 1)
                tile(index: 2)
            }
            GridRow {
                tile(index: 3)
                tile(index: 4).gridCellColumns(2)
            }
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func tile(index: Int) -> some View {
        if images.indices.contains(index) {
            Image(uiImage: images[index])
                .resizable()
                .scaledToFill()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
        } else {
            Rectangle()
                .fill(NRDesign.ColorToken.hairline)
                .overlay(
                    Image(systemName: "photo")
                        .foregroundStyle(NRDesign.ColorToken.secondaryText)
                )
        }
    }
}
