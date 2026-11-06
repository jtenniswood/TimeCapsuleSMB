import SwiftUI
import XCTest
@testable import TimeCapsuleSMBApp

@MainActor
final class NavigationRefreshTests: XCTestCase {
    func testSetupWaitsForATargetThenPreservesThePasswordWhenGoingBack() async throws {
        let fixture = try await AppViewFixture()
        let flow = fixture.composition.addDeviceStore
        flow.startManualEntry()
        flow.manualHost = "   "
        flow.continueToPassword()
        XCTAssertFalse(flow.showsPasswordStep)

        flow.manualHost = "192.0.2.24"
        flow.continueToPassword()
        XCTAssertTrue(flow.showsPasswordStep)
        XCTAssertFalse(flow.canConfigure)
        flow.password = "fixture password"
        XCTAssertTrue(flow.canConfigure)
        flow.returnToDeviceSelection()
        XCTAssertFalse(flow.showsPasswordStep)
        XCTAssertEqual(flow.password, "fixture password")
        XCTAssertEqual(flow.manualHost, "192.0.2.24")
        flow.continueToPassword()
        XCTAssertTrue(flow.showsPasswordStep)
        flow.reset()
        XCTAssertFalse(flow.showsPasswordStep)
        XCTAssertEqual(flow.password, "")
    }

    func testUnsupportedAirPortCannotAdvanceToThePassword() async throws {
        let fixture = try await AppViewFixture(responses: [testDiscoverResponse(devices: [testExpressDevice()])], discoveryWaitsForReadiness: false)
        let flow = fixture.composition.addDeviceStore
        flow.runDiscover()
        try await waitUntilStoreState { flow.state == .discoveryReady }
        flow.select(try XCTUnwrap(flow.devices.first))
        flow.continueToPassword()
        XCTAssertFalse(flow.canContinueToPassword)
        XCTAssertFalse(flow.showsPasswordStep)
    }

    func testPasswordRecoveryReturnsToThePasswordStep() async throws {
        let fixture = try await AppViewFixture()
        let flow = fixture.composition.addDeviceStore
        flow.startManualEntry()
        flow.manualHost = "192.0.2.24"
        let recover = try XCTUnwrap(flow.recoveryAction(.replacePassword))
        recover()
        XCTAssertTrue(flow.showsPasswordStep)
        XCTAssertEqual(flow.state, .passwordEntry)
    }

    func testSetupShowsOneStepAtATimeAndTheButtonsAdvanceAndGoBack() async throws {
        let fixture = try await AppViewFixture()
        let flow = fixture.composition.addDeviceStore
        flow.startManualEntry()
        let host = LiveHostedView(AddDeviceView(store: flow), size: CGSize(width: 760, height: 580))
        defer { host.close() }
        func buttons() -> [AccessibleElement] { accessibleElements(in: host.contentView).filter { $0.role == .button } }
        XCTAssertEqual(buttons().first { $0.text == L10n.string("simple.continue") }?.isEnabled, false)
        XCTAssertFalse(buttons().contains { $0.text == L10n.string("simple.connect") })
        flow.manualHost = "192.0.2.24"
        await runQueuedStoreUpdates()
        XCTAssertTrue(pressAccessibleControl(in: host.contentView, labeled: L10n.string("simple.continue")))
        await runQueuedStoreUpdates()
        XCTAssertTrue(flow.showsPasswordStep)
        XCTAssertEqual(buttons().first { $0.text == L10n.string("simple.connect") }?.isEnabled, false)
        flow.password = "fixture password"
        await runQueuedStoreUpdates()
        XCTAssertEqual(buttons().first { $0.text == L10n.string("simple.connect") }?.isEnabled, true)
        XCTAssertTrue(pressAccessibleControl(in: host.contentView, labeled: L10n.string("simple.back")))
        await runQueuedStoreUpdates()
        XCTAssertFalse(flow.showsPasswordStep)
        XCTAssertEqual(flow.password, "fixture password")
    }

