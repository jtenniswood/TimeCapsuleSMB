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

        ScrollView {
            VStack(alignment: .leading, spacing: UtilityStyle.sectionSpacing) {
                if let progress = CheckupProgressPresentation(state: store.state, currentStage: store.currentStage) {
                    InlineOperationProgress(progress: progress, title: L10n.string("simple.check_connection"))
                } else if store.error == nil {
                    Label(L10n.string(statusKey(store.state)), systemImage: store.state == .passed ? "checkmark.circle.fill" : "network")
                        .foregroundStyle(store.state == .passed ? Color.primary : Color.secondary)
                }
                if let warning = presentation.hostWarning { WarningBanner(warning: warning) }
                if !store.isRunning {
                    Button(L10n.string("simple.check_connection")) {
                        session.performCheckupAction(.runCheckup, profile: profile, showDiagnostics: showDiagnostics)
                    }
                    .disabled(operationCoordinator.isDeviceBusy(profile))
                }
                // Problems are never hidden in the diagnostic transcript.
                ForEach(presentation.domains) { domain in
                    ForEach(domain.attentionRows) { row in
                        UtilityNotice(color: row.status == .failed ? .red : .orange) { Text(row.message) }
                    }
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
                CheckupAdvancedOptionsView(store: store)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

private struct CheckupAdvancedOptionsView: View {
    @ObservedObject var store: DoctorStore

    var body: some View {
        DashboardDisclosureSection(title: L10n.string("checkup.advanced_options")) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Toggle(L10n.string("checkup.option.skip_ssh"), isOn: $store.skipSSH)
                    Toggle(L10n.string("checkup.option.skip_bonjour"), isOn: $store.skipBonjour)
                }
                GridRow {
                    Toggle(L10n.string("checkup.option.skip_smb"), isOn: $store.skipSMB)
                    EmptyView()
                }
            }
        }
        .disabled(store.isRunning)
    }
}
