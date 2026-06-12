import SwiftUI

struct SyncProgressHeroCard: View {
    let dashboard: LibrarySyncDashboardState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(dashboard.progressPercentText)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(NRDesign.ColorToken.primaryText)

                    Text(dashboard.progressLabelText)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(NRDesign.ColorToken.primaryText)
                }

                Spacer()

                Label(dashboard.statusText, systemImage: "icloud.and.arrow.up.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .foregroundStyle(NRDesign.ColorToken.accent)
                    .background(NRDesign.ColorToken.accent.opacity(0.12), in: Capsule())
            }

            ProgressView(value: dashboard.progressFraction)
                .tint(NRDesign.ColorToken.accent)

            HStack(spacing: 0) {
                SyncHeroMetric(icon: "clock", value: dashboard.etaText, label: "Est. remaining")
                Divider().frame(height: 38)
                SyncHeroMetric(icon: "gauge.with.dots.needle.67percent", value: dashboard.speedText, label: "Upload speed")
                Divider().frame(height: 38)
                SyncHeroMetric(icon: "externaldrive", value: dashboard.remainingText, label: "Remaining")
            }
        }
        .padding(18)
        .background(NRDesign.ColorToken.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(NRDesign.ColorToken.hairline, lineWidth: 1)
        )
    }
}

private struct SyncHeroMetric: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(NRDesign.ColorToken.secondaryText)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(NRDesign.ColorToken.primaryText)
            Text(label)
                .font(.caption)
                .foregroundStyle(NRDesign.ColorToken.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SyncStageCards: View {
    let dashboard: LibrarySyncDashboardState

    var body: some View {
        HStack(spacing: 12) {
            SyncStageCard(icon: "checkmark.circle", title: "Scanned", value: dashboard.scannedText, subtitle: "assets found", tint: .green)
            SyncStageCard(icon: "arrow.up.circle", title: "Exporting", value: dashboard.exportingText, subtitle: "readying files", tint: .orange)
            SyncStageCard(icon: "icloud.and.arrow.up", title: "Uploading", value: dashboard.uploadingText, subtitle: "active transfers", tint: .blue)
        }
    }
}

private struct SyncStageCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(NRDesign.ColorToken.primaryText)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(NRDesign.ColorToken.primaryText)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(NRDesign.ColorToken.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

struct SyncMetricGrid: View {
    let dashboard: LibrarySyncDashboardState

    var body: some View {
        HStack(spacing: 0) {
            SyncMetricCard(title: "Uploaded", value: dashboard.uploadedText, tint: .green)
            SyncMetricCard(title: "Waiting", value: dashboard.waitingText, tint: .blue)
            SyncMetricCard(title: "Active", value: dashboard.activeText, tint: .blue)
            SyncMetricCard(title: "Failed", value: dashboard.failedText, tint: .gray)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(NRDesign.ColorToken.hairline, lineWidth: 1)
        )
    }
}

private struct SyncMetricCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(NRDesign.ColorToken.secondaryText)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(NRDesign.ColorToken.primaryText)
            Capsule()
                .fill(tint)
                .frame(width: 36, height: 3)
                .opacity(0.9)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(NRDesign.ColorToken.surface)
    }
}

struct SyncQueueHealthCard: View {
    let dashboard: LibrarySyncDashboardState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Queue Health")
                .font(.caption.weight(.bold))
                .foregroundStyle(NRDesign.ColorToken.secondaryText)
                .textCase(.uppercase)

            HStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.green, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(dashboard.nextBatchText)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(NRDesign.ColorToken.primaryText)
                    Text(dashboard.nextBatchDetailText)
                        .font(.subheadline)
                        .foregroundStyle(NRDesign.ColorToken.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(NRDesign.ColorToken.secondaryText)
            }

            Text(dashboard.lastSyncedText)
                .font(.subheadline)
                .foregroundStyle(NRDesign.ColorToken.secondaryText)

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Circle().fill(Color.green).frame(width: 10, height: 10)
                    Circle().fill(Color.green).frame(width: 10, height: 10)
                    Circle().fill(Color.green.opacity(0.25)).frame(width: 10, height: 10)
                    Circle().fill(Color.gray.opacity(0.2)).frame(width: 10, height: 10)
                }

                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dashboard.safeToCloseTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(NRDesign.ColorToken.primaryText)
                        Text(dashboard.safeToCloseSubtitle)
                            .font(.caption)
                            .foregroundStyle(NRDesign.ColorToken.secondaryText)
                    }
                } icon: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Color.green)
                }
            }
        }
        .padding(18)
        .background(NRDesign.ColorToken.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(NRDesign.ColorToken.hairline, lineWidth: 1)
        )
    }
}

struct SyncDashboardActionBar: View {
    let dashboard: LibrarySyncDashboardState
    let onPrimaryAction: () -> Void
    let onOpenQueue: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPrimaryAction) {
                Label(dashboard.primaryActionTitle, systemImage: dashboard.canPause ? "pause.circle" : "icloud.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(NRDesign.ColorToken.accent)

            Button(action: onOpenQueue) {
                Label("View Queue", systemImage: "list.bullet")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(NRDesign.ColorToken.accent)
        }
    }
}
