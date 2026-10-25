import CryptoKit
import Foundation
import REPickShared

actor HealthReportCache {
    private let root: URL
    private static let maximumBytes = 2_000_000

    init(root: URL? = nil) {
        if let root { self.root = root; return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-reset")
            || ProcessInfo.processInfo.arguments.contains("--ui-testing-use-store") {
            self.root = URL.temporaryDirectory.appending(path: "repick-health-reports-ui", directoryHint: .isDirectory)
            return
        }
        #endif
        self.root = URL.applicationSupportDirectory.appending(path: "REPick/HealthReports", directoryHint: .isDirectory)
    }

    func load(origin: String, installationID: UUID) throws -> [HealthReportResource] {
        let file = try fileURL(origin: origin, installationID: installationID)
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: file) }
        catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile { return [] }
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
        guard data.count <= Self.maximumBytes else { throw HealthReportCacheError.invalidCache }
        let saved = try HealthReportCoding.decoder().decode(SavedReports.self, from: data)
        guard saved.version == 1, saved.reports.count <= 50,
              Set(saved.reports.map(\.id)).count == saved.reports.count else {
            throw HealthReportCacheError.invalidCache
        }
        try saved.reports.forEach(Self.validate)
        return saved.reports.sorted(by: Self.isNewer)
    }

    func save(_ reports: [HealthReportResource], origin: String, installationID: UUID) throws {
        try Task.checkCancellation()
        try reports.forEach(Self.validate)
        var byID: [UUID: HealthReportResource] = [:]
        for report in try load(origin: origin, installationID: installationID) { byID[report.id] = report }
        for report in reports { byID[report.id] = report }
        let retained = Array(byID.values.sorted(by: Self.isNewer).prefix(50))
        let encoder = HealthReportCoding.encoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var value = encoder.singleValueContainer()
            try value.encode(date.ISO8601Format(.init(includingFractionalSeconds: true)))
        }
        let data = try encoder.encode(SavedReports(version: 1, reports: retained))
        guard data.count <= Self.maximumBytes else { throw HealthReportCacheError.invalidCache }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: fileURL(origin: origin, installationID: installationID),
                       options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func fileURL(origin: String, installationID: UUID) throws -> URL {
        let partition = try ReportOrigin.canonical(origin) + "\n" + installationID.uuidString.lowercased()
        let key = SHA256.hash(data: Data(partition.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appending(path: key + ".json")
    }

    private static func validate(_ report: HealthReportResource) throws {
        try report.validate()
        guard report.status == .completed else { throw HealthReportCacheError.invalidCache }
    }

    private static func isNewer(_ lhs: HealthReportResource, _ rhs: HealthReportResource) -> Bool {
        lhs.createdAt == rhs.createdAt ? lhs.id.uuidString > rhs.id.uuidString : lhs.createdAt > rhs.createdAt
    }

    private struct SavedReports: Codable {
        let version: Int
        let reports: [HealthReportResource]
    }
}

enum HealthReportCacheError: Error, LocalizedError, Sendable {
    case invalidCache

    var errorDescription: String? {
        String(localized: "보관된 리포트를 읽지 못했어요. 원본은 유지했습니다. 지난 리포트에서 새로고침해 주세요.")
    }
}
