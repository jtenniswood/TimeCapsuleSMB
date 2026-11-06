import XCTest
@testable import TimeCapsuleSMBApp

@MainActor
final class DiskSharingStoreTests: XCTestCase {
    private func makeProfile() throws -> DeviceProfile {
        DeviceProfile.make(id: "sharing-test-device", configuredDevice: try testConfiguredDevice(), discoveredDevice: nil,
            applicationSupportURL: URL(fileURLWithPath: "/tmp/timecapsulesmb-sharing-tests", isDirectory: true))
    }

    private func payload(enabled: Bool = true) -> JSONValue {
        .object(["schema_version": .number(1), "enabled": .bool(enabled), "security": .string("accounts"),
            "accounts": .array([.object(["name": .string("Alex"), "access": .number(0)])]),
            "revision": .string("revision"), "supported": .bool(true), "partitions": .array([])])
    }

    private func loadedStore(responses: [StoreTestRunner.Response] = []) async throws -> (DiskSharingStore, DeviceProfile, StoreTestRunner) {
        let runner = StoreTestRunner(responses: [.init(events: [BackendEvent(type: "result", operation: "disk-sharing", ok: true, payload: payload())])] + responses)
        let coordinator = OperationCoordinator(backend: BackendClient(runner: runner))
        let profile = try makeProfile()
        let store = DiskSharingStore(coordinator: coordinator, profileID: profile.id)
        store.load(profile: profile, password: "admin")
        try await waitUntilStoreState { store.snapshot != nil && !store.loading }
        return (store, profile, runner)
    }

    func testAccountAndDiskPasswordEditsStayStagedAndCancelClearsThem() async throws {
        let (store, _, runner) = try await loadedStore()
        XCTAssertFalse(store.hasChanges)
        XCTAssertEqual(store.accounts[0].password, "")
        store.accounts[0].password = "new-account-password"
        store.diskPassword = "new-disk-password"
        store.diskPasswordVerification = store.diskPassword
        XCTAssertTrue(store.hasChanges)
        XCTAssertEqual(runner.calls.count, 1)
        store.reset()
        XCTAssertFalse(store.hasChanges)
        XCTAssertTrue(store.diskPassword.isEmpty && store.accounts[0].password.isEmpty)
    }

    func testInvalidAccountsAndMismatchedDiskPasswordsCannotBeApplied() async throws {
        let (store, _, _) = try await loadedStore()
        store.enabled = false
        XCTAssertTrue(store.canSave)
        var duplicate = SharingAccountDraft()
        duplicate.name = "alex"
        duplicate.password = "new"
        store.accounts.append(duplicate)
        XCTAssertFalse(store.canSave)
        store.accounts.removeLast()
        store.security = "disk_password"
        XCTAssertFalse(store.canSave)
        store.diskPassword = "new"
        XCTAssertFalse(store.canSave)
        store.diskPasswordVerification = "new"
        XCTAssertTrue(store.canSave)
    }

    func testApplyPutsPasswordsOnlyInTheCredentialEnvelopeThenClearsDraft() async throws {
        let (store, profile, runner) = try await loadedStore(responses: [
            .init(events: [BackendEvent(type: "result", operation: "disk-sharing", ok: true, payload: payload(enabled: false))])
        ])
        store.enabled = false
        store.accounts[0].password = "private-new-password"
        let saved = await store.save(profile: profile, password: "private-admin")
        XCTAssertTrue(saved)
        let params = try XCTUnwrap(runner.calls.last?.params)
        XCTAssertEqual(params["credentials"], .object(["password": .string("private-admin"),
            "account_passwords": .object(["Alex": .string("private-new-password")])]))
        XCTAssertEqual(params["changes"], .object(["enabled": .bool(false), "security": .string("accounts"),
            "accounts": .array([.object(["name": .string("Alex"), "access": .number(0), "source_name": .string("Alex")])]),
            "revision": .string("revision")]))
        XCTAssertFalse(store.hasChanges)
        XCTAssertTrue(store.accounts[0].password.isEmpty)
    }

    func testCompletingAnUpdateRefreshesTheSharingCapabilitiesWithoutWaitingForTheCache() async throws {
        let (store, profile, runner) = try await loadedStore(responses: [
            .init(events: [BackendEvent(type: "result", operation: "disk-sharing", ok: true, payload: payload())])
        ])
        store.load(profile: profile, password: "admin")
        XCTAssertEqual(runner.calls.count, 1)
        var updated = profile
        let now = Date()
        updated.lastDeployState = DeviceDeployStateSnapshot(operationID: nil, startedAt: now, updatedAt: now,
            finishedAt: now, status: .succeeded, stage: nil, payloadFamily: nil, rebootRequested: true,
            verified: true, summary: "Done", errorCode: nil, errorMessage: nil, recovery: nil)
        store.load(profile: updated, password: "admin")
        try await waitUntilStoreState { runner.calls.count == 2 && !store.loading }
        XCTAssertEqual(runner.calls.count, 2)
    }
}
