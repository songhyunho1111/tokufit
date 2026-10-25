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
              (try? state.validate()) != nil else { return nil }
        let model = MapUsagiView.Coordinator()
        let animated = time > 0
        model.update(bodyScale: state.bodyScale, outfit: state.equippedOutfit,
                     walking: motion == .walking, animated: animated,
                     heading: 180, cameraHeading: 0, motion: motion,
                     waterLevel: Double(state.daily.waterML) / 2_000,
                     character: state.preferences.character, equippedItems: state.equippedItems,
                     muscleLevel: state.muscleLevel, fieryEyes: state.attendanceNeedsAttention,
                     nutritionMood: state.nutritionMood, costume: state.currentCostume)
        return render(model: model, size: size, time: time)
    }

    static func renderCharacter(character: CharacterKind, size: CGSize) -> UIImage? {
        renderCostume(character: character, costume: nil, size: size)
    }

    static func renderCostume(character: CharacterKind, costume: CostumeStyle?, size: CGSize) -> UIImage? {
        guard size.width.isFinite, size.height.isFinite,
              (1...2_048).contains(size.width), (1...2_048).contains(size.height) else { return nil }
        let model = MapUsagiView.Coordinator()
        model.update(bodyScale: 1, outfit: .basic, walking: false, animated: false,
                     heading: 180, character: character, costume: costume)
        return render(model: model, size: size, time: 0)
    }

    private static func render(model: MapUsagiView.Coordinator, size: CGSize, time: TimeInterval) -> UIImage? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = model.scene
        renderer.pointOfView = model.camera
        renderer.scene?.background.contents = UIColor.clear
        // Scene actions need a zero-time frame before sampling a later animation frame.
        if time > 0 { _ = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X) }
        let image = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
        guard image.cgImage != nil else { return nil }
        return image
    }

}
