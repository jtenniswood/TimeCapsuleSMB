import XCTest
@testable import TimeCapsuleSMBApp

@MainActor
final class FileSharingInstallationPresentationTests: XCTestCase {
    private func makeProfile(payloadFamily: String = "netbsd6_samba4") throws -> DeviceProfile {
        var profile = DeviceProfile.make(id: "overview-test-device",
            configuredDevice: try testConfiguredDevice(payloadFamily: payloadFamily), discoveredDevice: nil,
            applicationSupportURL: URL(fileURLWithPath: "/tmp/timecapsulesmb-overview-tests", isDirectory: true))
        profile.runtimeState = DeviceRuntimeStateSnapshot(state: .installedVerified, source: .doctor, stage: nil,
            payloadFamily: payloadFamily, verified: true, summary: "Ready", errorCode: nil, errorMessage: nil, recovery: nil)
        return profile
    }

    func testCurrentReleaseWithAnOlderServiceStillNeedsTheSharingUpdate() throws {
        let profile = try makeProfile(payloadFamily: "netbsd6_samba4")
        var payload = try testReachabilityPayload().decode(ReachabilityPayload.self)
        payload.installState = "current"
        let sharing = DiskSharingPayload(schemaVersion: 1, enabled: true, security: "accounts", accounts: [],
            revision: "revision", supported: false, partitions: [])
        let state = FileSharingInstallationPresentation(profile: profile, payload: payload, sharing: sharing, checking: false)
        XCTAssertEqual(state.state, .updateAvailable)
        XCTAssertTrue(state.needsInstall)
    }

    func testMissingVersionEvidenceDoesNotClaimTheDeviceIsUpToDate() throws {
        let profile = try makeProfile()
        XCTAssertNotEqual(FileSharingInstallationPresentation(profile: profile, payload: nil, sharing: nil, checking: false).state, .upToDate)
    }

    func testDeviceModelUsesFriendlyFamilyAndGeneration() throws {
        let previousLanguage = L10n.currentLanguage
        L10n.apply(language: .english)
        defer { L10n.apply(language: previousLanguage) }
        var profile = try makeProfile()
        profile.syap = "119"
        profile.model = "TimeCapsule8,119"
        XCTAssertEqual(DeviceDashboardHeaderPresentation.friendlyModelValue(for: profile), "Apple Time Capsule, 5th Generation")
    }

    func testRemovedPanesLeadToOverview() {
        XCTAssertEqual(DeviceDashboardTab.allCases, [.overview, .maintenance])
        XCTAssertEqual(DeviceDashboardTab.checkup.visibleTab, .overview)
        XCTAssertEqual(DeviceDashboardTab.install.visibleTab, .overview)
        XCTAssertEqual(DeviceDashboardTab.settings.visibleTab, .overview)
    }
}
