import SwiftUI

struct DeviceDashboardView: View {
    let profile: DeviceProfile
    @ObservedObject var session: DeviceDashboardSession
    let appStore: AppStore
    /// Add Device just saved this device, and the page has not been left since.
    let justSaved: Bool
    @ObservedObject var appSettingsStore: AppSettingsStore
    @ObservedObject var reachabilityStore: DeviceReachabilityStore
    @ObservedObject var sshAccessStore: DeviceSSHAccessStore
    @ObservedObject var operationCoordinator: OperationCoordinator
    @ObservedObject var backend: BackendClient
    let showDiagnostics: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                if justSaved { DashboardSavedNoticeView(deviceName: profile.title) }
                if let notice = session.staleEndpointNotice(for: profile) {
                    DashboardStaleEndpointNoticeView(notice: notice) {
                        session.updateConfiguredAddressFromDiscovery(profile: profile)
                    }
                }
                OverviewTab(profile: profile, session: session, reachabilityStore: reachabilityStore,
                            showDiagnostics: showDiagnostics, diagnosticsText: diagnosticsText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(UtilityStyle.panePadding)
        }
        .sheet(isPresented: $session.maintenanceUtilitiesExpanded) {
            MaintenanceToolSheet(profile: profile, session: session, showDiagnostics: showDiagnostics, diagnosticsText: diagnosticsText)
        }
        .font(UtilityStyle.body)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        // Keyed by device: switching straight from one device to another keeps
        // this view, so onAppear would not run for the second.
        .task(id: profile.id) {
            await session.refreshDeviceStatus(profile: profile)
        }
        .alert(L10n.string("flash.manual_power_cycle.title"), isPresented: manualPowerCycleNoticePresented) {
            Button(L10n.string("dashboard.action.view_checkup")) {
                session.viewCheckupAfterPowerCycleNotice()
            }
            // Closing the alert dismisses the notice through the binding.
            Button(L10n.string("action.ok"), role: .cancel) {}
        } message: {
            Text(L10n.string("flash.manual_power_cycle.message"))
        }
    }

    private var manualPowerCycleNoticePresented: Binding<Bool> {
        Binding(
            get: { session.maintenanceStore.bootHookStore.showsManualPowerCycleNotice },
            set: { isPresented in
                if !isPresented {
                    session.maintenanceStore.bootHookStore.dismissManualPowerCycleNotice()
                }
            }
        )
    }

    private func diagnosticsText() -> String {
        DiagnosticsExportBuilder().build(context: appStore.diagnosticsExportContext(includeBackendEvents: true))
    }
}

private struct DashboardSavedNoticeView: View {
    let deviceName: String
    var body: some View {
        Label(L10n.format("add_device.saved", deviceName), systemImage: "checkmark.circle")
            .font(UtilityStyle.secondary).foregroundStyle(.secondary)
    }
}

private struct DashboardStaleEndpointNoticeView: View {
    let notice: StaleEndpointNotice
    let update: () -> Void

    var body: some View {
        UtilityNotice {
            Text(L10n.string("utility.connection.address_changed"))
            Button(L10n.string("utility.connection.reconnect"), action: update)
            DashboardDisclosureSection(title: L10n.string("utility.details")) {
                Text(L10n.format("stale_endpoint.message", notice.configuredHost, notice.currentHost))
                if notice.matchedByName { Text(L10n.format("stale_endpoint.name_match", notice.discoveredDevice.name)) }
            }
        }
    }
}
