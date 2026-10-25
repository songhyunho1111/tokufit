import Foundation
import ImageIO
import REPickShared
import WidgetKit

@MainActor
final class WatchComplicationPublisher {
    private let directory: URL?
    private var lastPayload: WidgetPayload?
    private var lastReload: Date?

    init(directory: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetStorage.appGroup)) {
        self.directory = directory
    }

    func publish(state: UsagiState, updatedAt: Date, characterPNG: Data?) throws {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        try state.validate()
        let payload = try WidgetPayload(snapshot: WidgetSnapshot(state: state, now: updatedAt), characterPNG: characterPNG)
        try Self.validateImage(characterPNG)
        if lastPayload?.snapshot == payload.snapshot, lastPayload?.characterPNG == characterPNG { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        guard data.count <= WidgetStorage.maximumPayloadBytes else { throw WidgetPayloadError.invalidImage }
        try data.write(to: directory.appending(path: WidgetStorage.filename), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let appearanceChanged = lastPayload?.characterPNG != characterPNG
            || lastPayload?.snapshot.hasProfile != payload.snapshot.hasProfile
        let now = Date()
        if appearanceChanged || lastReload == nil || now.timeIntervalSince(lastReload ?? .distantPast) >= 60 {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetStorage.watchKind)
            lastReload = now
        }
        lastPayload = payload
    }

    static func validateImage(_ data: Data?) throws {
        guard let data else { return }
        guard data.count <= 96 * 1_024,
              data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...512).contains(width), (1...512).contains(height),
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw WidgetPayloadError.invalidImage
        }
    }
}
