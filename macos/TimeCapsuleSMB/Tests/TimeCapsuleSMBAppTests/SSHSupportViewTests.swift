import AppKit
import XCTest
@testable import TimeCapsuleSMBApp

@MainActor
final class SSHSupportViewTests: XCTestCase {
    func testEnabledConnectionHelpOpensOnHoverAndClickAtTheTrailingEdge() async throws {
        let fixture = try await AppViewFixture(runner: StoreTestRunner(responses: []))
        let profile = try await fixture.saveProfile(id: "ssh-help")
        let session = fixture.dashboardSession(for: profile)
        fixture.appStore.sshAccessStore.apply(payload: try testSSHAccessPayload(sshPortReachable: true)
            .decode(SSHAccessPayload.self), profile: profile)
        let host = LiveHostedView(SSHSupportView(profile: profile, status: fixture.appStore.sshAccessStore,
            operation: session.maintenanceStore.sshAccessStore, coordinator: fixture.appStore.operationCoordinator,
            enable: {}), size: CGSize(width: 560, height: 80))
        defer { host.close() }
        await runQueuedStoreUpdates()
        host.contentView.layoutSubtreeIfNeeded()

        func infoButton(in view: NSView) -> SSHConnectionInfoControl? {
            if let button = view as? SSHConnectionInfoControl { return button }
            return view.subviews.lazy.compactMap { infoButton(in: $0) }.first
        }
        let button = try XCTUnwrap(infoButton(in: host.contentView))
        defer { button.closeHelp() }
        let command = try XCTUnwrap(DeviceEndpointPolicy.terminalSSHCommand(profile.host))
        let help = L10n.format("support.ssh.connection_help", command)
        XCTAssertEqual(button.accessibilityHelp(), help)
        XCTAssertGreaterThanOrEqual(button.visibleRect.width, 24)
        XCTAssertGreaterThanOrEqual(button.visibleRect.height, 24)
        let rect = button.convert(button.bounds, to: host.contentView)
        XCTAssertEqual(rect.maxX, host.contentView.bounds.maxX, accuracy: 1)

        host.contentView.window?.makeKeyAndOrderFront(nil)
        func shownHelp() -> NSView? {
            NSApp.windows.filter(\.isVisible).compactMap(\.contentView).first {
                accessibleElements(in: $0).contains { $0.text.contains(command) }
            }
        }
        func hover(_ type: NSEvent.EventType, in view: NSView? = nil) throws {
            let view = view ?? button
            let event = try XCTUnwrap(NSEvent.enterExitEvent(with: type, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: view.window!.windowNumber,
                context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
            if type == .mouseEntered { view.mouseEntered(with: event) }
            else { view.mouseExited(with: event) }
        }
        try hover(.mouseEntered)
        await runQueuedStoreUpdates()
        XCTAssertNotNil(shownHelp(), "Hover must display the instructions, not just register tooltip text")
        try hover(.mouseExited)
        try await waitUntilStoreState { shownHelp() == nil }

        try hover(.mouseEntered)
        await runQueuedStoreUpdates()
        let instructions = try XCTUnwrap(shownHelp())
        try hover(.mouseExited)
        try hover(.mouseEntered, in: instructions)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNotNil(shownHelp(), "Moving into the instructions must keep them open")
        try hover(.mouseExited, in: instructions)
        try await waitUntilStoreState { shownHelp() == nil }

        XCTAssertTrue(pressAccessibleControl(in: host.contentView, labeled: L10n.string("support.ssh.connection_info")))
        await runQueuedStoreUpdates()
        XCTAssertNotNil(shownHelp(), "The info button must open the instructions")
        try hover(.mouseExited)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNotNil(shownHelp(), "Clicked instructions stay open so the command can be selected")
        button.performClick(nil)
        await runQueuedStoreUpdates()
        XCTAssertNil(shownHelp())
    }

    func testEnableTargetsTheSelectedDeviceAndWaitsForConfirmation() async throws {
        let runner = StoreTestRunner(responses: [
            .init(events: [testConfirmationRequired(operation: "set-ssh", id: "enable-ssh", presentationID: "ssh_access.enable_reboot")]),
            .init(events: [BackendEvent(type: "result", operation: "set-ssh", ok: true,
                payload: testSSHAccessPayload(sshPortReachable: true))])
        ])
        let fixture = try await AppViewFixture(runner: runner)
        let profile = try await fixture.saveProfile(id: "ssh-device")
        let session = fixture.dashboardSession(for: profile)
        let coordinator = fixture.appStore.operationCoordinator
        fixture.appStore.sshAccessStore.apply(payload: try testSSHAccessPayload().decode(SSHAccessPayload.self), profile: profile)
        let host = LiveHostedView(SSHSupportView(profile: profile, status: fixture.appStore.sshAccessStore,
            operation: session.maintenanceStore.sshAccessStore, coordinator: coordinator,
            enable: { session.enableSSHAccess(profile: profile) }))
        defer { host.close() }

        XCTAssertTrue(pressAccessibleControl(in: host.contentView, labeled: L10n.string("ssh_access_notice.enable_action")))
        try await waitUntilStoreState { coordinator.readyConfirmation != nil }
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].context?.profileID, profile.id)
        XCTAssertEqual(runner.calls[0].params["action"], .string("enable"))
        XCTAssertTrue(session.maintenanceUtilitiesExpanded)

        coordinator.confirm(try XCTUnwrap(coordinator.readyConfirmation))
        try await waitUntilStoreState { session.maintenanceStore.sshAccessState == .succeeded && !coordinator.isDeviceBusy(profile.id) }
        let texts = accessibleElements(in: host.contentView).map(\.text)
        XCTAssertTrue(texts.contains(L10n.string("support.ssh.enabled")))
        XCTAssertFalse(texts.contains(L10n.string("ssh_access_notice.enable_action")))
    }

    func testMissingPasswordKeepsAuthenticationInTheSSHSheet() async throws {
        let runner = StoreTestRunner(responses: [])
        let fixture = try await AppViewFixture(runner: runner)
        let profile = try await fixture.saveProfile(id: "ssh-password", passwordState: .missing, password: nil)
        let session = fixture.dashboardSession(for: profile)
        session.enableSSHAccess(profile: profile)

        XCTAssertTrue(session.maintenanceUtilitiesExpanded)
        XCTAssertNotNil(session.profileEditorStore.passwordError)
        XCTAssertTrue(runner.calls.isEmpty)
        let host = LiveHostedView(SSHAccessToolView(profile: profile, session: session,
            status: fixture.appStore.sshAccessStore, operation: session.maintenanceStore.sshAccessStore,
            editor: session.profileEditorStore))
        defer { host.close() }
        await runQueuedStoreUpdates()
        session.profileEditorStore.replacementPassword = "replacement-fixture"
        await runQueuedStoreUpdates()
        let texts = accessibleElements(in: host.contentView).map(\.text)
        XCTAssertTrue(texts.contains(L10n.string("simple.setup.password")))
    }
}
