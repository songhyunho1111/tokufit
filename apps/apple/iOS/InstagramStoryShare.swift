import Foundation
import UIKit

@MainActor
struct InstagramStoryShare {
    enum Availability { case setupRequired, appUnavailable, ready }
    enum Failure: Error { case setupRequired, appUnavailable, invalidImage, handoffFailed }

    private let appID: String?
    private let canOpenURL: (URL) -> Bool
    private let writePasteboard: (Data, Date) -> Void
    private let openURL: (URL) async -> Bool
    private let now: () -> Date

    init(bundle: Bundle = .main) {
        self.init(
            appID: ["InstagramAppID", "FacebookAppID"]
                .compactMap { bundle.object(forInfoDictionaryKey: $0) as? String }
                .first { Self.destinationURL(appID: $0) != nil },
            canOpenURL: { UIApplication.shared.canOpenURL($0) },
            writePasteboard: { data, expiration in
                UIPasteboard.general.setItems(
                    [["com.instagram.sharedSticker.backgroundImage": data]],
                    options: [.expirationDate: expiration]
                )
            },
            openURL: { await UIApplication.shared.open($0, options: [:]) }
        )
    }

    init(
        appID: String?,
        canOpenURL: @escaping (URL) -> Bool,
        writePasteboard: @escaping (Data, Date) -> Void,
        openURL: @escaping (URL) async -> Bool,
        now: @escaping () -> Date = Date.init
    ) {
        self.appID = appID
        self.canOpenURL = canOpenURL
        self.writePasteboard = writePasteboard
        self.openURL = openURL
        self.now = now
    }

    var availability: Availability {
        guard let url = Self.destinationURL(appID: appID) else { return .setupRequired }
        return canOpenURL(url) ? .ready : .appUnavailable
    }

    static func destinationURL(appID: String?) -> URL? {
        guard let appID = appID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !appID.isEmpty,
              appID.utf8.allSatisfy({ (48...57).contains($0) }),
              appID.contains(where: { $0 != "0" }) else { return nil }
        var components = URLComponents()
        components.scheme = "instagram-stories"
        components.host = "share"
        components.queryItems = [URLQueryItem(name: "source_application", value: appID)]
        return components.url
    }

    func share(pngData: Data) async throws {
        guard let url = Self.destinationURL(appID: appID) else { throw Failure.setupRequired }
        guard canOpenURL(url) else { throw Failure.appUnavailable }
        guard pngData.count > 8, pngData.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else {
            throw Failure.invalidImage
        }
        try Task.checkCancellation()
        writePasteboard(pngData, now().addingTimeInterval(5 * 60))
        // Opening the composer is a handoff. Instagram owns editing and publication.
        guard await openURL(url) else { throw Failure.handoffFailed }
    }
}
