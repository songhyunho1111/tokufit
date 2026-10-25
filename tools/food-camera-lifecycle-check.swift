// Compile with the unchanged FoodCameraController.swift; only capture hardware is replaced.
import Foundation

struct PreparedFoodPhoto: Sendable, Equatable {
    let jpegData: Data
}

enum FoodPhotoError: Error, LocalizedError, Sendable {
    case cameraAccessDenied, cameraRestricted, cameraUnavailable, cameraInterrupted, cameraCaptureFailed

    var errorDescription: String? { String(describing: self) }
}

struct FoodCameraPreviewSource: Sendable {
    let service: FoodCameraService
}

actor FoodCameraService {
    enum Event: Sendable { case ready(flashAvailable: Bool), failed(FoodPhotoError) }
    typealias EventHandler = @MainActor @Sendable (Event, UInt64) -> Void

    struct CaptureCall: Sendable {
        let generation: UInt64
        let flash: Bool
        let rotationAngle: CGFloat
    }

    nonisolated var previewSource: FoodCameraPreviewSource { .init(service: self) }
    private var starts: [UInt64: CheckedContinuation<Bool, Error>] = [:]
    private var handlers: [UInt64: EventHandler] = [:]
    private var captureContinuation: CheckedContinuation<PreparedFoodPhoto, Error>?
    private(set) var startGenerations: [UInt64] = []
    private(set) var stopGenerations: [UInt64] = []
    private(set) var captures: [CaptureCall] = []

    func start(generation: UInt64, onEvent: @escaping EventHandler) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            starts[generation] = continuation
            handlers[generation] = onEvent
            startGenerations.append(generation)
        }
    }

    func stop(generation: UInt64) { stopGenerations.append(generation) }

    func capture(generation: UInt64, flash: Bool, rotationAngle: CGFloat) async throws -> PreparedFoodPhoto {
        try await withCheckedThrowingContinuation { continuation in
            captureContinuation = continuation
            captures.append(.init(generation: generation, flash: flash, rotationAngle: rotationAngle))
        }
    }

    func finishStart(_ generation: UInt64, with result: Result<Bool, Error>) {
        starts.removeValue(forKey: generation)?.resume(with: result)
    }

    func finishCapture(with result: Result<PreparedFoodPhoto, Error>) {
        let continuation = captureContinuation
        captureContinuation = nil
        continuation?.resume(with: result)
    }

    func emit(_ event: Event, generation: UInt64) async {
        await handlers[generation]?(event, generation)
    }
}

@main @MainActor
enum FoodCameraLifecycleCheck {
    private enum CheckFailure: Error { case failed(String) }
    private static var count = 0
    private static let photo = PreparedFoodPhoto(jpegData: Data([1, 2, 3]))

