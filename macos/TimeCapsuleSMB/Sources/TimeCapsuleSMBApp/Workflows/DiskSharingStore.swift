import Combine
import Foundation

struct DiskSharingPayload: Decodable, Equatable {
    let schemaVersion: Int
    let enabled: Bool
    let security: String
    let accounts: [DiskSharingAccount]
    let revision: String
    let supported: Bool
    let partitions: [SharingPartition]
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case enabled, security, accounts, revision, supported, partitions
    }
}

struct SharingPartition: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let builtin: Bool
    let sizeMiB: Int64?
    let freeMiB: Int64?
    enum CodingKeys: String, CodingKey {
        case id, name, builtin
        case sizeMiB = "size_mib"
        case freeMiB = "free_mib"
    }
}

struct DiskSharingAccount: Decodable, Equatable {
    let name: String
    let access: Int
}

struct SharingAccountDraft: Identifiable, Equatable {
    let id: UUID
    let sourceName: String?
    var name: String
    var access: Int
    var password = ""

    init(account: DiskSharingAccount? = nil) {
        id = UUID()
        sourceName = account?.name
        name = account?.name ?? ""
        access = account?.access ?? 0
    }

    var request: JSONValue {
        var record: [String: JSONValue] = ["name": .string(name), "access": .number(Double(access))]
        if let sourceName { record["source_name"] = .string(sourceName) }
        return .object(record)
    }

    var isValid: Bool {
        !name.isEmpty && name.utf8.count <= 255 && (0...2).contains(access)
            && !name.contains { $0.isNewline || $0.asciiValue.map { $0 < 32 || $0 == 127 } == true || ":/\\".contains($0) }
            && (sourceName != nil || !password.isEmpty)
            && password.utf8.count <= 4096 && !password.contains("\0")
    }
}

@MainActor
final class DiskSharingStore: ObservableObject {
    @Published private(set) var snapshot: DiskSharingPayload?
    @Published var enabled = false
    @Published var security = "accounts"
    @Published var accounts: [SharingAccountDraft] = []
    @Published var diskPassword = ""
    @Published var diskPasswordVerification = ""
    @Published private(set) var error: BackendErrorViewModel?
    @Published private(set) var loading = false
    @Published private(set) var saving = false

    private let coordinator: OperationCoordinator
    private let profileID: DeviceProfile.ID
    private var cancellables: Set<AnyCancellable> = []
    private var lastRead: Date?
    private var readStartedAt: Date?
    private var saved = false

    init(coordinator: OperationCoordinator, profileID: DeviceProfile.ID) {
        self.coordinator = coordinator
        self.profileID = profileID
        for workflow in [DeviceWorkflowLane.diskSharing, .diskSharingStatus] {
            let backend = coordinator.lane(for: .deviceWorkflow(profileID, workflow)).backend
            backend.didUpdateEvents.sink { [weak self] events in
                guard let event = events.last(where: { $0.operation == "disk-sharing" && ($0.type == "result" || $0.type == "error") }) else { return }
                self?.receive(event, applying: workflow == .diskSharing)
            }.store(in: &cancellables)
            backend.$isRunning.sink { [weak self] running in
                Task { @MainActor in
                    guard let self else { return }
                    if workflow == .diskSharing { self.saving = running || backend.pendingConfirmation != nil }
                    else { self.loading = running }
                }
            }.store(in: &cancellables)
        }
    }

    var hasChanges: Bool {
        guard let snapshot else { return false }
        return enabled != snapshot.enabled || security != snapshot.security || !diskPassword.isEmpty
            || accounts.map { DiskSharingAccount(name: $0.name, access: $0.access) } != snapshot.accounts
            || accounts.contains { !$0.password.isEmpty || $0.sourceName == nil || $0.name != $0.sourceName }
    }

