import AppKit
import XCTest
@testable import TimeCapsuleSMBApp

@MainActor
final class SSHSupportViewTests: XCTestCase {
    func testEnabledConnectionHelpHasANativeTooltipAtTheTrailingEdge() async throws {
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

        func nativeTooltip(in view: NSView) -> NSImageView? {
            if let image = view as? NSImageView, image.toolTip != nil { return image }
            return view.subviews.lazy.compactMap { nativeTooltip(in: $0) }.first
        }
        let icon = try XCTUnwrap(nativeTooltip(in: host.contentView))
        let command = try XCTUnwrap(DeviceEndpointPolicy.terminalSSHCommand(profile.host))
        XCTAssertEqual(icon.toolTip, L10n.format("support.ssh.connection_help", command))
        XCTAssertEqual(icon.accessibilityHelp(), icon.toolTip)
        XCTAssertGreaterThanOrEqual(icon.visibleRect.width, 20)
        XCTAssertGreaterThanOrEqual(icon.visibleRect.height, 20)
        let rect = icon.convert(icon.bounds, to: host.contentView)
        XCTAssertEqual(rect.maxX, host.contentView.bounds.maxX, accuracy: 1)
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
