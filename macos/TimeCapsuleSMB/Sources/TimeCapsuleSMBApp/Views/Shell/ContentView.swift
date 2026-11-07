import SwiftUI

public struct ContentView: View {
    @StateObject private var appStore: AppStore
    @ObservedObject private var appReadinessStore: AppReadinessStore
    @ObservedObject private var appSettingsStore: AppSettingsStore
    @ObservedObject private var deviceRegistry: DeviceRegistryStore
    @ObservedObject private var operationCoordinator: OperationCoordinator
    @ObservedObject private var activityStore: ActivityStore
    @ObservedObject private var deviceDiscovery: DeviceDiscoveryStore
    @ObservedObject private var appBackend: BackendClient
    @StateObject private var addDeviceStore: AddDeviceFlowStore
    @StateObject private var appSettingsEditorStore: AppSettingsEditorStore
    @StateObject private var dashboardStore: DashboardStore
    @ObservedObject private var presentation: ApplicationPresentationStore
    @State private var diagnosticsShowBackendEvents = true
    @State private var deleteErrorMessage: String?
    private let startsAutomatically: Bool
    private let updater: AppUpdater

    @MainActor
    public init(updater: AppUpdater) {
        self.init(composition: .production(), updater: updater)
    }

    @MainActor
    public init(application: ApplicationModel) {
        self.init(composition: application.composition, updater: application.updater, presentation: application.presentation)
    }

    @MainActor
    init(composition: AppViewComposition, startsAutomatically: Bool = true, updater: AppUpdater? = nil, presentation: ApplicationPresentationStore? = nil) {
        _presentation = ObservedObject(wrappedValue: presentation ?? ApplicationPresentationStore())
        _appStore = StateObject(wrappedValue: composition.appStore)
        _appReadinessStore = ObservedObject(wrappedValue: composition.appStore.appReadinessStore)
        _appSettingsStore = ObservedObject(wrappedValue: composition.appStore.appSettingsStore)
        _deviceRegistry = ObservedObject(wrappedValue: composition.appStore.deviceRegistry)
        _operationCoordinator = ObservedObject(wrappedValue: composition.appStore.operationCoordinator)
        _activityStore = ObservedObject(wrappedValue: composition.appStore.activityStore)
        _deviceDiscovery = ObservedObject(wrappedValue: composition.appStore.deviceDiscovery)
        _appBackend = ObservedObject(wrappedValue: composition.appStore.backend)
        _appSettingsEditorStore = StateObject(wrappedValue: composition.appSettingsEditorStore)
        _addDeviceStore = StateObject(wrappedValue: composition.addDeviceStore)
        _dashboardStore = StateObject(wrappedValue: composition.dashboardStore)
        self.startsAutomatically = startsAutomatically
        // Tests and previews get Sparkle unstarted: it never checks or shows anything.
        self.updater = updater ?? AppUpdater()
    }

