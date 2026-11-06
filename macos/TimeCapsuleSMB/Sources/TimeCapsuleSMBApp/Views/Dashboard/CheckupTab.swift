import SwiftUI

struct CheckupTab: View {
    let profile: DeviceProfile
    @ObservedObject var session: DeviceDashboardSession
    @ObservedObject var operationCoordinator: OperationCoordinator
    let appSettings: AppSettings
    let showDiagnostics: () -> Void
    let diagnosticsText: () -> String

    var body: some View {
        let store = session.doctorStore
        let presentation = CheckupPresentation(summary: store.summary, state: store.state, events: store.events,
            currentStage: store.currentStage, hostWarning: HostCompatibilityPolicy.warning(enabled: appSettings.timeMachineWarningsEnabled),
            localNetworkFacts: .current())

        let effectiveState = store.state == .idle ? profile.lastCheckup?.state ?? .idle : store.state
        ScrollView {
            VStack(alignment: .leading, spacing: UtilityStyle.sectionSpacing) {
                if let progress = CheckupProgressPresentation(state: store.state, currentStage: store.currentStage) {
                    InlineOperationProgress(progress: progress, title: L10n.string("simple.check_connection"))
                } else if store.error == nil {
                    Label(L10n.string(statusKey(effectiveState)), systemImage: effectiveState == .passed ? "checkmark.circle.fill" : "network")
                        .foregroundStyle(effectiveState == .passed ? Color.primary : Color.secondary)
                }
                if !store.isRunning {
                    Button(L10n.string("simple.check_connection")) {
                        session.performCheckupAction(.runCheckup, profile: profile, showDiagnostics: showDiagnostics)
                    }
                    .disabled(operationCoordinator.isDeviceBusy(profile))
                }
                if !presentation.domains.isEmpty {
                    SummaryGrid(rows: presentation.domains.map { ($0.title, UtilityCheckupLayout.statusTitle($0.status)) })
                }
                if let checkedAt = profile.lastCheckup?.checkedAt {
                    Text(L10n.format("disk_health.checked_at", checkedAt.formatted(date: .abbreviated, time: .shortened)))
                        .font(UtilityStyle.secondary).foregroundStyle(.secondary)
                }
                if let warning = presentation.hostWarning { WarningBanner(warning: warning) }
                ForEach(presentation.domains) { domain in
                    ForEach(domain.attentionRows.filter { UtilityCheckupLayout.isUrgent($0.id) }) { row in
                        UtilityNotice(color: row.status == .failed ? .red : .orange) { Text(row.message) }
                    }
                }
                if store.summary?.diskHealth?.disks.contains(where: \.reportsFailure) == true,
                   !presentation.domains.flatMap(\.attentionRows).contains(where: { UtilityCheckupLayout.isUrgent($0.id) }) {
                    UtilityNotice(color: .red) { Text(L10n.string("utility.disk.failure_advice")) }
                }
                if let error = store.error {
                    ErrorRecoveryView(error: error, diagnosticsText: diagnosticsText, omittedActions: [.retry, .runCheckup]) { kind in
                        kind == .diagnostics ? { showDiagnostics() } : session.recoveryAction(kind, error: error, profile: profile)
                    }
                }
                if !presentation.domains.isEmpty || !presentation.timeline.isEmpty {
                    DashboardDisclosureSection(title: L10n.string("utility.details")) {
                        ForEach(presentation.domains) { domain in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(domain.title).font(UtilityStyle.heading)
                                if domain.rows.isEmpty { Text(domain.status.title).foregroundStyle(.secondary) }
                                ForEach(domain.rows) { row in
                                    Label(row.message, systemImage: row.status.systemImage)
                                        .font(UtilityStyle.secondary)
                                }
                            }
                        }
                        OperationTimelineListView(items: presentation.timeline)
                    }
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func statusKey(_ state: DoctorWorkflowState) -> String {
        switch state {
        case .passed: return "utility.status.working"
        case .warning, .failed: return "utility.status.attention"
        case .idle: return "utility.status.unchecked"
        case .runFailed: return "utility.error.check"
        case .running: return "utility.status.working_on_device"
        }
    }
}
