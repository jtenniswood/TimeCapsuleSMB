import SwiftUI

struct OverviewTab: View {
    let profile: DeviceProfile
    @ObservedObject var session: DeviceDashboardSession
    @ObservedObject var reachabilityStore: DeviceReachabilityStore

    var body: some View {
        let summary = session.summary(for: profile)
        let presentation = DeviceDashboardOverviewPresentation(summary: summary,
            reachabilitySnapshot: reachabilityStore.snapshot(for: profile), isReachabilityRunning: reachabilityStore.isRunning(profile: profile))
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 24) {
                    AirPortDeviceIcon(isTower: profile.usesTowerArtwork)
                        .frame(width: 64, height: 86)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(profile.title).font(UtilityStyle.title)
                        HStack(spacing: 7) {
                            DeviceStatusLight(status: summary.displayStatus)
                            Text(summary.displayStatus.title)
                        }
                        Text(DeviceEndpointPolicy.hostComponent(profile.connectionTarget) ?? profile.displayTarget).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)

                // A ready disk is opened from its device popover. Other states
                // offer the next step here, without repeating it in a button strip.
                if presentation.primaryAction != .openSMB {
                    Button(primaryActionTitle(presentation.primaryAction)) {
                        if presentation.primaryAction == .installSMB { session.selectedTab = .install }
                        else { session.performPrimaryAction(presentation.primaryAction, profile: profile) }
                    }
                    .disabled(!presentation.isPrimaryActionEnabled)
                }
                ForEach(presentation.healthSections) { section in
                    ForEach(section.rows.filter { $0.status == .warning || $0.status == .failed }) { row in
                        UtilityNotice(color: row.status == .failed ? .red : .orange) {
                            Text(row.title).font(UtilityStyle.heading)
                            Text(row.detail).font(UtilityStyle.secondary).foregroundStyle(.secondary)
                            if let action = row.action {
                                Button(action.title) { session.performSecondaryAction(action, profile: profile) }
                                    .disabled(!presentation.isEnabled(action))
                            }
                        }
                    }
                }
                if let warning = presentation.hostWarning { WarningBanner(warning: warning) }
                DashboardDisclosureSection(title: L10n.string("simple.connection_details")) {
                    SummaryGrid(rows: presentation.header.rows.map { ($0.label, $0.value) })
                    Text(presentation.header.lastChecked).font(UtilityStyle.secondary).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func primaryActionTitle(_ action: DashboardPrimaryAction) -> String {
        switch action {
        case .installSMB: return L10n.string("simple.sharing.set_up")
        case .runCheckup: return L10n.string("simple.check_connection")
        default: return action.title
        }
    }
}
