import AppKit
import SwiftUI

struct MaintenanceTab: View {
    let profile: DeviceProfile
    @ObservedObject var session: DeviceDashboardSession
    let showDiagnostics: () -> Void
    let diagnosticsText: () -> String

    var body: some View {
        let busy = session.appStore.operationCoordinator.isDeviceBusy(profile)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 8) {
                    Button(L10n.string("utility.disk.repair")) { open(.fsck) }
                    Button(L10n.string("utility.disk.erase")) { open(.wipeDisk) }
                    Spacer()
                    Button(L10n.string("simple.disk.refresh")) {
                        session.runCheckup(profile: profile)
                        if session.selectedTab == .checkup { session.selectedTab = .maintenance }
                    }
                }
                .disabled(busy)
                DiskHealthView(report: profile.lastCheckup?.diskHealth, checkedAt: profile.lastCheckup?.checkedAt)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $session.maintenanceUtilitiesExpanded) {
            MaintenanceToolSheet(profile: profile, session: session, showDiagnostics: showDiagnostics, diagnosticsText: diagnosticsText)
        }
    }

    private func open(_ workflow: MaintenanceWorkflow) {
        session.maintenanceStore.selectedWorkflow = workflow
        session.maintenanceUtilitiesExpanded = true
    }
}

/// Each tool opens in its own native sheet; no unrelated utility picker.
struct MaintenanceToolSheet: View {
    let profile: DeviceProfile
    @ObservedObject var session: DeviceDashboardSession
    let showDiagnostics: () -> Void
    let diagnosticsText: () -> String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let store = session.maintenanceStore
        let presentation = MaintenanceDashboardPresentation(store: store, profile: profile).detail
        VStack(alignment: .leading, spacing: 0) {
            Text(presentation.workflow.utilityTitle).font(UtilityStyle.title)
                .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    MaintenanceDetailView(presentation: presentation, store: store,
                        performAction: { session.performMaintenanceAction($0, profile: profile, showDiagnostics: showDiagnostics) },
                        chooseFirmwareTemplate: { chooseFirmwareTemplate(store: store.bootHookStore) })
                    if let error = presentation.error {
                        ErrorRecoveryView(error: error, diagnosticsText: diagnosticsText) { kind in
                            kind == .diagnostics ? { showDiagnostics() } : session.recoveryAction(kind, error: error, profile: profile)
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            UtilityFooter {
                if store.isBusy && session.appStore.canCancelSelectedOperation {
                    Button(L10n.string("action.cancel")) { session.appStore.cancelSelectedOperation() }
                }
                Spacer()
                Button(L10n.string("action.done")) {
                    session.maintenanceUtilitiesExpanded = false
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .font(UtilityStyle.body).controlSize(.regular)
        .frame(width: 620, height: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: presentation.workflow) {
            guard !store.isBusy else { return }
            if presentation.workflow == .fsck && store.fsckTargets.isEmpty {
                session.performMaintenanceAction(.findVolumes, profile: profile, showDiagnostics: showDiagnostics)
            } else if presentation.workflow == .sshAccess && store.sshAccessPayload == nil {
                session.performMaintenanceAction(.checkSSHAccess, profile: profile, showDiagnostics: showDiagnostics)
            }
        }
    }

    private func chooseFirmwareTemplate(store: BootHookStore) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.string("maintenance.action.choose")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in store.firmwareTemplatePath = url.path }
        }
    }
}

private struct MaintenanceDetailView: View {
    let presentation: MaintenanceWorkflowDetailPresentation
    @ObservedObject var store: MaintenanceStore
    let performAction: (MaintenanceUserAction) -> Void
    let chooseFirmwareTemplate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if presentation.isRunning {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(L10n.string("utility.status.working_on_device"))
                }
            } else if presentation.completion != nil || (presentation.workflow == .bootHook && store.bootHookStore.writeResult != nil) {
                Label(L10n.string("action.done"), systemImage: "checkmark.circle")
            }
            Text(L10n.string("utility.tools.\(presentation.workflow.rawValue).message"))
                .foregroundStyle(.secondary)

            ForEach(presentation.warnings, id: \.self) { warning in
                MaintenanceWarningLabel(text: warning)
            }