    public var body: some View {
        VStack(spacing: 0) {
            if case .blocked = appReadinessStore.state {
                AppReadinessBlockedView(store: appReadinessStore) {
                    presentation.diagnosticsPresented = true
                }
            } else {
                AppReadinessBannerView(store: appReadinessStore) {
                    presentation.diagnosticsPresented = true
                }
                if let message = deviceRegistry.identityErrorMessage {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message).foregroundStyle(.red)
                        if let profile = deviceRegistry.conflictingProfile {
                            Button(L10n.format("discovery.open_saved_device", profile.title)) {
                                appStore.select(profile)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                detail
                    .frame(maxWidth: appStore.route == .allDevices ? .infinity : 920, maxHeight: .infinity)
                if appStore.route != .addDevice {
                    windowFooter
                }
            }
        }
        .frame(minWidth: 760, minHeight: 580)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(appStore.route == .activity ? L10n.string("sidebar.activity") : appStore.selectedProfile?.title ?? "Time Capsule Updater")
        .font(UtilityStyle.body)
        .controlSize(.regular)
        .preferredColorScheme(appSettingsStore.settings.appearance == .system ? nil : appSettingsStore.settings.appearance.preferredColorScheme(systemColorScheme: .light))
        .background(WindowCloseGuardInstaller())
        .onAppear {
            configureCloseGuard()
        }
        .task {
            if startsAutomatically {
                await appStore.start()
            }
            addDeviceStore.applyAppSettings(appSettingsStore.settings)
            appSettingsEditorStore.sync(settings: appSettingsStore.settings)
        }
        // Add Device hands over the device it saved, or a saved one clicked in
        // its list. The app opens it and takes the hand-off; Add Device has
        // already started over after a save, and a click leaves it as it was.
        .onChange(of: addDeviceStore.savedProfile) { _, profile in
            guard let profile else { return }
            dashboardStore.session(for: profile).selectedTab = profile.runtimeState?.state == .notInstalled ? .install : .overview
            appStore.openJustSaved(profile)
            addDeviceStore.clearHandoffs()
        }
        .onChange(of: addDeviceStore.profileToOpen) { _, profile in
            guard let profile else { return }
            appStore.select(profile)
            addDeviceStore.clearHandoffs()
        }
        .onChange(of: appSettingsStore.settings) { _, settings in
            addDeviceStore.applyAppSettings(settings)
            appSettingsEditorStore.sync(settings: settings)
        }
        .onChange(of: presentation.diagnosticsPresented) { _, isPresented in
            guard isPresented else { return }
            diagnosticsShowBackendEvents = appSettingsStore.settings.showRawBackendEventsByDefault
        }
        .sheet(isPresented: $presentation.diagnosticsPresented) {
            AppDiagnosticsView(
                store: appReadinessStore,
                exportContext: { includeBackendEvents in
                    appStore.diagnosticsExportContext(includeBackendEvents: includeBackendEvents)
                },
                showBackendEvents: $diagnosticsShowBackendEvents
            )
        }
        .confirmationDialog(
            L10n.string("dialog.forget.title"),
            isPresented: deleteConfirmationPresented,
            presenting: presentation.profilePendingDeletion
        ) { profile in
            Button(L10n.format("dialog.forget.action", profile.title), role: .destructive) {
                Task { @MainActor in
                    do {
                        try await appStore.forget(profile)
                        presentation.profilePendingDeletion = nil
                    } catch {
                        deleteErrorMessage = error.localizedDescription
                    }
                }
            }
            Button(L10n.string("action.cancel"), role: .cancel) {
                presentation.profilePendingDeletion = nil
            }
        } message: { profile in
            Text(L10n.format("dialog.forget.message", profile.title))
        }
        .alert(L10n.string("dialog.forget.error_title"), isPresented: deleteErrorPresented) {
            Button(L10n.string("action.ok"), role: .cancel) {
                deleteErrorMessage = nil
            }
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        .alert(
            operationCoordinator.readyConfirmation?.title ?? "",
            isPresented: confirmationPresented,
            presenting: operationCoordinator.readyConfirmation
        ) { confirmation in
            Button(confirmation.actionTitle, role: confirmation.isDestructive ? .destructive : nil) {
                operationCoordinator.confirm(confirmation)
            }
            if confirmation.prefersCancel {
                Button(L10n.string("action.cancel"), role: .cancel) {
                    operationCoordinator.cancel(confirmation)
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button(L10n.string("action.cancel"), role: .cancel) {
                    operationCoordinator.cancel(confirmation)
                }
            }
        } message: { confirmation in
            Text(confirmation.message)
        }
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { presentation.profilePendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    presentation.profilePendingDeletion = nil
                }
            }
        )
    }

    private var deleteErrorPresented: Binding<Bool> {
        Binding(
            get: { deleteErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    deleteErrorMessage = nil
                }
            }
        )
    }

    private var confirmationPresented: Binding<Bool> {
        let confirmation = operationCoordinator.readyConfirmation
        return Binding(
            get: { confirmation != nil },
            set: { isPresented in
                if !isPresented, let confirmation {
                    operationCoordinator.cancel(confirmation)
                }
            }
        )
    }

    private func configureCloseGuard() {
        AppCloseGuard.shared.configure { [weak operationCoordinator] in
            operationCoordinator?.hasBlockingWork ?? false
        }
    }

    @ViewBuilder
    private var windowFooter: some View {
        if appStore.route != .allDevices || activityStore.hasActiveActivity {
            VStack(spacing: 0) {
                if let profile = appStore.selectedProfile {
                    DeviceEditorFooter(profile: profile, session: dashboardStore.session(for: profile), appStore: appStore)
                } else if appStore.route != .allDevices {
                    UtilityFooter {
                        Spacer()
                        Button(L10n.string("action.done")) { appStore.navigate(to: .allDevices) }
                            .keyboardShortcut(.cancelAction)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch appStore.route {
        case .activity:
            ActivityDetailView(
                activityStore: activityStore,
                registry: deviceRegistry
            )
        case .appSettings:
            AppSettingsView(
                appStore: appStore,
                appSettingsStore: appSettingsStore,
                editor: appSettingsEditorStore,
                updater: updater
            )
        case .addDevice:
            AddDeviceView(store: addDeviceStore, onCancel: { appStore.navigate(to: .allDevices) })
        case .device(let profileID):
            if let profile = deviceRegistry.profile(id: profileID) {
                DeviceDashboardView(
                    profile: profile,
                    session: dashboardStore.session(for: profile),
                    appStore: appStore,
                    justSaved: appStore.justSavedProfileID == profile.id,
                    appSettingsStore: appSettingsStore,
                    reachabilityStore: appStore.reachabilityStore,
                    sshAccessStore: appStore.sshAccessStore,
                    operationCoordinator: operationCoordinator,
                    backend: appBackend,
                    showDiagnostics: {
                        presentation.diagnosticsPresented = true
                    }
                )
            } else {
                DeviceListOverviewView(
                    appStore: appStore,
                    deviceRegistry: deviceRegistry,
                    deviceDiscovery: deviceDiscovery,
                    backend: appBackend,
                    dashboardStore: dashboardStore,
                    addManually: { addDeviceStore.startManualEntry(); appStore.showAddDevice() },
                    canAddDevice: !addDeviceStore.isAdding,
                    addDiscoveredDevice: { device in
                        addDeviceStore.select(device)
                        addDeviceStore.continueToPassword()
                        appStore.showAddDevice()
                    }
                )
            }
        case .allDevices:
            DeviceListOverviewView(
                appStore: appStore,
                deviceRegistry: deviceRegistry,
                deviceDiscovery: deviceDiscovery,
                backend: appBackend,
                dashboardStore: dashboardStore,
                addManually: { addDeviceStore.startManualEntry(); appStore.showAddDevice() },
                canAddDevice: !addDeviceStore.isAdding,
                addDiscoveredDevice: { device in
                    addDeviceStore.select(device)
                    addDeviceStore.continueToPassword()
                    appStore.showAddDevice()
                }
            )
        }
    }
}

extension AppAppearance {
    func preferredColorScheme(systemColorScheme: ColorScheme) -> ColorScheme? {
        switch self {
        case .system:
            return systemColorScheme
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

private struct DeviceEditorFooter: View {
    let profile: DeviceProfile
    @ObservedObject var session: DeviceDashboardSession
    @ObservedObject var appStore: AppStore

    var body: some View {
        UtilityFooter {
            if appStore.canCancelSelectedOperation && !showsInlineCancel {
                Button(L10n.string("toolbar.cancel")) { appStore.cancelSelectedOperation() }
            }
            Spacer()
            Button(L10n.string("action.done")) { appStore.navigate(to: .allDevices) }
                .keyboardShortcut(.cancelAction)
        }
    }

    private var showsInlineCancel: Bool {
        session.selectedTab.visibleTab == .overview && session.deployStore.isBusy
    }
}
