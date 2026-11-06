import SwiftUI

private enum OverviewLayout {
    static let actionIconSize: CGFloat = 16
    static let healthRowMinHeight: CGFloat = 64
    static let healthStatusIconSize: CGFloat = 30
    static let healthStatusSymbolSize: CGFloat = 18
    static let healthActionSlotMinWidth: CGFloat = 144
}

struct OverviewTab: View {
    let profile: DeviceProfile
    @ObservedObject var session: DeviceDashboardSession
    @ObservedObject var reachabilityStore: DeviceReachabilityStore

    var body: some View {
        let summary = session.summary(for: profile)
        let presentation = DeviceDashboardOverviewPresentation(
            summary: summary,
            reachabilitySnapshot: reachabilityStore.snapshot(for: profile),
            isReachabilityRunning: reachabilityStore.isRunning(profile: profile)
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let warning = presentation.hostWarning {
                    WarningBanner(warning: warning)
                }

                HStack(spacing: 24) {
                    AirPortDeviceIcon(isTower: profile.deviceGeneration == "gen5" || profile.model?.contains("8,") == true)
                        .frame(width: 64, height: 86)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(profile.title).font(.title2.weight(.semibold))
                        HStack(spacing: 7) {
                            DeviceStatusLight(status: summary.displayStatus)
                            Text(summary.displayStatus.title).foregroundStyle(.secondary)
                        }
                        Text(profile.connectionTarget).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 18)

                Text(L10n.string(summary.primaryAction == .openSMB ? "simple.summary.ready" : "simple.summary.help"))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button(primaryActionTitle(presentation.primaryAction)) {
                        if presentation.primaryAction == .installSMB {
                            session.selectedTab = .install
                        } else {
                            session.performPrimaryAction(presentation.primaryAction, profile: profile)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!presentation.isPrimaryActionEnabled)
                    if presentation.primaryAction != .runCheckup {
                        Button(L10n.string("simple.check_connection")) {
                            session.performSecondaryAction(.runCheckup, profile: profile)
                        }
                        .disabled(!presentation.isEnabled(.runCheckup))
                    }
                }
                .padding(.vertical, 8)

                ForEach(presentation.healthSections.compactMap { section -> DashboardHealthSection? in
                    let problems = section.rows.filter { $0.status == .warning || $0.status == .failed }
                    return problems.isEmpty ? nil : DashboardHealthSection(domain: section.domain, rows: problems)
                }) { section in
                    DashboardHealthSectionView(section: section, isActionEnabled: presentation.isEnabled) { action in
                        session.performSecondaryAction(action, profile: profile)
                    }
                }

                if let disk = profile.lastCheckup?.diskHealth?.disks.first {
                    HStack(spacing: 10) {
                        Image(systemName: "internaldrive").foregroundStyle(.secondary)
                        Text(disk.label)
                        Spacer()
                        if let temperature = disk.temperatureCelsius {
                            Text(temperature).foregroundStyle(.secondary)
                        }
                        Button(L10n.string("simple.disk_details")) { session.selectedTab = .maintenance }
                    }
                    .font(.callout)
                    .padding(.vertical, 14)
                }

                DashboardDisclosureSection(title: L10n.string("simple.connection_details")) {
                    SummaryGrid(rows: presentation.header.rows.map { ($0.label, $0.value) })
                    Text(presentation.header.lastChecked).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func primaryActionTitle(_ action: DashboardPrimaryAction) -> String {
        switch action {
        case .openSMB: return L10n.string("simple.open_disk")
        case .installSMB: return L10n.string("simple.sharing.set_up")
        case .runCheckup: return L10n.string("simple.check_connection")
        default: return action.title
        }
    }

}

private struct DashboardActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label {
            Text(title)
                .lineLimit(1)
        } icon: {
            Image(systemName: systemImage)
                .frame(width: OverviewLayout.actionIconSize, height: OverviewLayout.actionIconSize)
        }
    }
}

private struct DashboardHealthSectionView: View {
    let section: DashboardHealthSection
    let isActionEnabled: (DashboardSecondaryAction) -> Bool
    let performAction: (DashboardSecondaryAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title)
                .font(.headline)
            ForEach(section.rows) { row in
                HStack(alignment: .top, spacing: 10) {
                    DashboardHealthStatusIcon(status: row.status)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(row.title)
                                .font(.body.weight(.medium))
                            Spacer()
                            DashboardHealthActionSlot(
                                action: row.action,
                                isActionEnabled: isActionEnabled,
                                performAction: performAction
                            )
                        }
                        AnimatedProgressText(message: row.detail, isRunning: row.status == .running)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: OverviewLayout.healthRowMinHeight, alignment: .topLeading)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

private struct DashboardHealthActionSlot: View {
    let action: DashboardSecondaryAction?
    let isActionEnabled: (DashboardSecondaryAction) -> Bool
    let performAction: (DashboardSecondaryAction) -> Void

    var body: some View {
        Group {
            if let action {
                Button {
                    performAction(action)
                } label: {
                    DashboardActionLabel(title: action.title, systemImage: action.systemImage)
                }
                .controlSize(.small)
                .disabled(!isActionEnabled(action))
            } else {
                // Reserve real button metrics so rows without actions align with rows that have action buttons.
                Button {} label: {
                    DashboardActionLabel(
                        title: DashboardSecondaryAction.runCheckup.title,
                        systemImage: DashboardSecondaryAction.runCheckup.systemImage
                    )
                }
                    .controlSize(.small)
                    .hidden()
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
        .frame(
            minWidth: OverviewLayout.healthActionSlotMinWidth,
            alignment: .trailing
        )
    }
}

private struct DashboardHealthStatusIcon: View {
    let status: DashboardHealthStatus

    var body: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(status == .unknown ? 0.10 : 0.14))
            icon
                .foregroundStyle(statusColor)
        }
            .frame(width: OverviewLayout.healthStatusIconSize, height: OverviewLayout.healthStatusIconSize)
            .accessibilityLabel(status.title)
    }

    @ViewBuilder
    private var icon: some View {
        if status == .running {
            OperationTimelineStateIcon(state: .running)
        } else {
            Image(systemName: status.systemImage)
                .font(.system(size: OverviewLayout.healthStatusSymbolSize, weight: .semibold))
        }
    }

    private var statusColor: Color {
        switch status {
        case .unknown:
            return .secondary
        case .good:
            return .green
        case .warning:
            return .orange
        case .failed:
            return .red
        case .running:
            return .accentColor
        }
    }
}
