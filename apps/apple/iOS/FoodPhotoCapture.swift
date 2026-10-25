import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct FoodPhotoCapture: UIViewControllerRepresentable {
    let onComplete: (Result<PreparedFoodPhoto?, Error>) -> Void

    static func requestAccess() async throws {
        try Task.checkCancellation()
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { throw FoodPhotoError.cameraUnavailable }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            try Task.checkCancellation()
            guard granted else { throw FoodPhotoError.cameraAccessDenied }
        case .denied: throw FoodPhotoError.cameraAccessDenied
        case .restricted: throw FoodPhotoError.cameraRestricted
        @unknown default: throw FoodPhotoError.cameraRestricted
        }
    }

    func makeUIViewController(context: Context) -> UIViewController {
        guard UIImagePickerController.isSourceTypeAvailable(.camera),
              AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            Task { @MainActor in
                let error: FoodPhotoError = UIImagePickerController.isSourceTypeAvailable(.camera)
                    ? .cameraAccessDenied : .cameraUnavailable
                onComplete(.failure(error))
            }
            return UIViewController()
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onComplete: (Result<PreparedFoodPhoto?, Error>) -> Void

        init(onComplete: @escaping (Result<PreparedFoodPhoto?, Error>) -> Void) { self.onComplete = onComplete }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onComplete(.success(nil)) }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage else {
                onComplete(.failure(FoodPhotoError.invalidImage))
                return
            }
            do { onComplete(.success(try FoodPhotoPreparation.prepare(cameraImage: image))) }
            catch { onComplete(.failure(error)) }
        }
    }
}
