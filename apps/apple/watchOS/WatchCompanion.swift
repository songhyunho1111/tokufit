import Foundation
import Observation
import REPickShared
import WatchConnectivity
import UIKit

@MainActor
@Observable
final class WatchCompanion: NSObject {
    private(set) var state: UsagiState?
    private(set) var updatedAt: Date?
    private(set) var isReachable = false
    private(set) var errorMessage: String?
    private(set) var complicationError: String?
    private(set) var characterPNG: Data?
    private(set) var characterImage: UIImage?
    private(set) var isCharacterImageStale = false
    private(set) var workoutMinutesToday = 0

    private let defaults: UserDefaults
    let session: WCSession?
    private let complication: WatchComplicationPublisher

    override convenience init() {
        self.init(defaults: .standard)
    }

    init(defaults: UserDefaults, complication: WatchComplicationPublisher = WatchComplicationPublisher()) {
        self.defaults = defaults
        self.complication = complication
        session = WCSession.isSupported() ? .default : nil
        super.init()
        if let context = defaults.dictionary(forKey: "companion.context") {
            receiveContext(context)
        } else if let data = defaults.data(forKey: "companion.state"),
           let timestamp = defaults.object(forKey: "companion.updatedAt") as? Double {
            receive(data: data, timestamp: timestamp, characterPNG: defaults.data(forKey: "companion.characterPNG"), workoutMinutesToday: nil, persist: false)
        }
    }

    func activate() {
        guard let session else {
            errorMessage = String(localized: "iPhone 연결을 지원하지 않는 기기예요.")
            return
        }
        session.delegate = self
        session.activate()
    }

    func refreshConnection() {
        guard let session else { return }
        isReachable = session.isReachable
        receiveContext(session.receivedApplicationContext)
    }

    private func receiveContext(_ context: [String: Any]) {
        guard let version = context["version"] as? Int, version == 1,
              let data = context["data"] as? Data,
              let timestamp = context["updatedAt"] as? Double,
              context["isCharacterImageStale"] == nil || context["isCharacterImageStale"] is Bool,
              context["workoutMinutesToday"] == nil || context["workoutMinutesToday"] is Int else { return }
        receive(data: data, timestamp: timestamp, characterPNG: context["characterPNG"] as? Data,
                workoutMinutesToday: context["workoutMinutesToday"] as? Int,
                isCharacterImageStale: context["isCharacterImageStale"] as? Bool ?? false, persist: true)
    }

    private func receive(data: Data, timestamp: Double, characterPNG: Data?, workoutMinutesToday: Int?,
                         isCharacterImageStale: Bool = false, persist: Bool) {
        guard data.count <= 500_000, timestamp.isFinite, timestamp > 0,
              workoutMinutesToday.map({ (0...288_000).contains($0) }) ?? true,
              timestamp <= Date().addingTimeInterval(5 * 60).timeIntervalSince1970 else {
            errorMessage = String(localized: "우사기 정보를 읽지 못했어요. iPhone 앱을 다시 열어 주세요.")
            return
        }
        if let updatedAt, timestamp < updatedAt.timeIntervalSince1970 { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(UsagiState.self, from: data)
            try snapshot.validate()
            try WatchComplicationPublisher.validateImage(characterPNG)
            let retainedPNG = snapshot.profile == nil ? nil : (characterPNG ?? self.characterPNG)
            state = snapshot
            if self.characterPNG != retainedPNG {
                characterImage = retainedPNG.flatMap(WatchCharacterImage.prepare)
                self.characterPNG = retainedPNG
            }
            self.isCharacterImageStale = retainedPNG != nil && (characterPNG == nil || isCharacterImageStale)
            self.workoutMinutesToday = workoutMinutesToday ?? snapshot.workoutMinutesToday
            updatedAt = Date(timeIntervalSince1970: timestamp)
            errorMessage = nil
            if persist {
                var context: [String: Any] = ["version": 1, "data": data, "updatedAt": timestamp,
                                              "workoutMinutesToday": self.workoutMinutesToday,
                                              "isCharacterImageStale": self.isCharacterImageStale]
                context["characterPNG"] = retainedPNG
                defaults.set(context, forKey: "companion.context")
            }
            // Keep the complication's original timestamp and metrics until its image is current too.
            guard snapshot.profile == nil || (characterPNG != nil && !isCharacterImageStale) else { return }
            do {
                try complication.publish(state: snapshot, updatedAt: Date(timeIntervalSince1970: timestamp), characterPNG: retainedPNG)
                complicationError = nil
            } catch {
                complicationError = String(localized: "워치페이스를 갱신하지 못했어요. 앱을 다시 열어 주세요.")
            }
        } catch {
            errorMessage = String(localized: "우사기 정보를 읽지 못했어요. iPhone 앱을 다시 열어 주세요.")
        }
    }
}

extension WatchCompanion: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        let failed = error != nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            if failed {
                self.errorMessage = String(localized: "iPhone에 연결하지 못했어요. 다시 시도해 주세요.")
            }
            self.refreshConnection()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.refreshConnection() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let version = applicationContext["version"] as? Int, version == 1,
              let data = applicationContext["data"] as? Data,
              let timestamp = applicationContext["updatedAt"] as? Double,
              applicationContext["workoutMinutesToday"] == nil || applicationContext["workoutMinutesToday"] is Int else { return }
        let characterPNG = applicationContext["characterPNG"] as? Data
        let workoutMinutesToday = applicationContext["workoutMinutesToday"] as? Int
        Task { @MainActor [weak self] in
            self?.receive(data: data, timestamp: timestamp, characterPNG: characterPNG,
                          workoutMinutesToday: workoutMinutesToday, persist: true)
        }
    }
}
