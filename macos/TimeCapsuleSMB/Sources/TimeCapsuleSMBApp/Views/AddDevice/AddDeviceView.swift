import SwiftUI

struct AddDeviceView: View {
    @ObservedObject var store: AddDeviceFlowStore
    var onCancel: () -> Void = {}
    @FocusState private var passwordFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 24) {
                        Spacer(minLength: 24)
                        AirPortDeviceIcon().frame(width: 64, height: 84)
                        VStack(spacing: 8) {
                            Text(L10n.string(store.showsPasswordStep ? "utility.setup.password_title" : "simple.setup.choose_title"))
                                .font(UtilityStyle.title)
                            if store.showsPasswordStep {
                                Text(store.selectedDevice?.displayName ?? store.hostFieldText).foregroundStyle(.secondary)
                            }
                        }
                        if store.isAdding {
                            VStack(spacing: 16) {
                                ProgressView().controlSize(.small)
                                Text(L10n.string("utility.progress.connecting"))
                            }
                            .frame(height: 130)
                        } else if store.showsPasswordStep {
                            passwordStep
                        } else {
                            chooseStep
                        }
                        if let error = store.error {
                            ErrorRecoveryView(error: error, omittedActions: [.retry, .replacePassword]) { store.recoveryAction($0) }
                        }
                        if let warning = store.discovery.warning {
                            Text(warning).font(UtilityStyle.secondary).foregroundStyle(.orange)
                        }
                        Spacer(minLength: 24)
                    }
                    .frame(maxWidth: 440, minHeight: geometry.size.height)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                }
            }
            UtilityFooter {
                Button(L10n.string("action.cancel")) {
                    if store.isAdding { store.cancel() } else { store.reset(); onCancel() }
                }
                .keyboardShortcut(.cancelAction).disabled(store.isAdding && !store.canCancel)
                Spacer()
                if store.showsPasswordStep {
                    Button(L10n.string("simple.back")) { store.returnToDeviceSelection() }.disabled(store.isAdding)
                }
                Button(L10n.string(store.showsPasswordStep ? "simple.connect" : "simple.continue")) {
                    if store.showsPasswordStep { store.runConfigure() } else { store.continueToPassword() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(store.showsPasswordStep ? !store.canConfigure : !store.canContinueToPassword)
            }
        }
        .font(UtilityStyle.body)
        .onAppear { passwordFocused = store.showsPasswordStep }
        .onChange(of: store.showsPasswordStep) { _, showsPassword in passwordFocused = showsPassword }
    }

    private var chooseStep: some View {
        VStack(spacing: 16) {
            Picker(L10n.string("add_device.connection_method"), selection: Binding(get: { store.entryMode }, set: { store.setEntryMode($0) })) {
                Text(L10n.string("simple.nearby")).tag(AddDeviceEntryMode.discover)
                Text(L10n.string("simple.address")).tag(AddDeviceEntryMode.manual)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 240)
            if store.entryMode == .manual {
                TextField(L10n.string("simple.address"), text: $store.manualHost)
                    .textFieldStyle(.roundedBorder).frame(width: UtilityStyle.fieldWidth)
                    .accessibilityLabel(L10n.string("simple.address"))
                    .padding(.vertical, 36)
            } else if store.devices.isEmpty {
                VStack(spacing: 12) {
                    if store.discovery.state == .discovering { ProgressView().controlSize(.small) }
                    Text(L10n.string(store.isRunning ? "overview.discovery.discovering" : "overview.discovery.empty"))
                        .foregroundStyle(.secondary)
                    Button(L10n.string("overview.discovery.refresh")) { store.runDiscover() }.disabled(store.isRunning)
                }
                .frame(height: 130)
            } else {
                List(selection: Binding(get: { store.selectedDeviceID }, set: { id in
                    if let device = store.devices.first(where: { $0.id == id }), !device.isUnsupportedModel { store.select(device) }
                })) {
                    ForEach(store.devices) { device in
                        HStack(spacing: 12) {
                            AirPortDeviceIcon(isTower: device.syap == "119" || device.syap == "120").frame(width: 28, height: 36)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.displayName)
                                Text(device.isUnsupportedModel ? L10n.string("add_device.state.unsupported") : device.host)
                                    .font(UtilityStyle.secondary).foregroundStyle(.secondary)
                            }
                        }
                        .tag(device.id).disabled(device.isUnsupportedModel)
                    }
                }
                .listStyle(.bordered).frame(height: 160)
            }
        }
    }

    private var passwordStep: some View {
        VStack(spacing: 12) {
            RevealablePasswordField(L10n.string("simple.setup.password"), text: $store.password) {
                if store.canConfigure { store.runConfigure() }
            }
            .focused($passwordFocused).frame(width: UtilityStyle.fieldWidth)
            .help(L10n.string("simple.setup.password_message"))
            Text(L10n.string("utility.setup.saved"))
                .font(UtilityStyle.secondary).foregroundStyle(.secondary)
            if let message = store.reconnectMessage { Text(message).foregroundStyle(.secondary) }
            if let profile = store.suggestedProfile {
                Button(L10n.format("discovery.reconnect_existing", profile.title)) { store.reconnectSuggestedProfile() }
            }
        }
    }
}
