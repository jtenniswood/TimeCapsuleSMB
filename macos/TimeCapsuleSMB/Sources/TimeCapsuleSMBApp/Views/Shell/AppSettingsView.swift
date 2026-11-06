import SwiftUI

struct AppSettingsView: View {
    let appStore: AppStore
    @ObservedObject var appSettingsStore: AppSettingsStore
    @ObservedObject var editor: AppSettingsEditorStore
    @ObservedObject var updater: AppUpdater
    @Environment(\.dismiss) private var dismiss
    @State private var automaticUpdates = true

    var body: some View {
        VStack(spacing: 0) {
            GroupBox { general }
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
        .background(Color(nsColor: .windowBackgroundColor))
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

}
