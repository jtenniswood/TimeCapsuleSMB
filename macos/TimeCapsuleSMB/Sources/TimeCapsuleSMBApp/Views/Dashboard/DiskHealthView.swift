import AppKit
import SwiftUI

struct DiskHealthView: View {
    let report: DiskHealthReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let report, report.error == nil {
                if report.disks.isEmpty {
                    Text(L10n.string("disk_health.no_disks"))
                        .font(UtilityStyle.body)
                }
                ForEach(report.disks) { disk in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            DiskSmartReadingsView(disk: disk)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text(L10n.string(report == nil || report?.error == "not_checked" ? "utility.status.unchecked" : "utility.disk.unavailable"))
                    .font(UtilityStyle.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DiskSmartReadingsView: View {
    let disk: DiskHealthDisk

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
                    if let capacity = disk.totalCapacity {
                        Text(capacity).foregroundStyle(.secondary)
                    }
                }
                Spacer()

            }
            if disk.reportsFailure {
                Label(L10n.string("utility.disk.failing"), systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                Text(L10n.string("utility.disk.failure_advice")).font(UtilityStyle.body)
            } else if disk.needsAttention {
                Label(L10n.string("disk_health.attention"), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Text(L10n.string("disk_health.attention_advice")).font(UtilityStyle.body)
            }
            HStack(spacing: 32) {
                if let free = disk.freeCapacity { reading(L10n.string("disk_health.free_space"), value: free) }
                if disk.details.state == "available" {
                    reading(L10n.string("disk_health.temperature"), value: disk.temperatureCelsius)
                    reading(L10n.string("disk_health.usage"), value: disk.metric(9, named: "Power-on hours count"))
                }
                Spacer(minLength: 0)
            }
            if disk.details.state == "available", disk.needsAttention {
                SummaryGrid(rows: [
                    (L10n.string("disk_health.reallocated"), disk.metric(5, named: "Reallocated sector count")),
                    (L10n.string("disk_health.pending"), disk.metric(197, named: "Current pending sector")),
                    (L10n.string("disk_health.uncorrectable"), disk.metric(198, named: "Offline uncorrectable"))
                ].compactMap { label, value in value.map { (label, $0) } })
            } else if disk.details.state != "available" {
                Text(L10n.string("disk_health.details_unavailable"))
                    .font(UtilityStyle.secondary).foregroundStyle(.secondary)
            }
        }
    }

    private func reading(_ label: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(UtilityStyle.secondary).foregroundStyle(.secondary)
            Text(value ?? L10n.string("value.unknown")).monospacedDigit()
        }
    }
}

enum DiskArtwork {
    static let image = NSImage(contentsOfFile:
        "/System/Applications/Utilities/AirPort Utility.app/Contents/Resources/AirDisk.icns")
}