    var canSave: Bool {
        guard let snapshot, snapshot.supported, hasChanges, !saving, !loading else { return false }
        guard accounts.count <= 128, accounts.allSatisfy(\.isValid) else { return false }
        for (index, account) in accounts.enumerated() {
            if accounts.prefix(index).contains(where: { $0.name.caseInsensitiveCompare(account.name) == .orderedSame }) { return false }
        }
        if enabled && security == "accounts" && !accounts.contains(where: { $0.access < 2 }) { return false }
        if security == "disk_password" && snapshot.security != "disk_password" && diskPassword.isEmpty { return false }
        if !diskPassword.isEmpty && (diskPassword != diskPasswordVerification || diskPassword.contains("\0") || diskPassword.utf8.count > 4096) { return false }
        return true
    }

    func reset() {
        diskPassword = ""
        diskPasswordVerification = ""
        error = nil
        guard let snapshot else { return }
        enabled = snapshot.enabled
        security = snapshot.security
        accounts = snapshot.accounts.map { SharingAccountDraft(account: $0) }
    }

    func load(profile: DeviceProfile, password: String?, force: Bool = false) {
        let refreshAfterUpdate = (profile.lastDeployState?.finishedAt ?? profile.lastDeployState?.startedAt)
            .map { completed in lastRead.map { $0 < completed } ?? true } ?? false
        guard !hasChanges, !loading, !saving, let password,
              !coordinator.isDeviceBusy(profileID), !coordinator.isRunningBackgroundCheck(profileID),
              force || refreshAfterUpdate || (lastRead.map({ Date().timeIntervalSince($0) >= 60 }) ?? true) else { return }
        let lane = coordinator.lane(for: .deviceWorkflow(profileID, .diskSharingStatus))
        lane.clear()
        error = nil
        if case .started = coordinator.run(operation: "disk-sharing", params: ["action": .string("read")],
            context: profile.runtimeContext, activeDeviceID: profileID, password: password, laneKey: lane.key) {
            readStartedAt = Date()
            loading = true
        }
    }

    func save(profile: DeviceProfile, password: String) async -> Bool {
        guard canSave, let snapshot else { return false }
        let lane = coordinator.lane(for: .deviceWorkflow(profileID, .diskSharing))
        let passwords = Dictionary(uniqueKeysWithValues: accounts.filter { !$0.password.isEmpty }.map { ($0.name, JSONValue.string($0.password)) })
        var credentials: [String: JSONValue] = ["password": .string(password), "account_passwords": .object(passwords)]
        if !diskPassword.isEmpty { credentials["disk_password"] = .string(diskPassword) }
        let changes: [String: JSONValue] = ["enabled": .bool(enabled), "security": .string(security),
            "accounts": .array(accounts.map(\.request)), "revision": .string(snapshot.revision)]
        lane.clear()
        saved = false
        error = nil
        let result = coordinator.run(operation: "disk-sharing", params: ["action": .string("apply"),
            "changes": .object(changes), "credentials": .object(credentials)], context: profile.runtimeContext,
            activeDeviceID: profileID, laneKey: lane.key)
        guard case .started = result else { return false }
        saving = true
        for await (running, confirmation) in Publishers.CombineLatest(lane.backend.$isRunning, lane.backend.$pendingConfirmation).values {
            if !running && confirmation == nil { break }
        }
        saving = false
        return saved
    }

    private func receive(_ event: BackendEvent, applying: Bool) {
        if event.type == "error" {
            // Confirmations are handled by the app's existing confirmation sheet.
            if event.code != "confirmation_required" {
                error = applying ? BackendErrorViewModel(event: event) : BackendErrorViewModel(
                    operation: "disk-sharing", code: event.code ?? "operation_failed", message: L10n.string("sharing.read_error"))
            }
            return
        }
        do {
            let payload = try event.decodePayload(DiskSharingPayload.self)
            guard applying || !hasChanges else { return }
            snapshot = payload
            lastRead = applying ? Date() : readStartedAt ?? Date()
            reset()
            if applying { saved = true }
        } catch {
            self.error = BackendErrorViewModel(operation: "disk-sharing", code: "contract_error", message: L10n.string("sharing.read_error"))
        }
    }
}
