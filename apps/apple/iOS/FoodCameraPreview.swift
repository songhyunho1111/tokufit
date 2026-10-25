import AVFoundation
import SwiftUI

struct FoodCameraPreview: UIViewRepresentable {
    let controller: FoodCameraController

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.controller = controller
        view.previewLayer?.videoGravity = .resizeAspectFill
        if let layer = view.previewLayer { controller.previewSource.connect(to: layer) }
        view.isAccessibilityElement = true
        view.accessibilityLabel = String(localized: "카메라 미리보기")
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) { view.updateRotation() }

    static func dismantleUIView(_ view: PreviewView, coordinator: ()) { view.previewLayer?.session = nil }

    final class PreviewView: UIView {
        weak var controller: FoodCameraController?
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            updateRotation()
        }

        func updateRotation() {
            let angle: CGFloat
            switch window?.windowScene?.interfaceOrientation {
            case .landscapeLeft: angle = 180
            case .landscapeRight: angle = 0
            case .portraitUpsideDown: angle = 270
            default: angle = 90
            }
            controller?.rotationAngle = angle
            if let connection = previewLayer?.connection, connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }
}
