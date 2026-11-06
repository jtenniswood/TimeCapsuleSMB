import AppKit
import SwiftUI

struct DiskHealthView: View {
    let report: DiskHealthReport?
    let checkedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let report, report.error == nil {
                if report.disks.isEmpty {
                    Text(L10n.string("disk_health.no_disks"))
                        .font(UtilityStyle.body)
                }
                ForEach(report.disks) { disk in
                    DiskSmartReadingsView(disk: disk)
                }
            } else {
                Text(L10n.string(report == nil || report?.error == "not_checked" ? "utility.status.unchecked" : "utility.disk.unavailable"))
                    .font(UtilityStyle.body)
                    .foregroundStyle(.secondary)
            }
            if let checkedAt {
                Text(L10n.format("disk_health.checked_at", checkedAt.formatted(date: .abbreviated, time: .shortened)))
                    .font(UtilityStyle.secondary)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DiskSmartReadingsView: View {
    let disk: DiskHealthDisk

    private var statusKey: String {
        if disk.reportsFailure { return "utility.disk.failing" }
        if disk.needsAttention { return "disk_health.attention" }
        return disk.smartStatus == "verified" ? "utility.status.working" : "utility.status.unchecked"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                if let artwork = DiskArtwork.image {
                    Image(nsImage: artwork).resizable().scaledToFit().frame(width: 48, height: 48)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: disk.builtin ? "internaldrive" : "externaldrive")
                        .font(.system(size: 32)).foregroundStyle(.secondary).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(disk.partitions.first?.name ?? disk.label).font(UtilityStyle.heading)
                    Label(L10n.string(statusKey), systemImage: disk.needsAttention ? "exclamationmark.triangle" :
                        disk.smartStatus == "verified" ? "checkmark.circle" : "questionmark.circle")
                        .foregroundStyle(disk.reportsFailure ? Color.red : disk.needsAttention ? .orange : .secondary)
                }
                Spacer()

            }
            if disk.reportsFailure {
                Text(L10n.string("utility.disk.failure_advice"))
                    .font(UtilityStyle.body)
            } else if disk.needsAttention {
                Text(L10n.string("disk_health.attention_advice")).font(UtilityStyle.body)
            }
            ForEach(Array(disk.partitions.enumerated()), id: \.offset) { _, partition in
                if let total = DiskHealthPartition.bytes(partition.sizeMiB),
                   let free = DiskHealthPartition.bytes(partition.freeMiB) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.format("disk_health.space", partition.name, free, total))
                            .font(UtilityStyle.secondary).foregroundStyle(.secondary)
                        if let size = partition.sizeMiB, size > 0, let available = partition.freeMiB, available >= 0 {
                            ProgressView(value: Double(size - min(size, available)), total: Double(size))
                                .tint(.accentColor)
                                .accessibilityLabel(partition.name)
                        }
                    }

                }
            }
            if disk.details.state == "available" {
                VStack(alignment: .leading, spacing: 20) {
                    SummaryGrid(rows: [
                        (L10n.string("disk_health.temperature"), disk.temperatureCelsius ?? L10n.string("value.unknown")),
                        (L10n.string("disk_health.usage"), disk.metric(9, named: "Power-on hours count") ?? L10n.string("value.unknown"))
                    ])
                    if disk.needsAttention {
                        SummaryGrid(rows: [
                            (L10n.string("disk_health.reallocated"), disk.metric(5, named: "Reallocated sector count")),
                            (L10n.string("disk_health.pending"), disk.metric(197, named: "Current pending sector")),
                            (L10n.string("disk_health.uncorrectable"), disk.metric(198, named: "Offline uncorrectable"))
                        ].compactMap { label, value in value.map { (label, $0) } })
                    }
                }
            } else {
                Text(L10n.string("disk_health.details_unavailable"))
                    .font(UtilityStyle.secondary).foregroundStyle(.secondary)
            }
        }
    }
}

enum DiskArtwork {
    static let image = NSImage(contentsOfFile:
        "/System/Applications/Utilities/AirPort Utility.app/Contents/Resources/AirDisk.icns")
}
