import SwiftUI

struct InstallTab: View {
    let profile: DeviceProfile
    @ObservedObject var session: DeviceDashboardSession
    @ObservedObject var operationCoordinator: OperationCoordinator
    let showDiagnostics: () -> Void
    let diagnosticsText: () -> String

    var body: some View {
        let store = session.deployStore
        let summary = session.summary(for: profile)
        let presentation = InstallWorkflowPresentation(
            state: store.state,
            result: store.result,
            error: store.error,
            events: store.events,
            currentStage: store.currentStage,
            profile: profile,
            isCheckupRunning: summary.displayStatus == .checking
        )
        let progress = InstallProgressPresentation(state: store.state, currentStage: store.currentStage)
        let isDeviceBusy = operationCoordinator.isDeviceBusy(profile)

        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    InstallHeaderView(presentation: presentation, isIdle: store.state == .idle)
                    if store.state == .idle {
                        Text(L10n.string("simple.sharing.message"))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let progress { InlineOperationProgress(progress: progress) }

                    ForEach(presentation.notices, id: \.self) { notice in
                        Label(notice, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }

                    if !presentation.actions.isEmpty {
                        HStack {
                            ForEach(presentation.actions) { action in
                                InstallActionButton(action: action, firstInstall: profile.runtimeState == nil || profile.runtimeState?.state == .notInstalled) {
                                    session.performInstallAction(action, profile: profile, showDiagnostics: showDiagnostics)
                                }
                                .disabled(isDisabled(action, store: store, isDeviceBusy: isDeviceBusy))
                            }
                        }
                    }

                    if let timeline = presentation.timeline {
                        DashboardDisclosureSection(title: L10n.string("simple.technical_details")) {
                            InstallTimelineView(presentation: timeline)
                        }
                    }

                    if let error = presentation.error {
                        ErrorRecoveryView(
                            error: error,
                            guidance: presentation.failureGuidance,
                            diagnosticsText: diagnosticsText
                        ) { recoveryAction($0, error: error) }
                    }

                    if let completion = presentation.completion {
                        InstallCompletionView(
                            presentation: completion,
                            isDisabled: { isDisabled($0, store: store, isDeviceBusy: isDeviceBusy) }
                        ) { action in
                            session.performInstallAction(action, profile: profile, showDiagnostics: showDiagnostics)
                        }
                    }

                    InstallExecutionOptionsView(store: store, isDeviceBusy: isDeviceBusy)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func recoveryAction(_ kind: RecoveryActionKind, error: BackendErrorViewModel) -> (() -> Void)? {
        kind == .diagnostics ? { showDiagnostics() } : session.recoveryAction(kind, error: error, profile: profile)
    }

    private func isDisabled(_ action: InstallUserAction, store: DeployWorkflowStore, isDeviceBusy: Bool) -> Bool {
        !InstallActionAvailabilityPolicy.isEnabled(action, store: store, isDeviceBusy: isDeviceBusy)
    }
}

private struct InstallHeaderView: View {
    let presentation: InstallWorkflowPresentation
    let isIdle: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.string("simple.sharing.title"))
                    .font(.title2.weight(.semibold))
                Spacer()
                if !isIdle {
                    Text(presentation.stateTitle)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
            }
            if !isIdle {
                Text(presentation.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct InstallActionButton: View {
    let action: InstallUserAction
    var firstInstall = false
    let perform: () -> Void

    var body: some View {
        if action == .installUpdate {
            Button(action: perform) {
                Label(L10n.string(firstInstall ? "simple.sharing.set_up" : "simple.sharing.update"), systemImage: action.systemImage)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button(action: perform) {
                Label(action.title, systemImage: action.systemImage)
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct InstallTimelineView: View {
    let presentation: InstallTimelinePresentation

    var body: some View {
        OperationTimelineListView(
            title: L10n.string("install.timeline.title"),
            emptyMessage: L10n.string("install.timeline.waiting"),
            items: presentation.items
        )
    }
}

private struct InstallCompletionView: View {
    let presentation: InstallCompletionPresentation
    let isDisabled: (InstallUserAction) -> Bool
    let performAction: (InstallUserAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(presentation.title)
                .font(.headline)
            SummaryGrid(rows: presentation.rows.map { ($0.label, $0.value) })
            ForEach(presentation.warnings) { warning in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(warning.text, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    if let action = warning.action {
                        Button {
                            performAction(action)
                        } label: {
                            Label(action.title, systemImage: action.systemImage)
                        }
                        .controlSize(.small)
                        .disabled(isDisabled(action))
                    }
                }
            }
            HStack {
                ForEach(presentation.actions) { action in
                    Button {
                        performAction(action)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                    .disabled(isDisabled(action))
                }
            }
        }
    }
}

private struct InstallExecutionOptionsView: View {
    @ObservedObject var store: DeployWorkflowStore
    let isDeviceBusy: Bool

    var body: some View {
        DashboardDisclosureSection(title: L10n.string("install.advanced_options")) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Toggle(L10n.string("toggle.no_wait"), isOn: $store.noWait)
                        .gridCellColumns(2)
                }
                GridRow {
                    Text(L10n.string("install.advanced_options.no_wait_note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .gridCellColumns(2)
                }
                GridRow {
                    Toggle(L10n.string("toggle.enable_rsync"), isOn: $store.rsyncEnabled)
                        .gridCellColumns(2)
                }
                GridRow {
                    Text(L10n.string("install.advanced_options.rsync_note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .gridCellColumns(2)
                }
                GridRow {
                    Text(L10n.string("field.mount_wait"))
                        .foregroundStyle(.secondary)
                    TextField(L10n.string("field.mount_wait"), text: $store.mountWait)
                        .frame(width: 150)
                }
            }
        }
        .disabled(store.isBusy || isDeviceBusy)
    }

}
