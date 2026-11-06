import AppKit
import SwiftUI
import XCTest
@testable import TimeCapsuleSMBApp

@MainActor
final class NativeInterfaceTests: XCTestCase {
    func testEditingAnAddressPreservesTheSavedLogin() {
        var draft = DeviceProfileEditorDraft(displayName: "AirPort", host: "root@192.0.2.24", debugLogging: false, mountWaitSeconds: "30")
        XCTAssertEqual(draft.address, "192.0.2.24")
        draft.address = "192.0.2.25"
        XCTAssertEqual(draft.host, "root@192.0.2.25")
        draft.host = "admin@[2001:db8::24]"
        XCTAssertEqual(draft.address, "[2001:db8::24]")
        draft.address = "2001:db8::25"
        XCTAssertEqual(DeviceEndpointPolicy.rootSSHTarget(draft.host), "admin@2001:db8::25")
        draft.host = "admin@[2001:db8::24]:2222"
        XCTAssertEqual(draft.address, "[2001:db8::24]:2222")
        draft.address = "[2001:db8::25]:2222"
        XCTAssertEqual(draft.host, "admin@[2001:db8::25]:2222")
        draft.address = ""
        XCTAssertEqual(draft.host, "")
    }

    func testManualSetupAndCancelDoNotWaitForOrStopTheSharedSearch() async throws {
        let runner = PausingStoreTestRunner(responses: [.init(events: [], pauseBeforeEvents: true)])
        defer { runner.finishAll() }
        let fixture = try await AppViewFixture(runner: runner, discoveryWaitsForReadiness: false)
        let flow = fixture.composition.addDeviceStore
        flow.runDiscover()
        try await waitUntilStoreState { flow.discovery.state == .discovering && runner.calls.count == 1 }
        flow.startManualEntry()
        flow.manualHost = "192.0.2.24"
        XCTAssertTrue(flow.canContinueToPassword)
        flow.continueToPassword()
        XCTAssertTrue(flow.showsPasswordStep)
        flow.password = "fixture password"
        XCTAssertTrue(flow.canConfigure)
        var cancelled = false
        let host = LiveHostedView(AddDeviceView(store: flow, onCancel: { cancelled = true }))
        defer { host.close() }
        XCTAssertTrue(pressAccessibleControl(in: host.contentView, labeled: L10n.string("action.cancel")))
        XCTAssertTrue(cancelled)
        XCTAssertEqual(flow.password, "")
        XCTAssertEqual(flow.discovery.state, .discovering)
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testTheHomeCanvasHasNoDuplicatedAppSettingsControls() async throws {
        let fixture = try await AppViewFixture()
        let controls = accessibleElements(fixture.contentView).filter { $0.role == .button }
        XCTAssertFalse(controls.contains { $0.text == L10n.string("sidebar.settings") })
        XCTAssertFalse(controls.contains { $0.text == L10n.string("sidebar.activity") })
    }

    func testEveryDevicePaneCanBeSelectedAtTheMinimumWindowSize() async throws {
        let fixture = try await AppViewFixture()
        let profile = try await fixture.saveProfile(id: "native-tabs")
        let session = fixture.dashboardSession(for: profile)
        fixture.appStore.select(profile)
        let host = LiveHostedView(fixture.contentView, size: CGSize(width: 760, height: 580))
        defer { host.close() }
        for tab in DeviceDashboardTab.allCases where tab != session.selectedTab {
            // NSSegmentedControl can return false after dispatching its action.
            // The selected pane, rather than that return value, is the outcome.
            _ = pressAccessibleControl(in: host.contentView, labeled: tab.title)
            await runQueuedStoreUpdates()
            XCTAssertEqual(session.selectedTab, tab)
        }
    }

    func testProfileChangesHaveOneBottomActionRowAndCanBeDiscarded() async throws {
        let fixture = try await AppViewFixture()
        let profile = try await fixture.saveProfile(id: "profile")
        let session = fixture.dashboardSession(for: profile)
        session.selectedTab = .settings
        fixture.appStore.select(profile)
        let host = LiveHostedView(fixture.contentView)
        defer { host.close() }
        session.profileEditorStore.draft.displayName = "Changed name"
        await runQueuedStoreUpdates()
        let buttons = accessibleElements(in: host.contentView).filter { $0.role == .button }
        XCTAssertEqual(buttons.filter { $0.text == L10n.string("utility.update") }.count, 1)
        XCTAssertFalse(buttons.contains { $0.text == L10n.string("profile_editor.save") })
        XCTAssertTrue(pressAccessibleControl(in: host.contentView, labeled: L10n.string("action.cancel")))
        XCTAssertEqual(session.profileEditorStore.draft.displayName, profile.displayName)
        XCTAssertEqual(fixture.appStore.route, .allDevices)
    }

    func testFirmwareGuideRequiresBackupAndAMatchingPlanForEachWrite() async throws {
        for mode in [FlashPlanMode.patch, .restore] {
            let fixture = try BootHookTestFixture(responses: testBootHookResponses(plan: testBootHookPlanPayload(mode: mode)))
            XCTAssertEqual(MaintenanceGuidePolicy.primaryAction(presentation: fixture.presentation), .backUpAndInspectFirmware)
            XCTAssertFalse(fixture.presentation.isEnabled(.writePatch))
            XCTAssertFalse(fixture.presentation.isEnabled(.writeRestore))
            try await fixture.run(.backup)
            XCTAssertEqual(MaintenanceGuidePolicy.primaryAction(presentation: fixture.presentation), .planPatch)
            try await fixture.run(.plan(mode))
            XCTAssertEqual(MaintenanceGuidePolicy.primaryAction(presentation: fixture.presentation), mode == .patch ? .writePatch : .writeRestore)
        }
    }

    func testSupportExportHonorsTheDetailedLogsChoice() async throws {
        let fixture = try await AppViewFixture()
        for includeLogs in [false, true] {
            var requested: Bool?
            let view = AppDiagnosticsView(store: fixture.appStore.appReadinessStore, exportContext: { include in
                requested = include
                return fixture.appStore.diagnosticsExportContext(includeBackendEvents: include)
            }, showBackendEvents: .constant(includeLogs))
            _ = view.exportText()
            XCTAssertEqual(requested, includeLogs)
        }
    }

}