            if presentation.workflow == .fsck, !store.fsckTargets.isEmpty {
                FsckTargetListView(store: store)
            }
            let primary = MaintenanceGuidePolicy.primaryAction(presentation: presentation)
            if !presentation.isRunning {
                MaintenanceActionButton(action: primary, title: primary.utilityTitle,
                    isEnabled: presentation.isEnabled(primary), perform: performAction)
            }
            if let plan = presentation.plan {
                ForEach(plan.warnings, id: \.self) { warning in MaintenanceWarningLabel(text: warning) }
            }
            if presentation.workflow == .wipeDisk, store.wipeDiskState == .succeeded,
               store.wipeDiskResult?.offerInstall == true {
                Button(L10n.string("simple.sharing.set_up")) { performAction(.installSMB) }
                    .disabled(store.isBusy)
            }
            DashboardDisclosureSection(title: L10n.string("utility.details")) {
                Text(presentation.statusMessage).font(UtilityStyle.secondary).foregroundStyle(.secondary)
                if !presentation.bootHookRows.isEmpty { BootHookRowsView(rows: presentation.bootHookRows) }
                if let plan = presentation.plan {
                    SummaryGrid(rows: plan.rows.map { ($0.label, $0.value) })
                }
                if let completion = presentation.completion {
                    SummaryGrid(rows: completion.rows.map { ($0.label, $0.value) })
                }
                if let timeline = presentation.timeline, !timeline.items.isEmpty {
                    MaintenanceTimelineView(presentation: timeline)
                }
                WrappingHStack {
                    ForEach(presentation.actionRows.flatMap { $0 }.filter { $0 != primary && $0 != .installSMB }) { action in
                        MaintenanceActionButton(action: action, title: action.utilityTitle,
                            isEnabled: presentation.isEnabled(action), perform: performAction)
                    }
                }
                if presentation.workflow == .bootHook {
                    BootHookFirmwareOptionsView(store: store.bootHookStore, chooseFirmwareTemplate: chooseFirmwareTemplate)
                }
            }


        }
    }

}

private struct MaintenanceActionButton: View {
    let action: MaintenanceUserAction
    let title: String
    let isEnabled: Bool
    let perform: (MaintenanceUserAction) -> Void

    var body: some View {
        Button(title) { perform(action) }
            .disabled(!isEnabled)
    }

}

private struct FsckTargetListView: View {
    @ObservedObject var store: MaintenanceStore

    var body: some View {
        UtilityFormRow(title: L10n.string("utility.disk.volume")) {
            Picker(L10n.string("utility.disk.volume"), selection: $store.selectedFsckTargetID) {
                ForEach(store.fsckTargets) { target in
                    Text(target.name ?? target.device).tag(Optional(target.id))
                }
            }
            .labelsHidden()
            .disabled(store.isBusy)
        }
    }

}

/// Lays out its views left to right and starts a new line when the next one
/// does not fit, so a row of long translated buttons wraps instead of
/// truncating their labels. A view wider than the whole row still truncates.
struct WrappingHStack: Layout {
    var spacing: CGFloat = 8

    private struct Line {
        var indices: [Int]
        var width: CGFloat
        var height: CGFloat
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = lines(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(
            width: lines.map(\.width).max() ?? 0,
            height: lines.map(\.height).reduce(0, +) + spacing * CGFloat(max(lines.count - 1, 0))
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in line.indices {
                let size = size(of: subviews[index], width: bounds.width)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + spacing
        }
    }

    private func lines(width: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = []
        for (index, subview) in subviews.enumerated() {
            let size = size(of: subview, width: width)
            if let last = lines.last, last.width + spacing + size.width <= width {
                lines[lines.count - 1].indices.append(index)
                lines[lines.count - 1].width += spacing + size.width
                lines[lines.count - 1].height = max(last.height, size.height)
            } else {
                lines.append(Line(indices: [index], width: size.width, height: size.height))
            }
        }
        return lines
    }

    private func size(of subview: LayoutSubview, width: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        return ideal.width <= width ? ideal : subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }
}

/// A warning in the normal text color with an orange icon: orange or yellow
/// text is too faint to read on a light background.
private struct MaintenanceWarningLabel: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
        .font(UtilityStyle.secondary)
    }
}

/// The boot hook's backup, plan and write details, each value selectable.
private struct BootHookRowsView: View {
    let rows: [PresentationRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.label)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(row.value)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                .font(UtilityStyle.secondary)
            }
        }
    }
}

private struct BootHookFirmwareOptionsView: View {
    @ObservedObject var store: BootHookStore
    let chooseFirmwareTemplate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L10n.string("field.firmware_version"), text: $store.firmwareVersion)
            HStack {
                TextField(L10n.string("field.firmware_template"), text: $store.firmwareTemplatePath)
                Button {
                    chooseFirmwareTemplate()
                } label: {
                    Label(L10n.string("flash.action.choose_template"), systemImage: "doc")
                }
            }
        }
        .textFieldStyle(.roundedBorder)
        // A plan is made for these values; changing them mid-run would leave
        // the plan on screen without them.
        .disabled(store.isBusy)
    }
}

struct MaintenanceTimelineView: View {
    let presentation: MaintenanceTimelinePresentation

    var body: some View {
        OperationTimelineListView(
            title: L10n.string("maintenance.timeline.title"),
            items: presentation.items
        )
    }
}
