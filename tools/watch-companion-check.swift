// Run with python3 tools/check_watch_companion.py; no simulator or real App Group is touched.
import AppKit
import Foundation
import ImageIO
import REPickShared

typealias UIImage = NSImage
enum WatchCharacterImage {
    static func prepare(_ data: Data) -> UIImage? { NSImage(data: data) }
}

enum WCSessionActivationState { case notActivated, activated }
protocol WCSessionDelegate: AnyObject {}
@MainActor final class WCSession {
    static let `default` = WCSession()
    static func isSupported() -> Bool { true }
    weak var delegate: (any WCSessionDelegate)?
    var receivedApplicationContext: [String: Any] = [:]
    var isReachable = false
    var activationState = WCSessionActivationState.activated
    var hasContentPending = false
    func activate() {}
}

@MainActor final class WidgetCenter {
    static let shared = WidgetCenter()
    func reloadTimelines(ofKind: String) {}
}

@main enum WatchCompanionCheck {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "REPick.watch-receiver-check.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { preconditionFailure("Missing test defaults") }
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let publisher = WatchComplicationPublisher(directory: directory)
        let file = directory.appending(path: WidgetStorage.filename)
        func receiver() -> WatchCompanion { WatchCompanion(defaults: defaults, complication: publisher) }
        func deliver(_ context: [String: Any], to receiver: WatchCompanion) {
            WCSession.default.receivedApplicationContext = context
            receiver.refreshConnection()
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        func context(_ state: UsagiState, _ timestamp: Double, _ image: Data?, minutes: Int = 0) throws -> [String: Any] {
            var result: [String: Any] = ["version": 1, "data": try encoder.encode(state),
                                         "updatedAt": timestamp, "workoutMinutesToday": minutes]
            result["characterPNG"] = image
            return result
        }
        let timestamp = floor(Date().timeIntervalSince1970) - 60
        var state = UsagiState()
        try state.setProfile(heightCM: 170, weightKG: 70, targetWeightKG: 65, goalSteps: 6_000)
        let firstPNG = makePNG(red: 1)
        let secondPNG = makePNG(red: 0)
        var companion = receiver()
        let fresh = try context(state, timestamp, firstPNG)
        deliver(fresh, to: companion)
        check(companion.state == state && companion.characterPNG == firstPNG, "Fresh state/image must be accepted")
        check(companion.characterImage != nil && !companion.isCharacterImageStale, "Fresh PNG must be visible and current")
        let firstPayload = try Data(contentsOf: file)

        try state.addWater(250)
        let imageMissing = try context(state, timestamp + 1, nil, minutes: 25)
        deliver(imageMissing, to: companion)
        check(companion.state == state && companion.workoutMinutesToday == 25, "Missing image must not block new records")
        check(companion.characterPNG == firstPNG && companion.characterImage != nil && companion.isCharacterImageStale,
              "Missing PNG must preserve and mark the previous image")
        let cached = defaults.dictionary(forKey: "companion.context")
        check(cached?["characterPNG"] as? Data == firstPNG && cached?["isCharacterImageStale"] as? Bool == true,
              "Merged image and stale marker must persist together")
        check(try Data(contentsOf: file) == firstPayload, "Missing image must preserve complete complication payload")
        companion = receiver()
        check(companion.state == state && companion.characterPNG == firstPNG && companion.isCharacterImageStale,
              "Relaunch must restore current records with honestly stale image")
        check(try Data(contentsOf: file) == firstPayload, "Relaunch must not publish retained image as fresh")
        deliver(imageMissing, to: companion)
        check(companion.isCharacterImageStale && companion.characterPNG == firstPNG, "Repeated missing PNG must remain stale")

        let next = try context(state, timestamp + 2, secondPNG, minutes: 30)
        companion.session(WCSession.default, didReceiveApplicationContext: next)
        for _ in 0..<20 where companion.updatedAt?.timeIntervalSince1970 != timestamp + 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        check(companion.characterPNG == secondPNG && !companion.isCharacterImageStale && companion.workoutMinutesToday == 30,
              "Delegate delivery of a fresh PNG must clear staleness")
        check(defaults.dictionary(forKey: "companion.context")?["isCharacterImageStale"] as? Bool == false,
              "Freshness must survive another relaunch")
        let newPayload = try Data(contentsOf: file)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(WidgetPayload.self, from: newPayload)
        check(payload.characterPNG == secondPNG && payload.snapshot.waterML == 250, "Fresh image and metrics must publish together")

        deliver(fresh, to: companion)
        check(companion.updatedAt?.timeIntervalSince1970 == timestamp + 2 && companion.characterPNG == secondPNG,
              "Out-of-order delivery must not roll back the accepted image/state")
        let goodCache = defaults.dictionary(forKey: "companion.context")! as NSDictionary
        for invalidPNG in [Data([0, 1, 2]), Data(firstPNG.prefix(8)), makePNG(red: 1, width: 513)] {
            deliver(try context(state, timestamp + 3, invalidPNG), to: companion)
            check(companion.characterPNG == secondPNG && companion.updatedAt?.timeIntervalSince1970 == timestamp + 2,
                  "Invalid PNG must not replace accepted state/image")
            check(companion.errorMessage != nil && !companion.isCharacterImageStale, "Invalid PNG must report error without altering freshness")
            check(defaults.dictionary(forKey: "companion.context")! as NSDictionary == goodCache, "Invalid image must preserve disk cache")
            check(try Data(contentsOf: file) == newPayload, "Invalid image must preserve complication file")
        }
        var corrupt = next
        corrupt["data"] = Data("invalid JSON".utf8)
        corrupt["updatedAt"] = timestamp + 3
        deliver(corrupt, to: companion)
        check(defaults.dictionary(forKey: "companion.context")! as NSDictionary == goodCache, "Invalid state must preserve disk cache")

        WCSession.default.receivedApplicationContext = try context(state, timestamp + 4, firstPNG)
        WCSession.default.hasContentPending = true
        let cancelled = Task { await companion.receiveBackgroundUpdates() }
        cancelled.cancel()
        await cancelled.value
        WCSession.default.hasContentPending = false
        check(companion.updatedAt?.timeIntervalSince1970 == timestamp + 2, "Cancelled background drain must not apply pending context")
        check(defaults.dictionary(forKey: "companion.context")! as NSDictionary == goodCache, "Cancelled background drain must preserve cache")

        deliver(try context(UsagiState(), timestamp + 5, firstPNG), to: companion)
        check(companion.state?.profile == nil && companion.characterPNG == nil && companion.characterImage == nil
              && !companion.isCharacterImageStale, "Profile removal must clear image, even with a supplied PNG")
        check(defaults.dictionary(forKey: "companion.context")?["characterPNG"] == nil, "Profile removal must clear persisted PNG")
        let removed = try decoder.decode(WidgetPayload.self, from: Data(contentsOf: file))
        check(!removed.snapshot.hasProfile && removed.characterPNG == nil, "Profile removal must clear complication image")

        defaults.set(fresh, forKey: "companion.context")
        let legacyContext = receiver()
        check(legacyContext.characterPNG == firstPNG && !legacyContext.isCharacterImageStale, "Version-1 contexts without marker stay compatible")
        defaults.removeObject(forKey: "companion.context")
        defaults.set(try encoder.encode(state), forKey: "companion.state")
        defaults.set(timestamp, forKey: "companion.updatedAt")
        defaults.set(firstPNG, forKey: "companion.characterPNG")
        let legacyKeys = receiver()
        check(legacyKeys.characterPNG == firstPNG && !legacyKeys.isCharacterImageStale, "Legacy separate cache keys stay compatible")
        print("Watch receiver: \(checks) checks passed; missing-image retention, relaunch, fresh recovery, invalid data, ordering, cancellation, profile removal and legacy caches.")
    }

    private static func makePNG(red: CGFloat, width: Int = 16) -> Data {
        let image = CGContext(data: nil, width: width, height: 16, bitsPerComponent: 8, bytesPerRow: width * 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        image.setFillColor(CGColor(red: red, green: 0.5, blue: 0.5, alpha: 1))
        image.fill(CGRect(x: 0, y: 0, width: width, height: 16))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
