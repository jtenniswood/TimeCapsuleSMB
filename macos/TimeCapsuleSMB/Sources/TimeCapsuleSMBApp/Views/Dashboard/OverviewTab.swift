import SwiftUI

struct OverviewTab: View {
    let profile: DeviceProfile
    @ObservedObject var session: DeviceDashboardSession
    @ObservedObject var reachabilityStore: DeviceReachabilityStore
    var showDiagnostics: () -> Void = {}
    var diagnosticsText: () -> String = { "" }

    var body: some View {
        let summary = session.summary(for: profile)
        let payload = DeviceDashboardHeaderPresentation.currentVersionPayload(reachabilityStore.snapshot(for: profile), profile: profile)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 20) {
                    AirPortDeviceIcon(isTower: profile.usesTowerArtwork).frame(width: 64, height: 86)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(profile.title).font(UtilityStyle.title)
                        Text(DeviceDashboardHeaderPresentation.friendlyModelValue(for: profile)).foregroundStyle(.secondary)
                        HStack(spacing: 7) {
                            DeviceStatusLight(status: summary.displayStatus)
                            Text(summary.displayStatus.title)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .help(DeviceDashboardHeaderPresentation.deviceTooltip(for: profile, payload: payload))
                FileSharingStatusView(profile: profile, session: session, reachability: reachabilityStore)
            }
            .frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity, alignment: .top)
        }
        .task(id: OverviewRefresh(profileID: profile.id, finishedAt: profile.lastDeployState?.finishedAt,
            busy: session.appStore.operationCoordinator.isDeviceBusy(profile))) {
            guard !session.appStore.operationCoordinator.isDeviceBusy(profile) else { return }
            await session.refreshInstalledVersion(profile: profile)
            await session.refreshSharingSettings(profile: profile)
        }
    }
}

private struct OverviewRefresh: Equatable {
    let profileID: DeviceProfile.ID
    let finishedAt: Date?
    let busy: Bool
}

private struct FileSharingStatusView: View {
    let profile: DeviceProfile
    @ObservedObject var session: DeviceDashboardSession
    @ObservedObject var reachability: DeviceReachabilityStore

    var body: some View {
        let store = session.deployStore
        let payload = DeviceDashboardHeaderPresentation.currentVersionPayload(reachability.snapshot(for: profile), profile: profile)
        let state = FileSharingInstallationPresentation(profile: profile, payload: payload, sharing: session.sharingStore.snapshot,
            checking: reachability.isRefreshing(profile: profile) || session.sharingStore.loading)
        GroupBox(L10n.string("simple.sharing.title")) {
            VStack(alignment: .leading, spacing: 12) {
                if store.isBusy {
                    FileSharingProgressView(store: store)
                } else {
                    HStack {
                        Label(state.statusTitle, systemImage: state.state == .upToDate ? "checkmark.circle.fill" :
                            state.needsInstall ? "arrow.down.circle" : "checkmark.circle")
                        Spacer()
                        if let version = state.version { Text(version).foregroundStyle(.secondary).monospacedDigit() }
                    }
                    if state.needsInstall {
                        HStack {
                            Text(L10n.string("sharing.update_help")).font(UtilityStyle.secondary).foregroundStyle(.secondary)
                            Spacer()
                            Button(L10n.string(state.state == .notInstalled ? "simple.sharing.set_up" : "simple.sharing.update")) {
                                session.runInstall(profile: profile)
                            }.disabled(session.appStore.operationCoordinator.isDeviceBusy(profile))
                        }
                    }
                    if let error = store.error, !["cancelled", "confirmation_cancelled"].contains(error.code) {
                        Text(error.message).foregroundStyle(.red)
                    }
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FileSharingProgressView: View {
    @ObservedObject var store: DeployWorkflowStore

    var body: some View {
        HStack(spacing: 16) {
            if let progress = InstallProgressPresentation(state: store.state, currentStage: store.currentStage) {
                InlineOperationProgress(progress: progress, title: L10n.string("simple.sharing.title"))
            } else {
                ProgressView().controlSize(.small)
                Text(L10n.string("simple.sharing.title"))
            }
            Spacer(minLength: 8)
            Button(L10n.string("toolbar.cancel")) { store.cancel() }.disabled(!store.canCancel)
        }
    }
}
