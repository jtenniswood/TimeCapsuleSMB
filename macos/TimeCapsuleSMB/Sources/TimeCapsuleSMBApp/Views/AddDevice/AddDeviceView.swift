import SwiftUI

struct AddDeviceView: View {
    @ObservedObject var store: AddDeviceFlowStore
    var onCancel: () -> Void = {}
    @FocusState private var passwordFocused: Bool
    private var enteringPassword: Bool { store.showsPasswordStep }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollView {
                    assistantContent
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
            }
            Divider()
            HStack {
                Button(L10n.string("action.cancel")) {
                    if store.isRunning { store.cancel() } else { store.reset(); onCancel() }
                }
                .keyboardShortcut(.cancelAction)
                .disabled(store.isAdding && !store.canCancel)
                Spacer()
                if enteringPassword {
                    Button(L10n.string("simple.back")) {
                        store.returnToDeviceSelection()
                    }
                    .disabled(store.isAdding)
                }
                Button(L10n.string(enteringPassword ? "simple.connect" : "simple.continue")) {
                    if enteringPassword { store.runConfigure() } else { store.continueToPassword() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(enteringPassword ? !store.canConfigure : !store.canContinueToPassword)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { passwordFocused = enteringPassword }
        .onChange(of: store.showsPasswordStep) { _, showsPassword in
            passwordFocused = showsPassword
        }
    }

    private var assistantContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            VStack(spacing: 20) {
                AirPortDeviceIcon().frame(width: 54, height: 70)
                VStack(spacing: 8) {
                    Text(L10n.string(enteringPassword ? "simple.setup.connect_title" : "simple.setup.choose_title"))
                        .font(.title2.weight(.semibold))
                    Text(enteringPassword ? (store.selectedDevice?.displayName ?? store.hostFieldText) : L10n.string("simple.setup.choose_message"))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let progress = AddDeviceProgressPresentation(state: store.state, currentStage: store.currentStage) {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(progress.message).multilineTextAlignment(.center)
                        if let detail = progress.detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 24)
                    .frame(minHeight: 160)
                } else if enteringPassword {
                    passwordStep
                } else {
                    chooseStep
                }
                if let error = store.error {
                    ErrorRecoveryView(error: error) { store.recoveryAction($0) }
                }
                if let warning = store.discovery.warning {
                    Text(warning).font(.caption).foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: 500)
            .padding(.horizontal, 32)
            Spacer(minLength: 20)
        }
    }

    private var chooseStep: some View {
        VStack(spacing: 14) {
            Picker(L10n.string("add_device.connection_method"), selection: Binding(
                get: { store.entryMode }, set: { store.setEntryMode($0) }
            )) {
                Text(L10n.string("simple.nearby")).tag(AddDeviceEntryMode.discover)
                Text(L10n.string("simple.address")).tag(AddDeviceEntryMode.manual)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
            if store.entryMode == .manual {
                TextField(L10n.string("add_device.host_or_ip"), text: $store.manualHost)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 340)
                    .padding(.vertical, 30)
            } else {
                VStack(spacing: 0) {
                    if store.devices.isEmpty {
                        VStack(spacing: 10) {
                            if store.isRunning { ProgressView().controlSize(.small) }
                            Text(L10n.string(store.isRunning ? "overview.discovery.discovering" : "overview.discovery.empty"))
                                .foregroundStyle(.secondary)
                            Button(L10n.string("overview.discovery.refresh")) { store.runDiscover() }
                                .disabled(store.isRunning)
                        }
                        .frame(maxWidth: .infinity, minHeight: 130)
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(store.devices) { device in
                                    Button { store.select(device) } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "airport.extreme.tower").font(.title2)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(device.displayName).fontWeight(.medium)
                                                Text(device.isUnsupportedModel ? L10n.string("add_device.state.unsupported") : device.addressSummary)
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            if store.selectedDeviceID == device.id {
                                                Image(systemName: "checkmark").foregroundStyle(.tint)
                                            }
                                        }
                                        .padding(12)
                                        .contentShape(Rectangle())
                                        .background(store.selectedDeviceID == device.id ? Color.accentColor.opacity(0.10) : .clear)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(store.isAdding || device.isUnsupportedModel)
                                    Divider()
                                }
                            }
                        }
                        .frame(height: 170)
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
            }
        }
    }

    private var passwordStep: some View {
        VStack(spacing: 16) {
            Text(L10n.string("simple.setup.password_message"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            RevealablePasswordField(L10n.string("simple.setup.password"), text: $store.password) {
                if store.canConfigure { store.runConfigure() }
            }
            .focused($passwordFocused)
            .frame(maxWidth: 340)
            Text(L10n.string("simple.setup.keychain"))
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let message = store.reconnectMessage {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            if let profile = store.suggestedProfile {
                Button(L10n.format("discovery.reconnect_existing", profile.title)) { store.reconnectSuggestedProfile() }
            }
        }
        .padding(.vertical, 12)
    }
}
