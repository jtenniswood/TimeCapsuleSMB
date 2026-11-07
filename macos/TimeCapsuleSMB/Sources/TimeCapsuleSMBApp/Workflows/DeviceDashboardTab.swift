import Foundation

enum DeviceDashboardTab: String, CaseIterable, Equatable, Identifiable {
    case overview
    case install
    case checkup
    case maintenance
    case settings

    // Keep old workflow destinations usable without exposing removed panes.
    static let allCases: [Self] = [.overview]

    var visibleTab: Self { .overview }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return L10n.string("dashboard.tab.overview")
        case .install:
            return L10n.string("simple.sharing.title")
        case .checkup:
            return L10n.string("simple.tab.connection")
        case .maintenance:
            return L10n.string("simple.tab.disks")
        case .settings:
            return L10n.string("utility.tab.base_station")
        }
    }
}
