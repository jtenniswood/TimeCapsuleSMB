import XCTest
@testable import TimeCapsuleSMBApp

@MainActor
final class DiskPanelRepairSelectionTests: XCTestCase {
    func testOpeningAnotherDiskClearsThePreviousRepairAndDoesNotSelectAnUnrelatedVolume() async throws {
        let result = testFsckListPayload(targets: [testFsckTargetPayload(name: "Data")])
        let runner = StoreTestRunner(responses: (0..<2).map { _ in
            .init(events: [BackendEvent(type: "result", operation: "fsck", ok: true, payload: result)])
        })
        let store = FsckStore(backend: BackendClient(runner: runner))
        let internalDisk = DiskHealthDisk(device: "wd0", label: "Internal", builtin: true, smartStatus: "verified",
            partitions: [.init(name: "Data", sizeMiB: nil, usedMiB: nil, freeMiB: nil)],
            details: .init(state: "unavailable", attributes: []))
        store.prepareForDisk(internalDisk)
        store.refreshTargets(mountWaitValue: 30, password: "fixture")
        try await waitUntilStoreState { store.state == .listReady && !store.isBusy }
        XCTAssertEqual(store.selectedTarget?.name, "Data")
        let externalDisk = DiskHealthDisk(device: "sd0", label: "USB", builtin: false, smartStatus: nil,
            partitions: [.init(name: "USB", sizeMiB: nil, usedMiB: nil, freeMiB: nil)],
            details: .init(state: "unavailable", attributes: []))
        store.prepareForDisk(externalDisk)
        XCTAssertNil(store.selectedTarget)
        store.refreshTargets(mountWaitValue: 30, password: "fixture")
        try await waitUntilStoreState { store.state == .listReady && !store.isBusy }
        XCTAssertNil(store.selectedTarget)
        XCTAssertFalse(store.canRun(options: nil))
    }
}
