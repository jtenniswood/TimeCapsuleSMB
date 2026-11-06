import SwiftUI

struct AppSettingsView: View {
    let appStore: AppStore
    @ObservedObject var appSettingsStore: AppSettingsStore
    @ObservedObject var editor: AppSettingsEditorStore
    @ObservedObject var updater: AppUpdater
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPane = 0
    @State private var automaticUpdates = true

    var body: some View {
        VStack(spacing: 0) {
            UtilityTabs(tabs: [(id: 0, title: L10n.string("app_settings.section.general")),
                               (id: 1, title: L10n.string("profile_editor.advanced"))], selection: $selectedPane) { pane in
                if pane == 0 { general } else { advanced }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            if let message = editor.validationError ?? editor.errorMessage ?? appSettingsStore.error?.localizedDescription {
                Text(message).font(UtilityStyle.secondary).foregroundStyle(.red).padding(.horizontal, 24)
            }
            UtilityFooter {
                if editor.isSaving { ProgressView().controlSize(.small) }
                Spacer()
                Button(L10n.string("action.cancel")) { editor.resetDraft(); dismiss() }
                    .keyboardShortcut(.cancelAction).disabled(editor.isSaving)
                Button(L10n.string("utility.save")) {
                    Task { @MainActor in
                        await editor.save(appStore: appStore)
                        if editor.errorMessage == nil && editor.validationError == nil {
                            updater.automaticallyChecksForUpdates = automaticUpdates
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editor.isSaving || editor.validationError != nil || (!editor.hasChanges && automaticUpdates == updater.automaticallyChecksForUpdates))
            }
        }
        .font(UtilityStyle.body)
        .background(Color(nsColor: UtilityStyle.windowBackground))
        .onAppear {
            editor.sync(settings: appSettingsStore.settings)
            automaticUpdates = updater.automaticallyChecksForUpdates
        }
        .onDisappear { editor.resetDraft() }
        .onChange(of: appSettingsStore.settings) { _, settings in editor.sync(settings: settings) }
    }

    private var general: some View {
        UtilityPane {
            VStack(spacing: 12) {
                UtilityFormRow(title: L10n.string("app_settings.language")) {
                    Picker("", selection: $editor.draft.language) {
                        ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 220, alignment: .leading)
                    .accessibilityLabel(L10n.string("app_settings.language"))
                    .help(L10n.string("app_settings.language_relaunch_notice"))
                    .id("language-\(appSettingsStore.settings.language.id)")
                }
                UtilityFormRow(title: L10n.string("app_settings.appearance")) {
                    Picker("", selection: $editor.draft.appearance) {
                        ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 220, alignment: .leading).accessibilityLabel(L10n.string("app_settings.appearance"))
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Toggle(L10n.string("app_settings.automatic_updates"), isOn: $automaticUpdates)
                Toggle(L10n.string("utility.settings.time_machine"), isOn: $editor.draft.timeMachineWarningsEnabled)
                    .help(L10n.string("app_settings.time_machine_warnings"))
                Toggle(L10n.string("utility.settings.usage"), isOn: $editor.draft.telemetryEnabled)
                    .help(L10n.string("app_settings.telemetry_deploy_notice"))
            }
            .padding(.leading, 172)
        }
    }

    private var advanced: some View {
        UtilityPane {
            DashboardDisclosureSection(title: L10n.string("app_settings.section.defaults")) {
                DeviceAdvancedSettingsFields(
                    rsyncEnabled: $editor.draft.rsyncEnabled,
                    internalShareUseDiskRoot: $editor.draft.internalShareUseDiskRoot,
                    smbBrowseCompatibility: $editor.draft.smbBrowseCompatibility,
                    mdnsAdvertiseAFP: $editor.draft.mdnsAdvertiseAFP,
                    anyProtocol: $editor.draft.anyProtocol,
                    requireSMBSigning: $editor.draft.requireSMBSigning,
                    requireSMBEncryption: $editor.draft.requireSMBEncryption,
                    disableSMBEncryption: $editor.draft.disableSMBEncryption,
                    fruitMetadataNetatalk: $editor.draft.fruitMetadataNetatalk,
                    vfsAIOForkEnabled: $editor.draft.vfsAIOForkEnabled,
                    debugLogging: $editor.draft.debugLogging,
                    mountWaitSeconds: $editor.draft.mountWaitSeconds,
                    ataIdleSeconds: $editor.draft.ataIdleSeconds,
                    ataStandby: $editor.draft.ataStandby
                )
            }
            UtilityFormRow(title: L10n.string("app_settings.default_bonjour_timeout")) {
                TextField("", text: $editor.draft.defaultBonjourTimeoutSeconds).frame(width: 100)
            }
            UtilityFormRow(title: L10n.string("app_settings.helper_path")) {
                TextField(L10n.string("value.auto"), text: $editor.draft.helperPathOverride)
            }
            Toggle(L10n.string("app_settings.show_raw_events"), isOn: $editor.draft.showRawBackendEventsByDefault)
            Button(L10n.string("app_settings.restore_defaults")) { editor.restoreDefaultsDraft() }.disabled(editor.isSaving)
        }
    }
}
