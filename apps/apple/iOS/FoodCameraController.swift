import Foundation
import Observation

@Observable @MainActor
final class FoodCameraController {
    enum Status { case idle, starting, ready, unavailable, denied, restricted, failed }

    private(set) var status: Status = .idle
    private(set) var errorMessage: String?
    private(set) var isCapturing = false
    private(set) var isFlashAvailable = false
    private(set) var isFlashEnabled = false
    var rotationAngle: CGFloat = 90

    private let service = FoodCameraService()
    private var generation: UInt64 = 0

    var previewSource: FoodCameraPreviewSource { service.previewSource }

    func start() async {
        guard status != .ready, status != .starting else { return }
        generation += 1
        let current = generation
        status = .starting
        errorMessage = nil
        do {
            let flashAvailable = try await service.start(generation: current) { [weak self] event, generation in
                guard let self, self.generation == generation else { return }
                switch event {
                case .ready(let flashAvailable):
                    self.status = .ready
                    self.errorMessage = nil
                    self.updateFlashAvailability(flashAvailable)
                case .failed(let error):
                    self.show(error)
                }
            }
            try Task.checkCancellation()
            guard generation == current else { return }
            status = .ready
            updateFlashAvailability(flashAvailable)
        } catch is CancellationError {
            if generation == current { stop() }
        } catch {
            guard generation == current else { return }
            show(error)
        }
    }

    func stop() {
        generation += 1
        let current = generation
        status = .idle
        errorMessage = nil
        isCapturing = false
        isFlashAvailable = false
        let service = service
        Task { await service.stop(generation: current) }
    }

    func toggleFlash() {
        guard status == .ready, isFlashAvailable, !isCapturing else { return }
        isFlashEnabled.toggle()
    }

    func capture() async -> PreparedFoodPhoto? {
        guard status == .ready, !isCapturing else { return nil }
        let current = generation
        isCapturing = true
        errorMessage = nil
        defer { if generation == current { isCapturing = false } }
        do {
            let photo = try await service.capture(generation: current, flash: isFlashEnabled,
                                                  rotationAngle: rotationAngle)
            try Task.checkCancellation()
            guard generation == current else { return nil }
            return photo
        } catch is CancellationError {
            return nil
        } catch {
            guard generation == current else { return nil }
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func updateFlashAvailability(_ available: Bool) {
        isFlashAvailable = available
        if !available { isFlashEnabled = false }
    }

    private func show(_ error: Error) {
        switch error {
        case FoodPhotoError.cameraAccessDenied: status = .denied
        case FoodPhotoError.cameraRestricted: status = .restricted
        case FoodPhotoError.cameraUnavailable: status = .unavailable
        default: status = .failed
        }
        isFlashAvailable = false
        errorMessage = error.localizedDescription
    }

    deinit {
        let service = service
        Task { await service.stop(generation: .max) }
    }
}

// Both delayed permission replies and queued stop tasks must respect the newest UI intent.
struct FoodCameraLifecycle {
    private(set) var generation: UInt64 = 0
    private(set) var isActive = false

    mutating func apply(generation: UInt64, active: Bool) -> Bool {
        guard generation >= self.generation else { return false }
        self.generation = generation
        isActive = active
        return true
    }

    func accepts(_ generation: UInt64) -> Bool { isActive && self.generation == generation }
}
