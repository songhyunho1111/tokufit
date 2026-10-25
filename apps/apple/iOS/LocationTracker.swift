import CoreLocation
import Foundation
import Observation

@Observable
@MainActor
final class LocationTracker: NSObject, CLLocationManagerDelegate {
    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var heading: Double?
    private(set) var headingSource = String(localized: "방향을 기다리고 있어요")
    private(set) var isWalking = false
    private(set) var isTracking = false
    private(set) var status = String(localized: "위치 확인 전")
    private(set) var authorization: CLAuthorizationStatus = .notDetermined

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var wantsUpdates = false
    @ObservationIgnored private var walkingExpiry: Task<Void, Never>?
    @ObservationIgnored private var compassTimestamp: Date?
    @ObservationIgnored private var previousLocation: CLLocation?
    @ObservationIgnored private var latestLocationTimestamp: Date?

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        manager.headingFilter = 5
        manager.headingOrientation = .portrait
        manager.delegate = self
        authorization = manager.authorizationStatus
    }

    func start() {
        guard !isTracking else { return }
        wantsUpdates = true
        authorization = manager.authorizationStatus
        if authorization == .notDetermined {
            status = String(localized: "위치 접근 허용을 기다리고 있어요")
            manager.requestWhenInUseAuthorization()
        } else {
            updateAuthorization(authorization)
        }
    }

    func stop() {
        wantsUpdates = false
        isTracking = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        compassTimestamp = nil
        previousLocation = nil
        latestLocationTimestamp = nil
        if heading != nil { headingSource = String(localized: "마지막 확인 방향") }
        walkingExpiry?.cancel()
        walkingExpiry = nil
        isWalking = false
        status = String(localized: "산책을 멈췄어요 · 마지막 위치")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let authorization = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.updateAuthorization(authorization)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        let accuracy = location.horizontalAccuracy
        let speed = location.speed
        let course = location.course
        let timestamp = location.timestamp
        Task { @MainActor [weak self] in
            self?.acceptLocation(latitude: latitude, longitude: longitude, accuracy: accuracy,
                                 speed: speed, course: course, timestamp: timestamp)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let trueHeading = newHeading.trueHeading
        let magneticHeading = newHeading.magneticHeading
        let accuracy = newHeading.headingAccuracy
        let timestamp = newHeading.timestamp
        Task { @MainActor [weak self] in
            guard let self, self.isTracking,
                  HeadingMath.isValidReading(accuracy: accuracy, timestamp: timestamp, now: Date()) else { return }
            let value = HeadingMath.preferredReading(trueHeading: trueHeading, magneticHeading: magneticHeading)
            guard let value else { return }
            if let previousTimestamp = self.compassTimestamp, timestamp <= previousTimestamp { return }
            self.compassTimestamp = timestamp
            self.updateHeading(value, source: String(localized: "바라보는 방향"))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let denied = (error as? CLError)?.code == .denied
        Task { @MainActor [weak self] in
            guard let self, self.wantsUpdates else { return }
            self.isWalking = false
            if denied {
                self.stop()
                self.coordinate = nil
                self.heading = nil
                self.headingSource = String(localized: "위치 권한이 필요해요")
                self.status = String(localized: "위치 접근이 꺼져 있어요 · 설정에서 허용해 주세요")
            } else {
                self.status = String(localized: "GPS 신호를 찾고 있어요 · 마지막 위치")
            }
        }
    }

    private func updateAuthorization(_ value: CLAuthorizationStatus) {
        authorization = value
        switch value {
        case .authorizedAlways, .authorizedWhenInUse:
            if wantsUpdates {
                status = String(localized: "현재 위치를 찾고 있어요")
                isTracking = true
                manager.startUpdatingLocation()
                if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
            }
        case .denied, .restricted:
            stop()
            coordinate = nil
            heading = nil
            headingSource = String(localized: "위치 권한이 필요해요")
            status = String(localized: "위치 접근이 꺼져 있어요 · 설정에서 허용해 주세요")
        case .notDetermined:
            break
        @unknown default:
            stop()
            status = String(localized: "위치 권한 상태를 확인할 수 없어요")
        }
    }

    private func acceptLocation(latitude: Double, longitude: Double, accuracy: Double,
                                speed: Double, course: Double, timestamp: Date) {
        guard wantsUpdates, isTracking else { return }
        guard latitude.isFinite, longitude.isFinite, accuracy.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude),
              (0...65).contains(accuracy), abs(timestamp.timeIntervalSinceNow) <= 30 else {
            isWalking = false
            status = String(localized: "정확한 GPS 신호를 기다리고 있어요")
            return
        }
        let currentCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let currentLocation = CLLocation(coordinate: currentCoordinate, altitude: 0,
                                         horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: timestamp)
        if let latestLocationTimestamp, timestamp <= latestLocationTimestamp { return }
        latestLocationTimestamp = timestamp
        var movementBearing: Double?
        var estimatedSpeed: Double?
        var shouldMoveAnchor = previousLocation == nil
        if let previousLocation, previousLocation.horizontalAccuracy <= 25, accuracy <= 25 {
            let interval = timestamp.timeIntervalSince(previousLocation.timestamp)
            let distance = currentLocation.distance(from: previousLocation)
            let minimumDistance = max(3, (accuracy + previousLocation.horizontalAccuracy) / 2)
            if (1...30).contains(interval), distance.isFinite, distance >= minimumDistance {
                movementBearing = HeadingMath.bearing(
                    fromLatitude: previousLocation.coordinate.latitude,
                    fromLongitude: previousLocation.coordinate.longitude,
                    toLatitude: latitude, toLongitude: longitude
                )
                estimatedSpeed = distance / interval
                shouldMoveAnchor = true
            }
            if interval > 30 { shouldMoveAnchor = true }
        } else {
            shouldMoveAnchor = true
        }
        // Accumulate a reliable displacement instead of deriving direction from GPS jitter.
        if shouldMoveAnchor { previousLocation = currentLocation }
        coordinate = currentCoordinate
        let movementSpeed = speed.isFinite && speed >= 0 ? speed : estimatedSpeed
        isWalking = movementSpeed.map { (0.3...3.5).contains($0) } ?? false
        let compassIsFresh = compassTimestamp.map { (0...15).contains(Date().timeIntervalSince($0)) } ?? false
        if !compassIsFresh, let movementSpeed, movementSpeed >= 0.3 {
            if course.isFinite, (0..<360).contains(course) {
                updateHeading(course, source: String(localized: "이동하는 방향"))
            } else if let movementBearing {
                updateHeading(movementBearing, source: String(localized: "이동하는 방향"))
            }
        }
        status = String(localized: "현재 위치 · 산책 중")
        walkingExpiry?.cancel()
        walkingExpiry = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(10))
                self?.isWalking = false
            } catch {
                // A newer location or a stopped walk cancels the previous motion timer.
            }
        }
    }

    private func updateHeading(_ value: Double, source: String) {
        heading = HeadingMath.smoothed(current: heading, toward: value)
        headingSource = source
    }
}

