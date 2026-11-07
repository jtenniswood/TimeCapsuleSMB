import SwiftUI

struct ActivityCompactView: View {
    @ObservedObject var activityStore: ActivityStore
    @ObservedObject var registry: DeviceRegistryStore
    let context: ActivityDisplayContext

    var body: some View {
        let status = activityStore.compactStatus(for: context)
        HStack(spacing: 10) {
            if status.isRunning && !status.requiresAttention { ProgressView().controlSize(.small) }
            else { Image(systemName: status.requiresAttention ? "exclamationmark.triangle" : "checkmark.circle").foregroundStyle(.orange) }
            Text(title(status)).lineLimit(1)
            Spacer()
        }
        .font(UtilityStyle.secondary)
        .padding(.horizontal, 24).padding(.vertical, 12)
    }

    private func title(_ status: ActivityCompactStatus) -> String {
        if case .device(let id) = status.scope, let profile = registry.profile(id: id) {
            return "\(status.operationTitle) – \(profile.title)"
        }
        return status.operationTitle
    }
}

struct ActivityDetailView: View {
    @ObservedObject var activityStore: ActivityStore
    @ObservedObject var registry: DeviceRegistryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if activityStore.activeLaneSnapshots.isEmpty && activityStore.recentLaneSnapshots.isEmpty {
                Text(L10n.string("activity.no_active_operation"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !activityStore.activeLaneSnapshots.isEmpty {
                        Section(L10n.string("activity.active")) {
                            ForEach(activityStore.activeLaneSnapshots) { snapshot in
                                ActivityLaneRow(lane: snapshot, registry: registry)
                            }
                        }
                    }
                    if !activityStore.recentLaneSnapshots.isEmpty {
                        Section(L10n.string("activity.recent")) {
                            ForEach(activityStore.recentLaneSnapshots) { snapshot in
                                ActivityLaneRow(lane: snapshot, registry: registry)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .font(UtilityStyle.body)
    }
}

private struct ActivityLaneRow: View {
    let lane: ActivityLaneSnapshot
    @ObservedObject var registry: DeviceRegistryStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if lane.snapshot.isRunning && !lane.isPendingConfirmation {
                ProgressView().controlSize(.small).frame(width: 18)
            } else {
                Image(systemName: lane.isPendingConfirmation ? "exclamationmark.triangle" : "clock")
                    .foregroundStyle(lane.isPendingConfirmation ? Color.orange : Color.secondary)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(UtilityOperationTitle.title(for: lane.snapshot.operation, fallback: lane.snapshot.operationTitle))
                if case .device(let id) = lane.snapshot.scope, let profile = registry.profile(id: id) {
                    Text(profile.title).font(UtilityStyle.secondary).foregroundStyle(.secondary)
                }
                DashboardDisclosureSection(title: L10n.string("utility.details")) {
                    if let message = lane.snapshot.latestMessage { Text(message).font(UtilityStyle.secondary) }
                    OperationTimelineListView(items: lane.snapshot.timeline)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }
}
