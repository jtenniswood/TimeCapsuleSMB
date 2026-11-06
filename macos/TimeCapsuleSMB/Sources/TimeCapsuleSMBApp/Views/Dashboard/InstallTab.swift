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
                VStack(alignment: .leading, spacing: 16) {
                    if let progress = InstallProgressPresentation(state: store.state, currentStage: store.currentStage) {
                        InlineOperationProgress(progress: progress, title: L10n.string("simple.sharing.title"))
                    } else if presentation.error == nil {
                        UtilityFormRow(title: L10n.string("simple.sharing.title")) {
                            Text(session.summary(for: profile).displayStatus.title)
                        }
                    }
                    if !firstInstall && !store.isBusy {
                        UtilityFormRow(title: L10n.string("dashboard.overview.installed_version")) {
                            let reachability = session.appStore.reachabilityStore
                            let payload = DeviceDashboardHeaderPresentation.currentVersionPayload(reachability.snapshot(for: profile), profile: profile)
                            if payload == nil && reachability.isRefreshing(profile: profile) {
                                ProgressView().controlSize(.small)
                            } else {
                                Text(DeviceDashboardHeaderPresentation.installedVersionValue(runtimeState: profile.runtimeState?.state, payload: payload))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    if !store.isBusy {
                        UtilityFormRow(title: "") {
                            Button(L10n.string(firstInstall ? "simple.sharing.set_up" : "simple.sharing.update")) {
                                session.performInstallAction(.installUpdate, profile: profile, showDiagnostics: showDiagnostics)
                            }
                            .disabled(!InstallActionAvailabilityPolicy.isEnabled(.installUpdate, store: store, isDeviceBusy: isDeviceBusy))
                        }
                    }
                }
                ForEach(presentation.notices, id: \.self) { notice in
                    UtilityNotice { Text(notice) }
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
        .task(id: InstalledVersionRefresh(profileID: profile.id, finishedAt: profile.lastDeployState?.finishedAt, deviceBusy: isDeviceBusy)) {
            guard !isDeviceBusy else { return }
            await session.refreshInstalledVersion(profile: profile)
        }
    }

    private func perform(_ action: InstallUserAction) {
        session.performInstallAction(action, profile: profile, showDiagnostics: showDiagnostics)
    }
}

private struct InstalledVersionRefresh: Equatable {
    let profileID: DeviceProfile.ID
    let finishedAt: Date?
    let deviceBusy: Bool
}

private struct InstallExecutionOptionsView: View {
    @ObservedObject var store: DeployWorkflowStore
    let isDeviceBusy: Bool

    var body: some View {
        DashboardDisclosureSection(title: L10n.string("install.advanced_options")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(L10n.string("toggle.no_wait"), isOn: $store.noWait)
                    .help(L10n.string("install.advanced_options.no_wait_note"))

            }
            .padding(.top, 8)
        }
        .disabled(store.isBusy || isDeviceBusy)
    }

}