enum HeadingMath {
    nonisolated static func normalized(_ degrees: Double) -> Double? {
        guard degrees.isFinite else { return nil }
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    nonisolated static func preferredReading(trueHeading: Double, magneticHeading: Double) -> Double? {
        if trueHeading.isFinite, (0..<360).contains(trueHeading) { return trueHeading }
        guard magneticHeading.isFinite, (0..<360).contains(magneticHeading) else { return nil }
        return magneticHeading
    }

    nonisolated static func isValidReading(accuracy: Double, timestamp: Date, now: Date) -> Bool {
        accuracy.isFinite && (0...45).contains(accuracy) && abs(timestamp.timeIntervalSince(now)) <= 10
    }

    nonisolated static func smoothed(current: Double?, toward target: Double) -> Double? {
        guard let target = normalized(target) else { return current }
        guard let current, let start = normalized(current) else { return target }
        let delta = (target - start + 540).truncatingRemainder(dividingBy: 360) - 180
        return normalized(start + delta * 0.35)
    }

    nonisolated static func bearing(fromLatitude: Double, fromLongitude: Double,
                                    toLatitude: Double, toLongitude: Double) -> Double? {
        guard [fromLatitude, fromLongitude, toLatitude, toLongitude].allSatisfy(\.isFinite),
              (-90...90).contains(fromLatitude), (-90...90).contains(toLatitude),
              (-180...180).contains(fromLongitude), (-180...180).contains(toLongitude),
              fromLatitude != toLatitude || fromLongitude != toLongitude else { return nil }
        let latitude1 = fromLatitude * .pi / 180
        let latitude2 = toLatitude * .pi / 180
        let longitudeDelta = (toLongitude - fromLongitude) * .pi / 180
        let y = sin(longitudeDelta) * cos(latitude2)
        let x = cos(latitude1) * sin(latitude2) - sin(latitude1) * cos(latitude2) * cos(longitudeDelta)
        guard abs(x) > 1e-12 || abs(y) > 1e-12 else { return nil }
        return normalized(atan2(y, x) * 180 / .pi)
    }
}