    static func main() async throws {
        try lifecycleOrdering()
        try await lateStartAfterStop()
        try await oldStartAfterRestart()
        try await lateCaptureAfterStop()
        try await captureFailure()
        try await flashAndCaptureSettings()
        try await eventGenerationFiltering()
        try await cancelledStart()
        try await authorizationErrors()
        print("Food camera lifecycle: \(count) checks passed; reordered intent, stale starts/photos/events, cancellation, errors and flash settings.")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckFailure.failed(message) }
        count += 1
    }

    private static func waitUntil(_ description: String, _ condition: () async -> Bool) async throws {
        for _ in 0..<2_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw CheckFailure.failed("Timed out waiting for \(description)")
    }

    private static func makeReady(flash: Bool = false) async throws -> FoodCameraController {
        let controller = FoodCameraController()
        let service = controller.previewSource.service
        let task = Task { await controller.start() }
        try await waitUntil("initial start") { await service.startGenerations == [1] }
        await service.finishStart(1, with: .success(flash))
        await task.value
        try require(controller.status == .ready, "Start must publish ready")
        return controller
    }

    private static func lifecycleOrdering() throws {
        var lifecycle = FoodCameraLifecycle()
        try require(!lifecycle.accepts(0), "Initial lifecycle must be inactive")
        try require(lifecycle.apply(generation: 3, active: true), "New start must be accepted")
        try require(lifecycle.accepts(3), "Current active generation must be accepted")
        try require(!lifecycle.apply(generation: 2, active: false), "Reordered old stop must be rejected")
        try require(lifecycle.accepts(3), "Old stop must preserve newer start")
        try require(lifecycle.apply(generation: 4, active: false), "New stop must be accepted")
        try require(!lifecycle.accepts(3) && !lifecycle.accepts(4), "Stop must invalidate active generations")
        try require(!lifecycle.apply(generation: 3, active: true), "Late old start must be rejected")
        try require(lifecycle.apply(generation: 5, active: true) && lifecycle.accepts(5), "Fresh restart must work")
    }

    private static func lateStartAfterStop() async throws {
        let controller = FoodCameraController()
        let service = controller.previewSource.service
        let task = Task { await controller.start() }
        try await waitUntil("permission wait") { await service.startGenerations == [1] }
        controller.stop()
        try require(controller.status == .idle, "Stop must immediately publish idle")
        await service.finishStart(1, with: .success(true))
        await task.value
        try require(controller.status == .idle && !controller.isFlashAvailable,
                    "Late permission approval must not revive a stopped camera")
        try await waitUntil("queued stop") { await service.stopGenerations.contains(2) }
        try require(await service.stopGenerations.contains(2), "Stop must reach capture service")
    }

    private static func oldStartAfterRestart() async throws {
        let controller = FoodCameraController()
        let service = controller.previewSource.service
        let oldTask = Task { await controller.start() }
        try await waitUntil("old start") { await service.startGenerations == [1] }
        controller.stop()
        let newTask = Task { await controller.start() }
        try await waitUntil("new start") { await service.startGenerations == [1, 3] }
        await service.finishStart(3, with: .success(false))
        await newTask.value
        await service.finishStart(1, with: .failure(FoodPhotoError.cameraAccessDenied))
        await oldTask.value
        try require(controller.status == .ready && controller.errorMessage == nil,
                    "Old permission denial must not overwrite a newer ready session")
        try require(!controller.isFlashAvailable, "Old start must not overwrite current flash support")
    }

    private static func lateCaptureAfterStop() async throws {
        let controller = try await makeReady()
        let service = controller.previewSource.service
        let task = Task { await controller.capture() }
        try await waitUntil("capture") { await service.captures.count == 1 }
        try require(controller.isCapturing, "Capture must publish progress")
        controller.stop()
        try require(!controller.isCapturing, "Stop must clear capture progress immediately")
        await service.finishCapture(with: .success(photo))
        let result = await task.value
        try require(result == nil && controller.status == .idle, "A late photo must be discarded after stop")
    }

    private static func captureFailure() async throws {
        let controller = try await makeReady()
        let service = controller.previewSource.service
        let task = Task { await controller.capture() }
        try await waitUntil("failing capture") { await service.captures.count == 1 }
        await service.finishCapture(with: .failure(FoodPhotoError.cameraCaptureFailed))
        let result = await task.value
        try require(result == nil && !controller.isCapturing, "Capture error must clear progress and return no photo")
        try require(controller.errorMessage == "cameraCaptureFailed", "Capture error must remain visible")
        try require(controller.status == .ready, "A capture error must leave retry available")
    }

    private static func flashAndCaptureSettings() async throws {
        let unsupported = try await makeReady()
        unsupported.toggleFlash()
        try require(!unsupported.isFlashEnabled, "Unsupported flash must ignore toggle")

        let controller = try await makeReady(flash: true)
        controller.toggleFlash()
        try require(controller.isFlashEnabled, "Supported flash must toggle on")
        controller.rotationAngle = 180
        let service = controller.previewSource.service
        let task = Task { await controller.capture() }
        try await waitUntil("flash capture") { await service.captures.count == 1 }
        controller.toggleFlash()
        try require(controller.isFlashEnabled, "Flash cannot change during capture")
        let capture = await service.captures[0]
        try require(capture.flash && capture.rotationAngle == 180 && capture.generation == 1,
                    "Capture must forward actual flash, rotation and generation")
        await service.finishCapture(with: .success(photo))
        try require(await task.value == photo && !controller.isCapturing, "Successful capture must return photo and clear progress")
        await service.emit(.ready(flashAvailable: false), generation: 1)
        try require(!controller.isFlashEnabled && !controller.isFlashAvailable,
                    "Losing flash availability must disable selected flash")
    }

    private static func eventGenerationFiltering() async throws {
        let controller = try await makeReady(flash: true)
        let service = controller.previewSource.service
        await service.emit(.failed(.cameraInterrupted), generation: 1)
        try require(controller.status == .failed && controller.errorMessage == "cameraInterrupted",
                    "Current interruption must be visible")
        await service.emit(.ready(flashAvailable: true), generation: 1)
        try require(controller.status == .ready && controller.errorMessage == nil,
                    "Current recovery must clear interruption error")
        controller.stop()
        await service.emit(.ready(flashAvailable: true), generation: 1)
        try require(controller.status == .idle && !controller.isFlashAvailable,
                    "Old ready event cannot reactivate a stopped controller")
        await service.emit(.failed(.cameraCaptureFailed), generation: 1)
        try require(controller.status == .idle && controller.errorMessage == nil,
                    "Old failed event cannot dirty a stopped controller")
    }

    private static func cancelledStart() async throws {
        let controller = FoodCameraController()
        let service = controller.previewSource.service
        let task = Task { await controller.start() }
        try await waitUntil("cancelable start") { await service.startGenerations == [1] }
        task.cancel()
        await service.finishStart(1, with: .success(true))
        await task.value
        try require(controller.status == .idle && !controller.isFlashAvailable,
                    "Canceled start must not publish ready after permission completes")
        try await waitUntil("cancellation stop") { await service.stopGenerations.contains(2) }
        try require(await service.stopGenerations.contains(2), "Canceled start must stop the service")
    }

    private static func authorizationErrors() async throws {
        let cases: [(FoodPhotoError, FoodCameraController.Status)] = [
            (.cameraAccessDenied, .denied), (.cameraRestricted, .restricted), (.cameraUnavailable, .unavailable),
        ]
        for (error, expectedStatus) in cases {
            let controller = FoodCameraController()
            let service = controller.previewSource.service
            let task = Task { await controller.start() }
            try await waitUntil("authorization error") { await service.startGenerations == [1] }
            await service.finishStart(1, with: .failure(error))
            await task.value
            try require(controller.status == expectedStatus && controller.errorMessage != nil,
                        "Authorization/hardware failure must preserve its recovery state")
            try require(!controller.isFlashAvailable, "Failed camera cannot expose supported flash")
        }
    }
}
