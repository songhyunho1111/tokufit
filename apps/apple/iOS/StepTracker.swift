import CoreMotion
import Foundation
import Observation

@Observable
@MainActor
final class StepTracker {
    private(set) var steps = 0
    private(set) var status = String(localized: "걸음 수 연동 전")
    private(set) var isAvailable = CMPedometer.isStepCountingAvailable()
    private(set) var isTracking = false

    @ObservationIgnored private let pedometer = CMPedometer()
    @ObservationIgnored private var generation: UUID?
    @ObservationIgnored private var trackingDay: Date?

    var trackingDate: Date? { trackingDay }

    func start() {
        let day = Calendar.current.startOfDay(for: Date())
        guard !isTracking || trackingDay != day else { return }
        stop()
        isAvailable = CMPedometer.isStepCountingAvailable()
        guard isAvailable else {
            status = String(localized: "이 기기에서는 걸음 수를 측정할 수 없어요")
            return
        }
        switch CMPedometer.authorizationStatus() {
        case .denied, .restricted:
            status = String(localized: "설정에서 동작 및 피트니스 접근을 허용해 주세요")
            return
        case .authorized, .notDetermined:
            break
        @unknown default:
            status = String(localized: "걸음 수 접근 상태를 확인할 수 없어요")
            return
        }
        if trackingDay != day { steps = 0 }
        trackingDay = day
        let currentGeneration = UUID()
        generation = currentGeneration
        isTracking = true
        status = String(localized: "걸음 수 불러오는 중")

        pedometer.queryPedometerData(from: day, to: Date()) { [weak self] data, error in
            let count = data?.numberOfSteps.intValue
            let failed = error != nil
            Task { @MainActor [weak self] in
                self?.receive(count: count, failed: failed, generation: currentGeneration, day: day)
            }
        }
        pedometer.startUpdates(from: day) { [weak self] data, error in
            let count = data?.numberOfSteps.intValue
            let failed = error != nil
            Task { @MainActor [weak self] in
                self?.receive(count: count, failed: failed, generation: currentGeneration, day: day)
            }
        }
    }

    func stop() {
        generation = nil
        isTracking = false
        pedometer.stopUpdates()
    }

    private func receive(count: Int?, failed: Bool, generation callbackGeneration: UUID, day: Date) {
        guard generation == callbackGeneration, isTracking else { return }
        guard Calendar.current.isDateInToday(day) else {
            stop()
            status = String(localized: "날짜가 바뀌었습니다 · 걸음 수를 다시 연결하세요")
            return
        }
        guard !failed, let count, count >= 0 else {
            stop()
            if CMPedometer.authorizationStatus() == .denied || CMPedometer.authorizationStatus() == .restricted {
                status = String(localized: "설정에서 동작 및 피트니스 접근을 허용해 주세요")
            } else {
                status = String(localized: "걸음 수를 불러오지 못했어요 · 다시 연결해 주세요")
            }
            return
        }
        // History and live callbacks can arrive out of order; today's total never goes backwards.
        steps = max(steps, count)
        status = String(localized: "걸음 수 연동 중")
    }
}
