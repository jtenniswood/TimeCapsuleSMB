import SwiftUI

struct DiskSharingSettingsView: View {
    @ObservedObject var store: DiskSharingStore
    let deviceBusy: Bool
    var isLegacyDevice = false
    var showPartitions = true
    let reload: () -> Void
    @State private var selectedAccountID: UUID?
    @State private var editingAccount: SharingAccountDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.loading && store.snapshot == nil {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            } else if let snapshot = store.snapshot {
                if showPartitions && !snapshot.partitions.isEmpty {
                    UtilityFormRow(title: L10n.string("sharing.partitions")) {
                        List(snapshot.partitions) { partition in
                            HStack(spacing: 12) {
                                if let artwork = DiskArtwork.image {
                                    Image(nsImage: artwork).resizable().scaledToFit().frame(width: 32, height: 32)
                                        .accessibilityHidden(true)
                                } else {
                                    Image(systemName: "externaldrive").font(.system(size: 24)).foregroundStyle(.secondary)
                                        .accessibilityHidden(true)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(partition.name).font(UtilityStyle.heading)
                                    if let free = DiskHealthPartition.bytes(partition.freeMiB) {
                                        Text(L10n.format("sharing.space_free", free)).font(UtilityStyle.secondary).foregroundStyle(.secondary)
                                    }
                                }
                            }.padding(.vertical, 6)
                        }.listStyle(.bordered)
                            .frame(height: min(160, CGFloat(snapshot.partitions.count) * 56 + 8))
                    }
                }
                VStack(alignment: .leading, spacing: 16) {
                    UtilityFormRow(title: "") {
                        Toggle(L10n.string("sharing.enable"), isOn: $store.enabled)
                    }
                    UtilityFormRow(title: L10n.string("sharing.secure_disks")) {
                        Picker("", selection: $store.security) {
                            Text(L10n.string("sharing.security.accounts")).tag("accounts")
                            Text(L10n.string("sharing.security.disk_password")).tag("disk_password")
                            Text(L10n.string("sharing.security.device_password")).tag("device_password")
                        }.labelsHidden().accessibilityLabel(L10n.string("sharing.secure_disks"))
                    }
                    if store.security == "accounts" {
                        UtilityFormRow(title: L10n.string("sharing.accounts")) {
                            VStack(spacing: 8) {
                                Table(store.accounts, selection: $selectedAccountID) {
                                    TableColumn(L10n.string("sharing.account_name"), value: \.name)
                                    TableColumn(L10n.string("sharing.access")) { account in
                                        Text(L10n.string("sharing.access.\(account.access)"))
                                    }
                                }.tableStyle(.bordered).frame(height: 108)
                                HStack(spacing: 0) {
                                    Button { editingAccount = SharingAccountDraft() } label: { Image(systemName: "plus").frame(width: 12, height: 12) }
                                        .help(L10n.string("sharing.add_account")).accessibilityLabel(L10n.string("sharing.add_account"))
                                        .disabled(store.accounts.count >= 128)
                                    Button {
                                        store.accounts.removeAll { $0.id == selectedAccountID }
                                        selectedAccountID = nil
                                    } label: { Image(systemName: "minus").frame(width: 12, height: 12) }
                                        .help(L10n.string("sharing.remove_account")).accessibilityLabel(L10n.string("sharing.remove_account"))
                                        .disabled(selectedAccount == nil)
                                    Spacer()
                                    Button(L10n.string("simple.edit")) { editingAccount = selectedAccount }
                                        .disabled(selectedAccount == nil)
                                }
                            }
                        }
                    } else if store.security == "disk_password" {
                        UtilityFormRow(title: L10n.string("sharing.disk_password")) {
                            SecureField(snapshot.security == "disk_password" ? L10n.string("settings.unchanged") : "", text: $store.diskPassword)
                                .accessibilityLabel(L10n.string("sharing.disk_password"))
                        }
                        UtilityFormRow(title: L10n.string("sharing.verify_password")) {
                            SecureField("", text: $store.diskPasswordVerification)
                                .accessibilityLabel(L10n.string("sharing.verify_password"))
                        }
                    }
                }.disabled(deviceBusy || store.saving || !snapshot.supported)
                if !snapshot.supported {
                    Text(L10n.string(isLegacyDevice ? "sharing.unavailable" : "sharing.update_required"))
                        .font(UtilityStyle.secondary).foregroundStyle(.secondary)
                }
            }
            if let error = store.error {
                Text(error.message).foregroundStyle(.red)
                Button(L10n.string("recovery.action.retry")) { store.reset(); reload() }
                    .disabled(deviceBusy || store.loading || store.saving)
            }
            if store.saving {
                HStack { ProgressView().controlSize(.small); Text(L10n.string("sharing.saving")) }
            }
        }
        .sheet(item: $editingAccount) { account in
            SharingAccountEditor(account: account, existingNames: store.accounts.filter { $0.id != account.id }.map(\.name)) { saved in
                if let index = store.accounts.firstIndex(where: { $0.id == saved.id }) { store.accounts[index] = saved }
                else { store.accounts.append(saved) }
                selectedAccountID = saved.id
                editingAccount = nil
            }
        }
    }

    private var selectedAccount: SharingAccountDraft? { store.accounts.first { $0.id == selectedAccountID } }
}

private struct SharingAccountEditor: View {
    @State var account: SharingAccountDraft
    let existingNames: [String]
    let save: (SharingAccountDraft) -> Void
    @State private var verifyPassword = ""
    @Environment(\.dismiss) private var dismiss

    private var valid: Bool {
        account.isValid
            && !existingNames.contains { $0.caseInsensitiveCompare(account.name) == .orderedSame }
            && account.password == verifyPassword
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.string(account.sourceName == nil ? "sharing.add_account" : "sharing.edit_account"))
                .font(UtilityStyle.title).padding(24)
            VStack(spacing: 16) {
                UtilityFormRow(title: L10n.string("sharing.account_name")) {
                    TextField("", text: $account.name).accessibilityLabel(L10n.string("sharing.account_name"))
                }
                UtilityFormRow(title: L10n.string("sharing.password")) {
                    SecureField(account.sourceName == nil ? "" : L10n.string("settings.unchanged"), text: $account.password)
                        .accessibilityLabel(L10n.string("sharing.password"))
                }
                UtilityFormRow(title: L10n.string("sharing.verify_password")) {
                    SecureField("", text: $verifyPassword).accessibilityLabel(L10n.string("sharing.verify_password"))
                }
                UtilityFormRow(title: L10n.string("sharing.access")) {
                    Picker("", selection: $account.access) {
                        ForEach(0..<3) { Text(L10n.string("sharing.access.\($0)")).tag($0) }
                    }.labelsHidden().accessibilityLabel(L10n.string("sharing.access"))
                }
            }.padding(.horizontal, 24)
            Spacer(minLength: 24)
            UtilityFooter {
                Spacer()
                Button(L10n.string("action.cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.string("utility.save")) { save(account); dismiss() }
                    .keyboardShortcut(.defaultAction).disabled(!valid)
            }
        }.font(UtilityStyle.body).frame(width: 580, height: 330)
    }
}
