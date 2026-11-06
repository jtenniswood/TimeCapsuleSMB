import SwiftUI

struct InstallTab: View {
    let profile: DeviceProfile
    @ObservedObject var session: DeviceDashboardSession
    @ObservedObject var operationCoordinator: OperationCoordinator
    let showDiagnostics: () -> Void
    let diagnosticsText: () -> String

    var body: some View {
        let store = session.deployStore
        let presentation = InstallWorkflowPresentation(state: store.state, result: store.result,
            error: store.error, events: store.events, currentStage: store.currentStage, profile: profile,
            isCheckupRunning: session.summary(for: profile).displayStatus == .checking)
        let isDeviceBusy = operationCoordinator.isDeviceBusy(profile)
        let firstInstall = profile.runtimeState == nil || profile.runtimeState?.state == .notInstalled

        ScrollView {
            VStack(alignment: .leading, spacing: UtilityStyle.sectionSpacing) {
                if let progress = InstallProgressPresentation(state: store.state, currentStage: store.currentStage) {
                    InlineOperationProgress(progress: progress, title: L10n.string("simple.sharing.title"))
                } else if presentation.error == nil {
                    Text(presentation.completion != nil ? L10n.string("utility.sharing.ready") :
                        session.summary(for: profile).displayStatus.title)
                }
                ForEach(presentation.notices, id: \.self) { notice in
                    UtilityNotice { Text(notice) }
                }
                if !store.isBusy {
                    HStack(spacing: 8) {
                        Button(L10n.string(firstInstall ? "simple.sharing.set_up" : "simple.sharing.update")) {
                            session.performInstallAction(.installUpdate, profile: profile, showDiagnostics: showDiagnostics)
                        }
                        .disabled(!InstallActionAvailabilityPolicy.isEnabled(.installUpdate, store: store, isDeviceBusy: isDeviceBusy))
                        if presentation.completion != nil {
                            Button(L10n.string("simple.open_disk")) { perform(.openFinder) }
                        }
                    }
                }
                if let completion = presentation.completion {
                    ForEach(completion.warnings) { warning in
                        UtilityNotice {
                            Text(warning.text)
                            if let action = warning.action {
                                Button(action.title) { perform(action) }
                                    .disabled(!InstallActionAvailabilityPolicy.isEnabled(action, store: store, isDeviceBusy: isDeviceBusy))
                            }
                        }
                    }
                }
                if let error = presentation.error {
                    ErrorRecoveryView(error: error, guidance: presentation.failureGuidance, diagnosticsText: diagnosticsText,
                        omittedActions: [.retry, .installSMB]) { kind in
                        kind == .diagnostics ? { showDiagnostics() } : session.recoveryAction(kind, error: error, profile: profile)
                    }
                }
                if presentation.timeline != nil || presentation.completion != nil {
                    DashboardDisclosureSection(title: L10n.string("utility.details")) {
                        if let completion = presentation.completion {
                            SummaryGrid(rows: completion.rows.filter { $0.label != L10n.string("deploy.result.message") }.map { ($0.label, $0.value) })
                        }
                        if let timeline = presentation.timeline, store.isBusy || presentation.completion == nil {
                            OperationTimelineListView(items: timeline.items)
                        }
                    }
                }
                InstallExecutionOptionsView(store: store, isDeviceBusy: isDeviceBusy)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func perform(_ action: InstallUserAction) {
        session.performInstallAction(action, profile: profile, showDiagnostics: showDiagnostics)
    }
}

private struct InstallExecutionOptionsView: View {
    @ObservedObject var store: DeployWorkflowStore
    let isDeviceBusy: Bool

    var body: some View {
        DashboardDisclosureSection(title: L10n.string("install.advanced_options")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(L10n.string("toggle.no_wait"), isOn: $store.noWait)
                    .help(L10n.string("install.advanced_options.no_wait_note"))
                Toggle(L10n.string("toggle.enable_rsync"), isOn: $store.rsyncEnabled)
                    .help(L10n.string("install.advanced_options.rsync_note"))
                HStack(spacing: 12) {
                    Text(L10n.string("field.mount_wait"))
                    TextField("", text: $store.mountWait)
                        .frame(width: 70)
                        .accessibilityLabel(L10n.string("field.mount_wait"))
                }
            }
            .padding(.top, 8)
        }
        .disabled(store.isBusy || isDeviceBusy)
    }

}
