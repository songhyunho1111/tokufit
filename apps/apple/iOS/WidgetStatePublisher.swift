import Foundation
import Observation
import REPickShared
import UIKit
import WidgetKit

@Observable @MainActor
final class WidgetStatePublisher {
    private(set) var status = String(localized: "위젯 대기 중")
    @ObservationIgnored private var cachedAppearance: Appearance?
    @ObservationIgnored private var cachedPNG: Data?
    @ObservationIgnored private var lastWrite: Date?
    @ObservationIgnored private var lastMetrics: Metrics?
    @ObservationIgnored private var lastReload: Date?

    func publish(_ state: UsagiState, forceReload: Bool = false) {
        guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetStorage.appGroup) else {
            status = String(localized: "위젯 저장 공간을 사용할 수 없습니다. 앱 서명 설정을 확인하세요.")
            return
        }
        do {
            try state.validate()
            let appearance = Appearance(state: state)
            let appearanceChanged = appearance != cachedAppearance
            let metrics = Metrics(state: state)
            let now = Date()
            if !forceReload, !appearanceChanged, metrics == lastMetrics, let lastWrite, now.timeIntervalSince(lastWrite) < 30 { return }
            if appearanceChanged {
                guard UIApplication.shared.applicationState != .background else {
                    status = String(localized: "앱을 다시 열면 위젯 모습이 갱신됩니다.")
                    return
                }
                if state.profile != nil {
                    guard let image = UsagiSnapshotRenderer.render(state: state, size: CGSize(width: 512, height: 640), motion: .idle, time: 0),
                          let data = image.pngData() else {
                        status = String(localized: "위젯 이미지를 만들지 못했습니다.")
                        return
                    }
                    cachedPNG = data
                } else {
                    cachedPNG = nil
                }
                cachedAppearance = appearance
            }
            let payload = try WidgetPayload(snapshot: WidgetSnapshot(state: state, now: now), characterPNG: cachedPNG)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)
            guard data.count <= WidgetStorage.maximumPayloadBytes else { throw WidgetPayloadError.invalidImage }
            try data.write(to: directory.appending(path: WidgetStorage.filename), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            lastWrite = now
            lastMetrics = metrics
            if forceReload || appearanceChanged || lastReload == nil || now.timeIntervalSince(lastReload ?? .distantPast) >= 60 {
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetStorage.kind)
                lastReload = now
            }
            status = String(localized: "위젯 업데이트 요청됨")
        } catch {
            status = String(localized: "위젯 데이터를 저장하지 못했습니다. 다음 변경 때 다시 시도합니다.")
        }
    }

    private struct Metrics: Equatable {
        let day: String
        let goal: Int
        let points: Int
        let name: String
        let workoutMode: WorkoutMode?
        init(state: UsagiState) {
            day = state.daily.day
            goal = state.daily.goalSteps
            points = state.points
            name = state.preferences.name
            workoutMode = state.activeWorkout?.mode
        }
    }

    private struct Appearance: Equatable {
        let hasProfile: Bool
        let bodyScale: Double
        let outfit: Outfit
        let waterML: Int
        let character: CharacterKind
        let items: [WardrobeItem]
        let muscleLevel: Double
        let fieryEyes: Bool
        let nutritionMood: NutritionMood
        let costume: CostumeStyle?

        init(state: UsagiState) {
            hasProfile = state.profile != nil
            bodyScale = state.bodyScale
            outfit = state.equippedOutfit
            waterML = state.daily.waterML
            character = state.preferences.character
            items = state.equippedItems
            muscleLevel = state.muscleLevel
            fieryEyes = state.attendanceNeedsAttention
            nutritionMood = state.nutritionMood
            costume = state.currentCostume
        }
    }
}
