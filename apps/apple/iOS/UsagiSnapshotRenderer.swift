import Metal
import REPickShared
import SceneKit
import UIKit

@MainActor
enum UsagiSnapshotRenderer {
    static func render(
        state: UsagiState,
        size: CGSize,
        motion: UsagiMotion = .idle,
        time: TimeInterval = 0
    ) -> UIImage? {
        guard size.width.isFinite, size.height.isFinite,
              (1...2_048).contains(size.width), (1...2_048).contains(size.height),
              time.isFinite, time >= 0,
              (try? state.validate()) != nil,
              let device = MTLCreateSystemDefaultDevice() else { return nil }
        let model = MapUsagiView.Coordinator()
        let animated = time > 0
        model.update(bodyScale: state.bodyScale, outfit: state.equippedOutfit,
                     walking: motion == .walking, animated: animated,
                     heading: 180, cameraHeading: 0, motion: motion,
                     waterLevel: Double(state.daily.waterML) / 2_000,
                     character: state.preferences.character, equippedItems: state.equippedItems)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = model.scene
        renderer.pointOfView = model.camera
        renderer.scene?.background.contents = UIColor.clear
        // Scene actions need a zero-time frame before sampling a later animation frame.
        if animated { _ = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X) }
        let image = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
        guard image.cgImage != nil else { return nil }
        return image
    }

}
