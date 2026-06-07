import SwiftUI

struct SetupChecklistView: View {
    let rows: [SetupChecklistRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: row.state.iconName)
                        .font(.system(size: NRDesign.IconSize.status, weight: .semibold))
                        .foregroundStyle(row.state.tint)
                        .frame(width: 24)

                    Image(systemName: row.systemImage)
                        .font(.system(size: NRDesign.IconSize.row, weight: .regular))
                        .foregroundStyle(NRDesign.ColorToken.accent)
                        .frame(width: 26)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(NRDesign.ColorToken.primaryText)
                        Text(row.subtitle)
                            .font(.caption)
                            .foregroundStyle(NRDesign.ColorToken.secondaryText)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(row.title), \(row.subtitle)")
                .accessibilityValue(row.state == .complete ? "Complete" : (row.state == .failed ? "Needs attention" : "Pending"))

                if row.id != rows.last?.id {
                    Divider().padding(.leading, 72)
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
