import SwiftUI

struct SettingsTab: View {
    let profile: DeviceProfile
    @ObservedObject var session: DeviceDashboardSession
    let appStore: AppStore
    @ObservedObject var backend: BackendClient

    var body: some View {
        DeviceProfileEditorView(profile: profile, store: session.profileEditorStore,
                                recoveryAction: { kind, error in session.recoveryAction(kind, error: error, profile: profile) },
                                diagnosticsText: {
            DiagnosticsExportBuilder().build(context: appStore.diagnosticsExportContext(includeBackendEvents: true))
        })
    }
}

private struct DeviceProfileEditorView: View {
    let profile: DeviceProfile
    @ObservedObject var store: DeviceProfileEditorStore
    let recoveryAction: (RecoveryActionKind, BackendErrorViewModel) -> (() -> Void)?
    let diagnosticsText: () -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 12) {
                UtilityFormRow(title: L10n.string("utility.device.name")) {
                    TextField("", text: $store.draft.displayName).accessibilityLabel(L10n.string("utility.device.name"))
                }
                UtilityFormRow(title: L10n.string("simple.address")) {
                    TextField("", text: $store.draft.address).accessibilityLabel(L10n.string("simple.address"))
                }
                UtilityFormRow(title: L10n.string("simple.setup.password")) {
                    RevealablePasswordField(L10n.string("dashboard.replacement_password"), text: $store.replacementPassword)
                }
            }
            .disabled(store.isRunning)
            if let passwordError = store.passwordError { Text(passwordError).foregroundStyle(.red) }
            if let error = store.error {
                ErrorRecoveryView(error: error, diagnosticsText: diagnosticsText, omittedActions: [.retry, .replacePassword]) { recoveryAction($0, error) }
            }
            ForEach(store.validationErrors, id: \.self) { error in Text(error.localizedDescription).foregroundStyle(.red) }
            DashboardDisclosureSection(title: L10n.string("profile_editor.advanced")) {
                DeviceAdvancedSettingsFields(
                    rsyncEnabled: $store.draft.rsyncEnabled,
                    internalShareUseDiskRoot: $store.draft.internalShareUseDiskRoot,
                    smbBrowseCompatibility: $store.draft.smbBrowseCompatibility,
                    mdnsAdvertiseAFP: $store.draft.mdnsAdvertiseAFP,
                    anyProtocol: $store.draft.anyProtocol,
                    requireSMBSigning: $store.draft.requireSMBSigning,
                    requireSMBEncryption: $store.draft.requireSMBEncryption,
                    disableSMBEncryption: $store.draft.disableSMBEncryption,
                    fruitMetadataNetatalk: $store.draft.fruitMetadataNetatalk,
                    vfsAIOForkEnabled: $store.draft.vfsAIOForkEnabled,
                    debugLogging: $store.draft.debugLogging,
                    mountWaitSeconds: $store.draft.mountWaitSeconds,
                    ataIdleSeconds: $store.draft.ataIdleSeconds,
                    ataStandby: $store.draft.ataStandby
                )
                .help(L10n.string("profile_editor.advanced.deploy_notice")).disabled(store.isRunning)
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear { store.sync(to: profile) }
        .onChange(of: profile) { _, profile in store.sync(to: profile) }
    }
}
