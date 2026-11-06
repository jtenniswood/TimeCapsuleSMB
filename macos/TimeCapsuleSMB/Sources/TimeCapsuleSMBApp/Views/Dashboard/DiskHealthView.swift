import SwiftUI

struct DiskHealthView: View {
    let report: DiskHealthReport?
    let checkedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("disk_health.title"))
                .font(.headline)
            if let checkedAt {
                Text(L10n.format("disk_health.checked_at", checkedAt.formatted(date: .abbreviated, time: .shortened)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let report, report.error == nil {
                if report.disks.isEmpty {
                    Text(L10n.string("disk_health.no_disks"))
                        .font(.callout)
                }
                ForEach(report.disks) { disk in
                    DiskSmartReadingsView(disk: disk)
                }
            } else {
                Text(L10n.string(report == nil || report?.error == "not_checked" ? "disk_health.not_checked" : "disk_health.unavailable"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct DiskSmartReadingsView: View {
    let disk: DiskHealthDisk

    private var statusKey: String {
        if disk.reportsFailure { return "disk_health.failing" }
        return disk.smartStatus == "verified" ? "disk_health.verified" : "disk_health.not_reported"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(disk.label, systemImage: disk.builtin ? "internaldrive" : "externaldrive")
                    .font(.body.weight(.medium))
                Spacer()
                Label(L10n.string(statusKey), systemImage: disk.reportsFailure ? "exclamationmark.triangle" :
                    disk.smartStatus == "verified" ? "checkmark.circle" : "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(disk.reportsFailure ? Color.orange : Color.secondary)
            }
            if disk.reportsFailure {
                Text(L10n.string("disk_health.failure_advice"))
                    .font(.callout)
            }
            ForEach(Array(disk.partitions.enumerated()), id: \.offset) { _, partition in
                if let total = DiskHealthPartition.bytes(partition.sizeMiB),
                   let free = DiskHealthPartition.bytes(partition.freeMiB) {
                    Text(L10n.format("disk_health.space", partition.name, free, total))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if disk.details.state == "available" {
                if let temperature = disk.temperatureCelsius {
                    LabeledContent(L10n.string("disk_health.temperature"), value: temperature)
                        .font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup(L10n.string("simple.technical_details")) {
                    SummaryGrid(rows: [
                        (L10n.string("disk_health.temperature"), disk.temperatureCelsius ?? L10n.string("value.unknown")),
                        (L10n.string("disk_health.power_on_hours"), disk.metric(9, named: "Power-on hours count") ?? L10n.string("value.unknown")),
                        (L10n.string("disk_health.reallocated"), disk.metric(5, named: "Reallocated sector count") ?? L10n.string("value.unknown")),
                        (L10n.string("disk_health.pending"), disk.metric(197, named: "Current pending sector") ?? L10n.string("value.unknown")),
                        (L10n.string("disk_health.uncorrectable"), disk.metric(198, named: "Offline uncorrectable") ?? L10n.string("value.unknown")),
                        (L10n.string("disk_health.crc_errors"), disk.metric(199, named: "Ultra DMA CRC error count") ?? L10n.string("value.unknown"))
                    ])
                    Text(L10n.string("disk_health.attributes")).font(.subheadline.weight(.medium))
                    Table(disk.details.attributes) {
                        TableColumn(L10n.string("disk_health.id")) { attribute in Text(String(attribute.id)) }
                            .width(32)
                        TableColumn(L10n.string("disk_health.attribute"), value: \.name)
                            .width(min: 140)
                        TableColumn(L10n.string("disk_health.value")) { attribute in Text(String(attribute.value)) }
                            .width(50)
                        TableColumn(L10n.string("disk_health.threshold")) { attribute in Text(String(attribute.threshold)) }
                            .width(65)
                        TableColumn(L10n.string("disk_health.raw"), value: \.raw)
                            .width(min: 100)
                        TableColumn(L10n.string("disk_health.reliability")) { attribute in
                            Text(L10n.string(attribute.reliability == "negative" ? "disk_health.outside_threshold" : "disk_health.within_threshold"))
                        }
                            .width(min: 110)
                    }
                    .frame(height: 220)
                    Text(L10n.string("disk_health.vendor_values"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(L10n.string("disk_health.details_unavailable"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
