import SwiftUI

struct SetupChecklistView: View {
    let rows: [SetupChecklistRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                HStack(spacing: 14) {
                    Image(systemName: row.state.iconName)
                        .font(.title3)
                        .foregroundStyle(row.state.tint)
                        .frame(width: 28)

                    Image(systemName: row.systemImage)
                        .font(.title3)
                        .foregroundStyle(NRDesign.ColorToken.accent)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title)
                            .font(.headline)
                            .foregroundStyle(NRDesign.ColorToken.primaryText)
                        Text(row.subtitle)
                            .font(.caption)
                            .foregroundStyle(NRDesign.ColorToken.secondaryText)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NRDesign.ColorToken.secondaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(row.title), \(row.subtitle)")
                .accessibilityValue(row.state == .complete ? "Complete" : (row.state == .failed ? "Needs attention" : "Pending"))

                if row.id != rows.last?.id {
                    Divider().padding(.leading, 86)
                }
            }
        }
        .background(NRDesign.ColorToken.surface)
        .clipShape(RoundedRectangle(cornerRadius: NRDesign.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NRDesign.Radius.row, style: .continuous)
                .stroke(NRDesign.ColorToken.hairline, lineWidth: 1)
        )
    }
}
