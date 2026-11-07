import Foundation

/// Brief, actionable wording for the everyday interface. The complete helper
/// recovery and diagnostic text remains available in the Details disclosure.
enum UtilityErrorPresentation {
    static func title(for error: BackendErrorViewModel) -> String {
        let key: String
        switch error.code {
        case "auth_failed": key = "utility.error.password"
        case "password_missing", "keychain_unavailable": key = "utility.error.saved_password"
        case "unsupported_device": key = "utility.error.unsupported"
        case "cancelled", "confirmation_cancelled": key = "utility.error.cancelled"
        default:
            if error.recovery?.localNetworkBlock == .proven {
                return L10n.string("utility.error.local_network")
            }
            switch error.operation {
            case "configure", "reachability", "set-ssh": key = "utility.error.connect"
            case "deploy": key = "utility.error.sharing"
            case "doctor": key = "utility.error.check"
            case "fsck": key = "utility.error.repair"
            case "wipe-disk": key = "utility.error.erase"
            case "discover": key = "utility.error.discover"
            default: return error.message
            }
        }
        return L10n.string(key)
    }

    static func actionTitle(_ action: RecoveryAction) -> String {
        switch action.kind {
        case .retry: return L10n.string("utility.try_again")
        case .runCheckup: return L10n.string("simple.check_connection")
        case .installSMB: return L10n.string("simple.sharing.set_up")
        case .startSMB: return L10n.string("utility.sharing.start")
        case .uninstall: return L10n.string("utility.sharing.remove")
        case .diskRepair: return L10n.string("utility.disk.repair")
        case .wipeDisk: return L10n.string("utility.disk.erase")
        case .replacePassword: return L10n.string("utility.password.update")
        case .copyDiagnostics: return L10n.string("utility.copy_details")
        case .diagnostics: return L10n.string("utility.support")
        case .openSSHAccess: return L10n.string("utility.connection.options")
        case .openSystemSettings, .generic: return action.title
        }
    }
}
