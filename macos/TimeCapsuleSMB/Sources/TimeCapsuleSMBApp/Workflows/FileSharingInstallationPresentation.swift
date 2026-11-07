import Foundation

struct FileSharingInstallationPresentation: Equatable {
    enum State: Equatable { case notInstalled, updateAvailable, upToDate, installed, checking }
    let state: State
    let version: String?

    init(profile: DeviceProfile, payload: ReachabilityPayload?, sharing: DiskSharingPayload?, checking: Bool) {
        version = payload?.installedReleaseTag
        if profile.runtimeState == nil || profile.runtimeState?.state == .notInstalled {
            state = .notInstalled
        } else if payload?.installState == "outdated" || payload?.installState == "unknown"
                    || (profile.payloadFamily == "netbsd6_samba4" && sharing?.supported == false) {
            state = .updateAvailable
        } else if checking && (payload == nil || (profile.payloadFamily == "netbsd6_samba4" && sharing == nil)) {
            state = .checking
        } else if ["current", "newer"].contains(payload?.installState ?? "")
                    && (profile.payloadFamily != "netbsd6_samba4" || sharing?.supported == true) {
            state = .upToDate
        } else {
            state = .installed
        }
    }

    var statusTitle: String {
        switch state {
        case .notInstalled: return L10n.string("dashboard.overview.installed_version.not_installed")
        case .updateAvailable: return L10n.string("simple.software.update_available")
        case .upToDate: return L10n.string("simple.software.current")
        case .installed: return L10n.string("simple.software.installed")
        case .checking: return L10n.string("simple.software.checking_version")
        }
    }

    var needsInstall: Bool { state == .notInstalled || state == .updateAvailable }
}
