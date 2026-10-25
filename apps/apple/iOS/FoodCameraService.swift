import Foundation
// Apple's AVCam uses this bridge for its non-Sendable session: only the actor mutates
// capture state; the MainActor preview source only attaches that session to a layer.
@preconcurrency import AVFoundation

struct FoodCameraPreviewSource: Sendable {
    private let session: AVCaptureSession

    init(session: AVCaptureSession) { self.session = session }

    @MainActor
    func connect(to layer: AVCaptureVideoPreviewLayer) { layer.session = session }
}

actor FoodCameraService {
    enum Event: Sendable { case ready(flashAvailable: Bool), failed(FoodPhotoError) }
    typealias EventHandler = @MainActor @Sendable (Event, UInt64) -> Void

    nonisolated let previewSource: FoodCameraPreviewSource
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var lifecycle = FoodCameraLifecycle()
    private var onEvent: EventHandler?
    private var observers: [NSObjectProtocol] = []
    private var flashObservation: NSKeyValueObservation?
    private var captureID: UUID?
    private var continuation: CheckedContinuation<Data, Error>?
    private var photoDelegates: [UUID: FoodCameraPhotoDelegate] = [:]

    init() { previewSource = FoodCameraPreviewSource(session: session) }

    func start(generation: UInt64, onEvent: @escaping EventHandler) async throws -> Bool {
        try Task.checkCancellation()
        guard lifecycle.apply(generation: generation, active: true) else { throw CancellationError() }
        self.onEvent = onEvent
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied: throw FoodPhotoError.cameraAccessDenied
        case .restricted: throw FoodPhotoError.cameraRestricted
        case .authorized, .notDetermined: break
        @unknown default: throw FoodPhotoError.cameraRestricted
        }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw FoodPhotoError.cameraUnavailable
        }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            try Task.checkCancellation()
            guard lifecycle.accepts(generation) else { throw CancellationError() }
            guard granted else { throw FoodPhotoError.cameraAccessDenied }
        }
        try Task.checkCancellation()
        guard lifecycle.accepts(generation) else { throw CancellationError() }
        try configure(camera)
        observeSession(generation: generation)
        if !session.isRunning { session.startRunning() }
        guard session.isRunning, !session.isInterrupted else { throw FoodPhotoError.cameraInterrupted }
        return flashAvailable
    }

    func stop(generation: UInt64) {
        guard lifecycle.apply(generation: generation, active: false) else { return }
        cancelCapture()
        removeObservers()
        onEvent = nil
        if session.isRunning { session.stopRunning() }
    }

    func capture(generation: UInt64, flash: Bool, rotationAngle: CGFloat) async throws -> PreparedFoodPhoto {
        try Task.checkCancellation()
        guard lifecycle.accepts(generation) else { throw CancellationError() }
        guard session.isRunning, !session.isInterrupted, continuation == nil, photoDelegates.isEmpty else {
            throw FoodPhotoError.cameraInterrupted
        }
        let id = UUID()
        let data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.captureID = id
                self.continuation = continuation
                let settings = AVCapturePhotoSettings()
                settings.flashMode = flash && flashAvailable ? .on : .off
                if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(rotationAngle) {
                    connection.videoRotationAngle = rotationAngle
                }
                let delegate = FoodCameraPhotoDelegate { [weak self] result in
                    Task { await self?.finishCapture(id: id, result: result) }
                }
                photoDelegates[id] = delegate
                output.capturePhoto(with: settings, delegate: delegate)
            }
        } onCancel: {
            Task { await self.cancelCapture(id: id) }
        }
        try Task.checkCancellation()
        guard lifecycle.accepts(generation) else { throw CancellationError() }
        return try FoodPhotoPreparation.prepare(data: data)
    }

    private var flashAvailable: Bool {
        device?.hasFlash == true && device?.isFlashAvailable == true && output.supportedFlashModes.contains(.on)
    }

    private func configure(_ camera: AVCaptureDevice) throws {
        guard device == nil else { return }
        let input = try AVCaptureDeviceInput(device: camera)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input) else { throw FoodPhotoError.cameraUnavailable }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            throw FoodPhotoError.cameraUnavailable
        }
        session.addOutput(output)
        device = camera
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        flashObservation = nil
    }

    private func observeSession(generation: UInt64) {
        removeObservers()
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] _ in
                Task { await self?.interrupted(generation: generation) }
            },
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
                Task { await self?.resumeIfActive(generation: generation) }
            },
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] _ in
                Task { await self?.runtimeFailed(generation: generation) }
            },
        ]
        flashObservation = device?.observe(\.isFlashAvailable) { [weak self] _, _ in
            Task { await self?.publishReadiness(generation: generation) }
        }
    }

    private func interrupted(generation: UInt64) async {
        guard lifecycle.accepts(generation) else { return }
        cancelCapture()
        await onEvent?(.failed(.cameraInterrupted), generation)
    }

    private func runtimeFailed(generation: UInt64) async {
        guard lifecycle.accepts(generation) else { return }
        cancelCapture()
        await onEvent?(.failed(.cameraCaptureFailed), generation)
    }

    private func resumeIfActive(generation: UInt64) async {
        guard lifecycle.accepts(generation) else { return }
        if !session.isRunning { session.startRunning() }
        await publishReadiness(generation: generation)
    }

    private func publishReadiness(generation: UInt64) async {
        guard lifecycle.accepts(generation), session.isRunning, !session.isInterrupted else { return }
        await onEvent?(.ready(flashAvailable: flashAvailable), generation)
    }

    private func finishCapture(id: UUID, result: Result<Data, FoodPhotoError>) {
        photoDelegates[id] = nil
        guard captureID == id else { return }
        let continuation = continuation
        self.continuation = nil
        captureID = nil
        continuation?.resume(with: result.mapError { $0 as Error })
    }

    private func cancelCapture(id: UUID? = nil) {
        if let id, captureID != id { return }
        let continuation = continuation
        self.continuation = nil
        captureID = nil
        continuation?.resume(throwing: CancellationError())
    }
}

private final class FoodCameraPhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let lock = NSLock()
    private var result: Result<Data, FoodPhotoError> = .failure(.invalidImage)
    private let onFinish: @Sendable (Result<Data, FoodPhotoError>) -> Void

    init(onFinish: @escaping @Sendable (Result<Data, FoodPhotoError>) -> Void) { self.onFinish = onFinish }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let result: Result<Data, FoodPhotoError>
        if error != nil { result = .failure(.cameraCaptureFailed) }
        else if let data = photo.fileDataRepresentation() { result = .success(data) }
        else { result = .failure(.invalidImage) }
        lock.withLock { self.result = result }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        onFinish(error == nil ? lock.withLock { result } : .failure(.cameraCaptureFailed))
    }
}