    func testCancelLeavesSetupAndClearsThePassword() async throws {
        let fixture = try await AppViewFixture()
        let flow = fixture.composition.addDeviceStore
        flow.startManualEntry()
        flow.manualHost = "192.0.2.24"
        flow.password = "fixture password"
        flow.continueToPassword()
        var cancelled = false
        let host = LiveHostedView(AddDeviceView(store: flow, onCancel: { cancelled = true }))
        defer { host.close() }
        XCTAssertTrue(pressAccessibleControl(in: host.contentView, labeled: L10n.string("action.cancel")))
        XCTAssertTrue(cancelled)
        XCTAssertFalse(flow.showsPasswordStep)
        XCTAssertEqual(flow.password, "")
    }

    func testRecoveryLinksExpandTheRequestedUtility() async throws {
        let fixture = try await AppViewFixture()
        let profile = try await fixture.saveProfile(id: "device", payloadFamily: "netbsd4_samba4")
        let session = fixture.dashboardSession(for: profile)
        XCTAssertFalse(session.maintenanceUtilitiesExpanded)
        session.performInstallAction(.openBootHook, profile: profile, showDiagnostics: {})
        XCTAssertEqual(session.selectedTab, .maintenance)
        XCTAssertEqual(session.maintenanceStore.selectedWorkflow, .bootHook)
        XCTAssertTrue(session.maintenanceUtilitiesExpanded)
        session.maintenanceUtilitiesExpanded = false
        session.performCheckupAction(.startSMB, profile: profile, showDiagnostics: {})
        XCTAssertEqual(session.maintenanceStore.selectedWorkflow, .activate)
        XCTAssertTrue(session.maintenanceUtilitiesExpanded)
    }

    func testCheckupKeepsProblemsVisibleAndRetainsAllChecksForDetails() throws {
        let checks = [
            testDoctorCheck(status: "PASS", message: "Working", domain: "device"),
            testDoctorCheck(status: "INFO", message: "Information", domain: "device"),
            testDoctorCheck(status: "WARN", message: "Needs attention", domain: "device"),
            testDoctorCheck(status: "FAIL", message: "Needs repair", domain: "device")
        ]
        let summary = DoctorSummary(payload: try testDoctorPayload(checks: checks).decode(DoctorPayload.self))
        let domain = try XCTUnwrap(CheckupPresentation(summary: summary, state: .failed).domains.first)
        XCTAssertEqual(domain.attentionRows.map(\.message), ["Needs attention", "Needs repair"])
        XCTAssertEqual(domain.rows.count, 4)
    }

    func testDiskWarningAndDetailedReadingsAreVisibleImmediately() throws {
        let disk = DiskHealthDisk(device: "wd0", label: "Disk 1", builtin: true, smartStatus: "failing", partitions: [],
                                  details: DiskSmartDetails(state: "available", attributes: []))
        let texts = accessibleElements(DiskHealthView(report: DiskHealthReport(error: nil, disks: [disk]), checkedAt: nil)).map(\.text)
        XCTAssertTrue(texts.contains(L10n.string("utility.disk.failure_advice")))
        XCTAssertTrue(texts.contains(L10n.string("disk_health.attributes")))
        XCTAssertTrue(texts.contains(L10n.string("disk_health.power_on_hours")))
    }

    func testHomeAndDeviceEditorHaveClearReturnNavigationAtMinimumSize() async throws {
        let fixture = try await AppViewFixture()
        let profile = try await fixture.saveProfile(id: "device")
        let host = LiveHostedView(fixture.contentView, size: CGSize(width: 760, height: 580))
        defer { host.close() }
        XCTAssertEqual(fixture.appStore.route, .allDevices)
        fixture.appStore.select(profile)
        await runQueuedStoreUpdates()
        XCTAssertTrue(pressAccessibleControl(in: host.contentView, labeled: L10n.string("action.done")))
        XCTAssertEqual(fixture.appStore.route, .allDevices)
    }
}
