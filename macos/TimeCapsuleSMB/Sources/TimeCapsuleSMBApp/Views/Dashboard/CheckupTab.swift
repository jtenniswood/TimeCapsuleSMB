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
        let presentation = CheckupPresentation(
            summary: store.summary,
            state: store.state,
            events: store.events,
            currentStage: store.currentStage,
            hostWarning: HostCompatibilityPolicy.warning(enabled: appSettings.timeMachineWarningsEnabled),
            localNetworkFacts: .current()
        )
        let progress = CheckupProgressPresentation(state: store.state, currentStage: store.currentStage)
        let isDeviceBusy = operationCoordinator.isDeviceBusy(profile)

        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    CheckupHeaderView(presentation: presentation)

                    if let warning = presentation.hostWarning {
                        WarningBanner(warning: warning)
                    }

                    if let action = presentation.primaryAction {
                        Button {
                            session.performCheckupAction(action, profile: profile, showDiagnostics: showDiagnostics)
                        } label: {
                            Label(action == .runCheckup ? L10n.string("simple.check_connection") : action.title, systemImage: action.systemImage)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isDeviceBusy)
                    }

                    if let progress {
                        InlineOperationProgress(progress: progress)
                    }

                    if !presentation.timeline.isEmpty && !store.isRunning {
                        DashboardDisclosureSection(title: L10n.string("simple.technical_details")) {
                            OperationTimelineListView(title: L10n.string("checkup.timeline.title"), items: presentation.timeline)
                            SummaryGrid(rows: presentation.summaryRows.map { ($0.label, $0.value) })
                        }
                    }

                    ForEach(presentation.domains) { domain in
                        CheckupDomainView(domain: domain)
                    }

                    CheckupAdvancedOptionsView(store: store)

                    if let error = store.error {
                        ErrorRecoveryView(
                            error: error,
                            diagnosticsText: diagnosticsText
                        ) { recoveryAction($0, error: error) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func recoveryAction(_ kind: RecoveryActionKind, error: BackendErrorViewModel) -> (() -> Void)? {
        kind == .diagnostics ? { showDiagnostics() } : session.recoveryAction(kind, error: error, profile: profile)
    }
}

private struct CheckupHeaderView: View {
    let presentation: CheckupPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.string("simple.tab.connection"))
                    .font(.title2.weight(.semibold))
                Spacer()
                Text(presentation.stateTitle)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
            Text(presentation.headline)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CheckupDomainView: View {
    let domain: CheckupDomainPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: domain.status.systemImage)
                        .foregroundStyle(iconColor(for: domain.status))
                        .accessibilityLabel(domain.status.title)
                    Text(domain.title)
                }
                .font(.headline)
                Spacer()
                Text(domain.status.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(domain.attentionRows) { row in
                checkRow(row)
            }
            DashboardDisclosureSection(title: L10n.string("simple.show_details")) {
                Text(domain.countSummary).font(.caption).foregroundStyle(.secondary)
                ForEach(domain.rows) { row in checkRow(row) }
            }

        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func checkRow(_ row: CheckupRowPresentation) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: row.status.systemImage)
                .foregroundStyle(iconColor(for: row.status))
                .accessibilityLabel(row.status.title)
                .frame(width: 16)
            Text(row.message).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func iconColor(for status: CheckupStatusPresentation) -> Color {
        switch status {
        case .passed:
            return .green
        case .warning:
            return .orange
        case .failed:
            return .red
        case .notChecked:
            return .secondary
        case .info, .unknown:
            return .primary
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
