import XCTest
@testable import TimeCapsuleSMBApp

@MainActor
final class DiskHealthReportTests: XCTestCase {
    private func report() throws -> DiskHealthReport {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "disk_smart_report", withExtension: "json", subdirectory: "Fixtures"
        ))
        return try JSONDecoder().decode(DiskHealthReport.self, from: Data(contentsOf: url))
    }

    func testDecodesHelperReadingsAndKeepsRawVendorValues() throws {
        let report = try report()
        XCTAssertNil(report.error)
        XCTAssertEqual(report.disks.count, 2)
        let disk = report.disks[0]
        XCTAssertEqual(disk.temperatureCelsius, "48 °C")
        XCTAssertEqual(disk.metric(9, named: "Power-on hours count"), 16141.formatted())
        XCTAssertEqual(disk.metric(5, named: "Reallocated sector count"), "0")
        XCTAssertEqual(disk.metric(197, named: "Current pending sector"), "0")
        XCTAssertFalse(disk.reportsFailure)
        XCTAssertEqual(disk.details.attributes.first?.raw, "109549360")
        XCTAssertEqual(disk.details.attributes.first?.reliability, "positive")
        XCTAssertEqual(disk.details.attributes.count, 24)
        XCTAssertNil(report.disks[1].temperatureCelsius)
        XCTAssertNil(report.disks[1].metric(9, named: "Power-on hours count"))
        XCTAssertFalse(report.disks[1].reportsFailure)
    }

    func testOnlyKnownReadingsGetUnitsAndMissingDoesNotMeanZero() throws {
        let disk = try report().disks[0]
        XCTAssertNil(disk.metric(1, named: "Reallocated sector count"))
        XCTAssertNil(disk.metric(999, named: "Unknown"))
        let vendorTemperature = DiskSmartAttribute(
            id: 194, value: 100, threshold: 0, critical: false,
            collection: "online", reliability: "positive", name: "Vendor-specific", raw: "1024"
        )
        let unknown = replacing(disk, details: DiskSmartDetails(state: "available", attributes: [vendorTemperature]))
        XCTAssertNil(unknown.temperatureCelsius)
        let unavailable = replacing(disk, details: DiskSmartDetails(state: "unavailable", attributes: disk.details.attributes))
        XCTAssertNil(unavailable.temperatureCelsius)
        XCTAssertNil(unavailable.metric(9, named: "Power-on hours count"))
    }

    func testSelectedMediaProblemsNeedAttentionWithoutLabelingEveryVendorValueAsFailure() throws {
        let disk = try report().disks[0]
        XCTAssertFalse(disk.needsAttention)
        for (id, name) in [(5, "Reallocated sector count"), (197, "Current pending sector"), (198, "Offline uncorrectable")] {
            let attribute = DiskSmartAttribute(id: id, value: 100, threshold: 0, critical: false,
                collection: "online", reliability: "positive", name: name, raw: "1")
            let problem = replacing(disk, details: DiskSmartDetails(state: "available", attributes: [attribute]))
            XCTAssertTrue(problem.needsAttention)
            XCTAssertFalse(problem.reportsFailure)
        }
        let vendor = DiskSmartAttribute(id: 197, value: 100, threshold: 0, critical: false,
            collection: "online", reliability: "positive", name: "Vendor-specific", raw: "999")
        XCTAssertFalse(replacing(disk, details: DiskSmartDetails(state: "available", attributes: [vendor])).needsAttention)
    }

    func testFailureIsKeptWhenDetailedReadingsAreUnavailable() throws {
        let disk = try report().disks[0]
        XCTAssertTrue(replacing(disk, status: "failing", details: DiskSmartDetails(
            state: "unsupported", attributes: []
        )).reportsFailure)
        XCTAssertTrue(replacing(disk, details: DiskSmartDetails(
            state: "unavailable", attributes: [], thresholdExceeded: true
        )).reportsFailure)
        let failedAttribute = DiskSmartAttribute(
            id: 5, value: 30, threshold: 36, critical: true,
            collection: "online", reliability: "negative", name: "Reallocated sector count", raw: "1000"
        )
        XCTAssertTrue(replacing(disk, details: DiskSmartDetails(
            state: "available", attributes: [failedAttribute]
        )).reportsFailure)
    }

    func testAppPayloadAndPersistedSnapshotCarryTheReport() throws {
        let report = try report()
        var payload = try testDoctorPayload(checks: []).decode(DoctorPayload.self)
        XCTAssertNil(payload.diskHealth) // Older helpers omit the field.
        payload.diskHealth = report
        let summary = DoctorSummary(payload: payload)
        let checkedAt = Date(timeIntervalSince1970: 1234)
        let snapshot = DeviceDashboardSnapshotMapper.checkupSnapshot(
            state: .passed, summary: summary, observedAt: checkedAt
        )
        let data = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(DeviceCheckupSnapshot.self, from: data)
        XCTAssertEqual(restored.diskHealth, report)
        XCTAssertEqual(restored.checkedAt, checkedAt)
        // Profiles saved by earlier versions must still load.
        var older = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        older.removeValue(forKey: "diskHealth")
        let oldSnapshot = try JSONDecoder().decode(
            DeviceCheckupSnapshot.self, from: JSONSerialization.data(withJSONObject: older)
        )
        XCTAssertNil(oldSnapshot.diskHealth)
    }

    func testNewHelperPayloadDecodesTheReport() throws {
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(testDoctorPayload(checks: []))
        ) as? [String: Any])
        payload["disk_health"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(report()))
        let decoded = try JSONDecoder().decode(DoctorPayload.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(decoded.diskHealth, try report())
    }

    func testInvalidSpaceNeverOverflowsOrDisplaysNegativeCapacity() {
        XCTAssertNil(DiskHealthPartition.bytes(nil))
        XCTAssertNil(DiskHealthPartition.bytes(-1))
        XCTAssertNil(DiskHealthPartition.bytes(Int64.max))
        XCTAssertNotNil(DiskHealthPartition.bytes(0))
        XCTAssertNotNil(DiskHealthPartition.bytes(1905681))
    }

    func testCapacityCombinesTheVolumesOfOneDisk() {
        let disk = DiskHealthDisk(device: "wd0", label: "Disk", builtin: true, smartStatus: "verified",
            partitions: [DiskHealthPartition(name: "A", sizeMiB: 100, usedMiB: 40, freeMiB: 60),
                         DiskHealthPartition(name: "B", sizeMiB: 200, usedMiB: 100, freeMiB: 100)],
            details: DiskSmartDetails(state: "unavailable", attributes: []))
        XCTAssertEqual(disk.totalCapacity, DiskHealthPartition.bytes(300))
        XCTAssertEqual(disk.freeCapacity, DiskHealthPartition.bytes(160))
    }

    func testMissingOrOverflowingVolumeSizesDoNotBecomePartialTotals() {
        for sizes: [Int64?] in [[100, nil], [Int64.max, 1], [-1, 100]] {
            let disk = DiskHealthDisk(device: "wd0", label: "Disk", builtin: true, smartStatus: nil,
                partitions: sizes.map { DiskHealthPartition(name: "Volume", sizeMiB: $0, usedMiB: nil, freeMiB: $0) },
                details: DiskSmartDetails(state: "unavailable", attributes: []))
            XCTAssertNil(disk.totalCapacity)
            XCTAssertNil(disk.freeCapacity)
        }
    }

    func testRendersReportedAndUnavailableDiskHealth() throws {
        let bitmap = try renderView(
            DiskHealthView(report: report()),
            size: CGSize(width: 800, height: 500)
        )
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
    }

    private func replacing(
        _ disk: DiskHealthDisk, status: String? = "verified", details: DiskSmartDetails
    ) -> DiskHealthDisk {
        DiskHealthDisk(
            device: disk.device, label: disk.label, builtin: disk.builtin,
            smartStatus: status, partitions: disk.partitions, details: details
        )
    }
}
