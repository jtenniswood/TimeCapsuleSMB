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
        let state = store.state == .idle ? profile.lastCheckup?.state ?? .idle : store.state
        VStack(alignment: .leading, spacing: 12) {
            if let progress = CheckupProgressPresentation(state: store.state, currentStage: store.currentStage) {
                InlineOperationProgress(progress: progress, title: L10n.string("simple.check_connection"))
            } else {
                HStack {
                    Label(L10n.string(statusKey(state)), systemImage: state == .passed ? "checkmark.circle.fill" : "network")
                    Spacer()
                    Button(L10n.string("simple.check_connection")) {
                        session.performCheckupAction(.runCheckup, profile: profile, showDiagnostics: showDiagnostics)
                    }.disabled(operationCoordinator.isDeviceBusy(profile))
                }
            }
            if let error = store.error, !["cancelled", "confirmation_cancelled"].contains(error.code) {
                Text(error.message).foregroundStyle(.red)
            }
            let presentation = CheckupPresentation(summary: store.summary, state: store.state, events: store.events,
                currentStage: store.currentStage, hostWarning: nil, localNetworkFacts: .current())
            ForEach(presentation.domains) { domain in
                ForEach(domain.attentionRows.filter { UtilityCheckupLayout.isUrgent($0.id) }) { row in
                    Text(row.message).foregroundStyle(row.status == .failed ? Color.red : .orange)
                }
            }
            if let checkedAt = profile.lastCheckup?.checkedAt {
                Text(L10n.format("disk_health.checked_at", checkedAt.formatted(date: .abbreviated, time: .shortened)))
                    .font(UtilityStyle.secondary).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
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
