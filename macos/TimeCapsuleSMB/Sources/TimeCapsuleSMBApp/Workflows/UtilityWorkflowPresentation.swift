import Foundation

extension MaintenanceWorkflow {
    var utilityTitle: String { L10n.string("utility.tools.\(rawValue)") }
}

extension MaintenanceUserAction {
    var utilityTitle: String {
        switch self {
        case .enableSSHAccess: return L10n.string("utility.connection.allow")
        case .checkSSHAccess: return L10n.string("simple.check_connection")
        case .runActivation: return L10n.string("utility.sharing.start")
        case .runUninstall: return L10n.string("utility.sharing.remove")
        case .runWipeDisk: return L10n.string("utility.disk.erase")
        case .installSMB: return L10n.string("simple.sharing.set_up")
        case .viewDiagnostics: return L10n.string("utility.support")
        default: return title
        }
    }
}

/// Shows the next valid step without bypassing the workflow's existing gates.
enum MaintenanceGuidePolicy {
    static func primaryAction(presentation: MaintenanceWorkflowDetailPresentation) -> MaintenanceUserAction {
        switch presentation.workflow {
        case .sshAccess: return .enableSSHAccess
        case .activate: return .runActivation
        case .uninstall: return .runUninstall
        case .wipeDisk: return .runWipeDisk
        case .fsck:
            if presentation.isEnabled(.runFsck) { return .runFsck }
            if presentation.isEnabled(.planFsck) { return .planFsck }
            return .findVolumes
        case .bootHook:
            if presentation.isEnabled(.writePatch) { return .writePatch }
            if presentation.isEnabled(.writeRestore) { return .writeRestore }
            if presentation.isEnabled(.planPatch) { return .planPatch }
            return .backUpAndInspectFirmware
        }
    }
}

enum UtilityOperationTitle {
    static func title(for operation: String?, fallback: String) -> String {
        let key: String
        switch operation {
        case "configure", "reachability", "set-ssh": key = "simple.tab.connection"
        case "deploy": key = "simple.sharing.title"
        case "doctor": key = "simple.check_connection"
        case "fsck": key = "maintenance.presentation.fsck.title"
        case "wipe-disk": key = "utility.tools.wipeDisk"
        case "activate": key = "utility.sharing.start"
        case "uninstall": key = "utility.tools.uninstall"
        case "flash": key = "utility.tools.bootHook"
        case "discover": key = "simple.setup.choose_title"
        default: return fallback
        }
        return L10n.string(key)
    }
}
