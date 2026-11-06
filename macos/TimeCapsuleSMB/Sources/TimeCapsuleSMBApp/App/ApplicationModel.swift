import Combine
import SwiftUI

/// The utility window, app menu and native Settings window share one session.
@MainActor
public final class ApplicationModel {
    let composition: AppViewComposition
    let presentation = ApplicationPresentationStore()
    public let updater: AppUpdater

    public init(updater: AppUpdater? = nil) {
        self.updater = updater ?? AppUpdater()
        composition = .production()
    }

    init(composition: AppViewComposition, updater: AppUpdater? = nil) {
        self.composition = composition
        self.updater = updater ?? AppUpdater()
    }
}

@MainActor
final class ApplicationPresentationStore: ObservableObject {
    @Published var diagnosticsPresented = false
    @Published var profilePendingDeletion: DeviceProfile?
}

public struct ApplicationCommands: Commands {
    @ObservedObject private var appStore: AppStore
    @ObservedObject private var presentation: ApplicationPresentationStore
    @Environment(\.openWindow) private var openWindow

    public init(application: ApplicationModel) {
        appStore = application.composition.appStore
        presentation = application.presentation
    }

    public var body: some Commands {
        CommandMenu("AirPort") {
            Button(L10n.string("toolbar.forget")) {
                openWindow(id: "main")
                presentation.profilePendingDeletion = appStore.selectedProfile
            }
            .disabled(appStore.selectedProfile.map { appStore.operationCoordinator.isDeviceBusy($0) } ?? true)
        }
        CommandGroup(after: .windowArrangement) {
            Button(L10n.string("sidebar.activity")) { openWindow(id: "main"); appStore.navigate(to: .activity) }
        }
        CommandGroup(replacing: .help) {
            Button(L10n.string("utility.support")) { openWindow(id: "main"); presentation.diagnosticsPresented = true }
        }
    }
}

public struct AppSettingsWindow: View {
    private let application: ApplicationModel
    @ObservedObject private var settingsStore: AppSettingsStore

    public init(application: ApplicationModel) {
        self.application = application
        settingsStore = application.composition.appStore.appSettingsStore
    }

    public var body: some View {
        let composition = application.composition
        AppSettingsView(appStore: composition.appStore, appSettingsStore: settingsStore,
                        editor: composition.appSettingsEditorStore, updater: application.updater)
            .font(UtilityStyle.body)
            .controlSize(.regular)
            .frame(width: 620, height: 460)
            .preferredColorScheme(settingsStore.settings.appearance == .system ? nil : settingsStore.settings.appearance.preferredColorScheme(systemColorScheme: .light))
    }
}
