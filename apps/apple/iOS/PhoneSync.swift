import Foundation
import Observation
import REPickShared
import UIKit
import WatchConnectivity

@Observable @MainActor
final class PhoneSync: NSObject, WCSessionDelegate {
    private(set) var status = String(localized: "Watch 연결 중")
    private var latest: UsagiState?
    private let session: WCSession?
    private var cachedAppearance: Appearance?
    private var cachedPNG: Data?

    override init() {
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func publish(_ state: UsagiState) {
        latest = state
        guard let session, session.activationState == .activated else { return }
        guard session.isPaired, session.isWatchAppInstalled else {
            status = String(localized: "Watch 앱 설치 필요")
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var context: [String: Any] = [
                "version": 1,
                "data": try encoder.encode(state.watchSnapshot()),
                "updatedAt": Date().timeIntervalSince1970,
                "workoutMinutesToday": state.workoutMinutesToday
            ]
            if let png = characterPNG(for: state) {
                context["characterPNG"] = png
                // Keep the image optional so it cannot crowd out the existing state transfer.
                let size = try PropertyListSerialization.data(fromPropertyList: context, format: .binary, options: 0).count
                if size > 128 * 1_024 { context.removeValue(forKey: "characterPNG") }
            }
            try session.updateApplicationContext(context)
            status = String(localized: "Watch 동기화 대기 중")
        } catch {
            status = String(localized: "Watch 동기화 실패 · 연결 후 재시도")
        }
    }

    private func characterPNG(for state: UsagiState) -> Data? {
        let appearance = Appearance(bodyScale: state.bodyScale, outfit: state.equippedOutfit,
                                    waterML: state.daily.waterML, hasProfile: state.profile != nil,
                                    character: state.preferences.character, items: state.equippedItems,
                                    workoutMode: state.activeWorkout?.mode)
        if cachedAppearance == appearance { return cachedPNG }
        guard state.profile != nil, UIApplication.shared.applicationState != .background else { return nil }
        for size in [CGSize(width: 320, height: 400), CGSize(width: 160, height: 200)] {
            if let image = UsagiSnapshotRenderer.render(state: state, size: size,
                                                        motion: state.activeWorkout?.mode == .indoor ? .exercising : .idle),
               let png = image.pngData(), png.count <= 96 * 1_024 {
                cachedAppearance = appearance
                cachedPNG = png
                return png
            }
        }
        return nil
    }

    private struct Appearance: Equatable {
        let bodyScale: Double
        let outfit: Outfit
        let waterML: Int
        let hasProfile: Bool
        let character: CharacterKind
        let items: [WardrobeItem]
        let workoutMode: WorkoutMode?
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        let succeeded = error == nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            if succeeded, let latest { publish(latest) }
            else if !succeeded { status = String(localized: "Watch 연결 실패") }
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            if let self, let latest = self.latest { self.publish(latest) }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            if let self, let latest = self.latest { self.publish(latest) }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
