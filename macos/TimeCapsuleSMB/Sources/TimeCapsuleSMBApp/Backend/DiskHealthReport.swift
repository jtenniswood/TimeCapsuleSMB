import Foundation

/// App-only readings collected during Checkup, not background reachability
/// or the developer telemetry report. Unknown and missing readings stay nil.
struct DiskHealthReport: Codable, Equatable {
    let error: String?
    let disks: [DiskHealthDisk]
}

struct DiskHealthDisk: Codable, Equatable, Identifiable {
    let device: String
    let label: String
    let builtin: Bool
    let smartStatus: String?
    let partitions: [DiskHealthPartition]
    let details: DiskSmartDetails

    var id: String { device }
    var reportsFailure: Bool {
        smartStatus == "failing" || details.thresholdExceeded == true
            || details.attributes.contains { $0.critical && $0.reliability == "negative" }
    }

    /// These are the names atactl itself gives the standard HDD attributes.
    /// Other vendor-specific encodings remain visible only as raw attributes.
    func metric(_ id: Int, named name: String) -> String? {
        guard details.state == "available",
              let attribute = details.attributes.first(where: { $0.id == id }),
              attribute.name.caseInsensitiveCompare(name) == .orderedSame,
              let raw = attribute.raw.split(separator: " ").first,
              let value = UInt64(raw) else { return nil }
        return value.formatted()
    }

    var temperatureCelsius: String? {
        let attribute = details.attributes.first { $0.id == 194 && $0.name == "Temperature" }
            ?? details.attributes.first { $0.id == 190 && $0.name == "Airflow Temperature" }
        guard details.state == "available", let raw = attribute?.raw.split(separator: " ").first,
              let value = Int(raw), (0...125).contains(value) else { return nil }
        return "\(value) °C"
    }

    enum CodingKeys: String, CodingKey {
        case device, label, builtin, partitions, details
        case smartStatus = "smart_status"
    }
}

struct DiskHealthPartition: Codable, Equatable {
    let name: String
    let sizeMiB: Int64?
    let usedMiB: Int64?
    let freeMiB: Int64?

    static func bytes(_ mib: Int64?) -> String? {
        guard let mib, mib >= 0, mib <= Int64.max / 1_048_576 else { return nil }
        return ByteCountFormatter.string(fromByteCount: mib * 1_048_576, countStyle: .file)
    }

    enum CodingKeys: String, CodingKey {
        case name
        case sizeMiB = "size_mib"
        case usedMiB = "used_mib"
        case freeMiB = "free_mib"
    }
}

struct DiskSmartDetails: Codable, Equatable {
    let state: String
    let attributes: [DiskSmartAttribute]
    var thresholdExceeded: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case state, attributes
        case thresholdExceeded = "threshold_exceeded"
    }
}

struct DiskSmartAttribute: Codable, Equatable, Identifiable {
    let id: Int
    let value: Int
    let threshold: Int
    let critical: Bool
    let collection: String
    let reliability: String
    let name: String
    let raw: String
}
