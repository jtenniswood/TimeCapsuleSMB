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

                Button(summary.displayStatus == .activationNeeded ? L10n.string("utility.sharing.start") : primaryActionTitle(presentation.primaryAction)) {
                    if summary.displayStatus == .activationNeeded { session.performSecondaryAction(.startSMB, profile: profile) }
                    else if presentation.primaryAction == .installSMB { session.selectedTab = .install }
                    else { session.performPrimaryAction(presentation.primaryAction, profile: profile) }
                }
                .disabled(summary.displayStatus == .activationNeeded ? !presentation.isEnabled(.startSMB) : !presentation.isPrimaryActionEnabled)
                // Only urgent disk precautions interrupt the overview. All
                // connection and software checks have their home in Connection.
                ForEach(presentation.healthSections) { section in
                    ForEach(section.rows.filter { UtilityCheckupLayout.isUrgent($0.id) }) { row in
                        UtilityNotice(color: row.status == .failed ? .red : .orange) {
                            Text(row.detail)
                        }
                    }
                }
                if profile.lastCheckup?.diskHealth?.disks.contains(where: \.reportsFailure) == true {
                    UtilityNotice(color: .red) { Text(L10n.string("utility.disk.failure_advice")) }
                }
                if let warning = presentation.hostWarning { WarningBanner(warning: warning) }
                DashboardDisclosureSection(title: L10n.string("simple.connection_details")) {
                    SummaryGrid(rows: presentation.header.rows.map { ($0.label, $0.value) })
                    Text(presentation.header.lastChecked).font(UtilityStyle.secondary).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func primaryActionTitle(_ action: DashboardPrimaryAction) -> String {
        switch action {
        case .installSMB: return L10n.string("simple.sharing.set_up")
        case .runCheckup: return L10n.string("simple.check_connection")
        case .openSMB: return L10n.string("simple.open_disk")
        case .replacePassword: return L10n.string("utility.password.update")
        default: return action.title
        }
    }
}
