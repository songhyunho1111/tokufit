import Foundation

public struct APIStatus: Codable, Sendable {
    public let status: String
    public let service: String
    public let timestamp: String

    public init(status: String, service: String, timestamp: String) {
        self.status = status
        self.service = service
        self.timestamp = timestamp
    }

    public var date: Date? {
        guard timestamp.range(of: #"^\d{4}-\d{2}-\d{2}T([01]\d|2[0-3]):[0-5]\d:[0-5]\d(\.\d+)?(Z|[+-]([01]\d|2[0-3]):[0-5]\d)$"#, options: .regularExpression) != nil,
              UsagiState.isValidDay(String(timestamp.prefix(10))) else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: timestamp) { return date }
        formatter.formatOptions = .withInternetDateTime
        return formatter.date(from: timestamp)
    }
}
