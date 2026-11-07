import SwiftUI

struct SSHSupportView: View {
    let profile: DeviceProfile
    @ObservedObject var status: DeviceSSHAccessStore
    @ObservedObject var operation: SSHAccessMaintenanceStore
    @ObservedObject var coordinator: OperationCoordinator
    let enable: () -> Void

    var body: some View {
        let payload = status.snapshot(for: profile)?.payload
        let enabled = payload.map { $0.sshFinalReachable ?? $0.sshPortReachable } == true
        let enabling = operation.isBusy || operation.isPreparing
        let checking = coordinator.activeOperation(for: .deviceWorkflow(profile.id, .sshStatus)) != nil
        GroupBox(L10n.string("ssh_support.title")) {
            HStack(spacing: 12) {
                if enabling || checking {
                    ProgressView().controlSize(.small)
                    Text(L10n.string(enabling ? "ssh_support.enabling" : "ssh_support.checking"))
                } else {
                    Label(L10n.string(enabled ? "ssh_support.enabled" :
                        payload == nil ? "value.unknown" : "ssh_support.disabled"),
                          systemImage: enabled ? "checkmark.circle" : "terminal")
                }
                Spacer()
                if !enabled && !enabling {
                    Button(L10n.string("ssh_access_notice.enable_action"), action: enable)
                        .disabled(checking || coordinator.isDeviceBusy(profile))
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Keep authentication and progress in the SSH sheet, without reopening the
/// removed device-settings page when a saved password is missing or rejected.
struct SSHAccessToolView: View {
    let profile: DeviceProfile
    let session: DeviceDashboardSession
    @ObservedObject var status: DeviceSSHAccessStore
    @ObservedObject var operation: SSHAccessMaintenanceStore
    @ObservedObject var editor: DeviceProfileEditorStore
    @State private var savingPassword = false
    @State private var passwordEntryRequired = false

    var body: some View {
        let payload = operation.payload ?? status.snapshot(for: profile)?.payload
        let enabled = payload.map { $0.sshFinalReachable ?? $0.sshPortReachable } == true
        let busy = operation.isBusy || operation.isPreparing || savingPassword
        let needsPassword = passwordEntryRequired || editor.passwordError != nil || operation.error?.code == "auth_failed"
        VStack(alignment: .leading, spacing: 16) {
            if busy {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(L10n.string(operation.state == .loading ? "ssh_support.checking" : "ssh_support.enabling"))
                }
            } else {
                Label(L10n.string(enabled ? "ssh_support.enabled" : "ssh_support.disabled"),
                      systemImage: enabled ? "checkmark.circle" : "terminal")
                if !enabled {
                    if needsPassword {
                        UtilityFormRow(title: L10n.string("simple.setup.password")) {
                            SecureField("", text: $editor.replacementPassword)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel(L10n.string("simple.setup.password"))
                                .onSubmit { if editor.canSave { savingPassword = true } }
                        }
                    }
                    Button(L10n.string("ssh_access_notice.enable_action")) {
                        if needsPassword {
                            savingPassword = true
                        } else {
                            session.enableSSHAccess(profile: profile)
                        }
                    }
                    .disabled(needsPassword && !editor.canSave)
                }
            }
            if let error = operation.error, !["cancelled", "confirmation_cancelled"].contains(error.code) {
                Text(error.message).foregroundStyle(.red)
            }
            if let error = editor.error { Text(error.message).foregroundStyle(.red) }
            ForEach(editor.validationErrors, id: \.self) { error in
                Text(error.localizedDescription).foregroundStyle(.red)
            }
        }
        .task(id: savingPassword) {
            guard savingPassword else { return }
            await editor.save(profile: profile)
            for await state in editor.$state.values {
                guard !Task.isCancelled else { return }
                switch state {
                case .saving, .reconfiguring: continue
                case .saved:
                    savingPassword = false
                    passwordEntryRequired = false
                    session.enableSSHAccess(profile: profile)
                    return
                default:
                    savingPassword = false
                    return
                }
            }
        }
        .onAppear {
            passwordEntryRequired = editor.passwordError != nil || operation.error?.code == "auth_failed"
        }
        .onChange(of: editor.passwordError) { _, error in
            if error != nil { passwordEntryRequired = true }
        }
        .onChange(of: operation.error?.code) { _, code in
            if code == "auth_failed" { passwordEntryRequired = true }
        }
        .onDisappear { editor.replacementPassword = "" }
    }
}
