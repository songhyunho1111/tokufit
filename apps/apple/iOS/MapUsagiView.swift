import REPickShared
import SceneKit
import SwiftUI

enum UsagiOnboardingPose: String, CaseIterable {
    case height, weight, gender, goal
}

struct MapUsagiView: UIViewRepresentable {
    var bodyScale: Double = 1
    var outfit: Outfit = .basic
    var isWalking = false
    var heading: Double = 0
    var cameraHeading: Double = 0
    var motion: UsagiMotion?
    var waterLevel: Double = 0
    var isAnimating = true
    var accessibilityIdentifier = "walk.avatar"
    var onboardingPose: UsagiOnboardingPose?
    var character: CharacterKind = .usagi
    var equippedItems: [WardrobeItem] = []
    var reportReaction: HealthReportReaction? = nil
    var eatingStyle: FoodEatingStyle? = nil
    var muscleLevel: Double = 0
    var fieryEyes = false
    var nutritionMood: NutritionMood = .neutral
    var costume: CostumeStyle? = nil

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 24
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = accessibilityIdentifier
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let animated = isAnimating && scenePhase == .active && !reduceMotion
        let displayedMotion = motion ?? (isWalking ? .walking : .idle)
        context.coordinator.update(bodyScale: bodyScale, outfit: outfit, walking: isWalking, animated: animated,
                                   heading: heading, cameraHeading: cameraHeading,
                                   motion: displayedMotion, waterLevel: waterLevel, onboardingPose: onboardingPose,
                                   character: character, equippedItems: equippedItems, reportReaction: reportReaction,
                                   eatingStyle: eatingStyle, muscleLevel: muscleLevel, fieryEyes: fieryEyes,
                                   nutritionMood: nutritionMood, costume: costume)
        view.isPlaying = animated
        view.accessibilityIdentifier = accessibilityIdentifier
        view.accessibilityValue = eatingStyle?.rawValue
        switch displayedMotion {
        case .idle: view.accessibilityLabel = String(localized: "쉬는 3D 우사기")
        case .walking: view.accessibilityLabel = String(localized: "걷는 3D 우사기")
        case .exercising: view.accessibilityLabel = String(localized: "운동하는 3D 우사기")
        case .grazing: view.accessibilityLabel = String(localized: "풀을 먹는 3D 우사기")
        case .sweating: view.accessibilityLabel = String(localized: "땀 흘리는 3D 우사기")
        case .eating: view.accessibilityLabel = String(localized: "떡볶이를 먹는 3D 우사기")
        case .drinking: view.accessibilityLabel = String(localized: "물을 마시는 3D 우사기")
        }
        if let reportReaction {
            switch reportReaction {
            case .celebrate: view.accessibilityLabel = String(localized: "두 팔을 들어 기뻐하는 3D 우사기")
            case .encourage: view.accessibilityLabel = String(localized: "한 팔을 들어 응원하는 3D 우사기")
            case .rest: view.accessibilityLabel = String(localized: "편안히 쉬는 3D 우사기")
            case .curious: view.accessibilityLabel = String(localized: "고개를 기울여 살펴보는 3D 우사기")
            }
        }
        if let eatingStyle {
            switch eatingStyle {
            case .grass: view.accessibilityLabel = String(localized: "풀을 먹는 3D 우사기")
            case .noodles: view.accessibilityLabel = String(localized: "면을 먹는 3D 우사기")
            case .rice: view.accessibilityLabel = String(localized: "밥을 먹는 3D 우사기")
            case .tteokbokki: view.accessibilityLabel = String(localized: "떡볶이를 먹는 3D 우사기")
            }
        }
        if character != .usagi {
            view.accessibilityLabel = view.accessibilityLabel?.replacingOccurrences(of: "우사기", with: character.name)
        }
        if let costume {
            view.accessibilityLabel = (view.accessibilityLabel ?? character.name) + ", " + costume.name
        }
        if nutritionMood == .sparkling {
            view.accessibilityLabel = (view.accessibilityLabel ?? character.name) + String(localized: ", 금빛 반짝임")
        } else if nutritionMood == .lowEnergy {
            view.accessibilityLabel = (view.accessibilityLabel ?? character.name) + String(localized: ", 조용히 쉬는 모습")
        }
        if fieryEyes {
            view.accessibilityLabel = (view.accessibilityLabel ?? character.name) + String(localized: ", 불꽃 눈")
        }
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        view.isPlaying = false
        coordinator.scene.isPaused = true
        view.scene = nil
    }

    @MainActor
    final class Coordinator {
        let scene = SCNScene()
        let camera = SCNNode()
        private let orientation = SCNNode()
        private let rabbit = SCNNode()
        private let torso = SCNNode()
        private let bodyOutline = SCNNode()
        private let clothing = SCNNode()
        private let headwear = SCNNode()
        private let wardrobe = SCNNode()
        private let props = SCNNode()
        private let waterWave = SCNNode()
        private let muscleDetails = SCNNode()
        private let fullCostume = SCNNode()
        private let costumeHeldProps = SCNNode()
        private let nutritionEffect = SCNNode()
        private var eyes: [SCNNode] = []
        private var flames: [SCNNode] = []
        private var arms: [SCNNode] = []
        private var feet: [SCNNode] = []
        private var ears: [SCNNode] = []
        private var lastOutfit: Outfit?
        private var lastMotion: UsagiMotion?
        private var lastOnboardingPose: UsagiOnboardingPose?
        private var lastReportReaction: HealthReportReaction?
        private var lastEatingStyle: FoodEatingStyle?
        private var lastWaterLevel: Double?
        private var lastAnimated: Bool?
        private var lastBodyScale: Float?
        private var lastYaw: Double?
        private var character: CharacterKind = .usagi
        private var lastItems: [WardrobeItem]?
        private var muscleLevel: CGFloat = 0
        private var lastFieryEyes: Bool?
        private var lastCostume: CostumeStyle?
        private var lastNutritionMood: NutritionMood?

        private var fur: UIColor { character == .usagi ? UIColor(red: 1, green: 241.0 / 255, blue: 203.0 / 255, alpha: 1) : UIColor(white: 0.985, alpha: 1) }
        private let hachiwareBlue = UIColor(red: 128 / 255, green: 177 / 255, blue: 200 / 255, alpha: 1)
        private let pink = UIColor(red: 1, green: 194.0 / 255, blue: 202.0 / 255, alpha: 1)
        private let ink = UIColor(red: 65.0 / 255, green: 37.0 / 255, blue: 33.0 / 255, alpha: 1)
        private let navy = UIColor(red: 0.13, green: 0.23, blue: 0.39, alpha: 1)

        init() {
            scene.background.contents = UIColor.clear
            scene.rootNode.addChildNode(orientation)
            orientation.addChildNode(rabbit)
            rabbit.addChildNode(torso)
            rabbit.addChildNode(clothing)
            rabbit.addChildNode(headwear)
            wardrobe.name = "character.wardrobe"
            rabbit.addChildNode(wardrobe)
            props.name = "care.motion.props"
            waterWave.name = "care.water"
            torso.name = "character.body"
            muscleDetails.name = "character.muscles"
            rabbit.addChildNode(props)
            rabbit.addChildNode(waterWave)
            rabbit.addChildNode(muscleDetails)
            fullCostume.name = "character.costume"
            costumeHeldProps.name = "costume.heldProps"
            nutritionEffect.name = "nutrition.effect"
            rabbit.addChildNode(fullCostume)
            rabbit.addChildNode(nutritionEffect)
            makeBody()
            makeFace()
            makeLightsAndCamera()
        }

        func update(bodyScale: Double, outfit: Outfit, walking: Bool, animated: Bool, heading: Double = 0, cameraHeading: Double = 0, motion: UsagiMotion? = nil, waterLevel: Double = 0, onboardingPose: UsagiOnboardingPose? = nil, character: CharacterKind = .usagi, equippedItems: [WardrobeItem] = [], reportReaction: HealthReportReaction? = nil, eatingStyle: FoodEatingStyle? = nil, muscleLevel: Double = 0, fieryEyes: Bool = false, nutritionMood: NutritionMood = .neutral, costume: CostumeStyle? = nil) {
            if self.character != character { rebuildCharacter(character) }
            updateOrientation(heading: heading, cameraHeading: cameraHeading, animated: animated)
            let width = Float(min(1.6, max(0.75, bodyScale.isFinite ? bodyScale : 1)))
            let strength = CGFloat(min(1, max(0, muscleLevel.isFinite ? muscleLevel : 0)))
            let widthChanged = width != lastBodyScale || strength != self.muscleLevel
            self.muscleLevel = strength
            if widthChanged {
                let mesh = bodyGeometry(width: width)
                mesh.firstMaterial = material(fur)
                torso.geometry = mesh
                bodyOutline.geometry = outlinedGeometry(mesh)
                let shoulder = Float(bodySection(at: 0.82, width: width).x) - 0.01
                for (index, arm) in arms.enumerated() { arm.position.x = (index == 0 ? -shoulder : shoulder) }
                for (index, foot) in feet.enumerated() { foot.position.x = (index == 0 ? -footSpacing : footSpacing) * min(1.2, width) }
                frameCharacter()
                lastBodyScale = width
            }
            let costumeChanged = lastCostume != costume
            let outfitChanged = lastOutfit != outfit
            let itemsChanged = lastItems != equippedItems
            let costumeNeedsUpdate = costumeChanged || widthChanged || outfitChanged || itemsChanged
            if outfitChanged || widthChanged || costumeChanged {
                setOutfit(outfit, width: width)
                setMuscles(width: width, outfit: outfit)
                muscleDetails.isHidden = costume != nil
                lastOutfit = outfit
            }
            if itemsChanged || widthChanged || costumeChanged {
                setItems(equippedItems, width: width)
                lastItems = equippedItems
            }
            if costumeNeedsUpdate {
                setCostume(costume, width: width, outfit: outfit, items: equippedItems)
                lastCostume = costume
            }
            let displayedMotion = motion ?? (walking ? .walking : .idle)
            if lastFieryEyes != fieryEyes || lastAnimated != animated {
                setFieryEyes(fieryEyes, animated: animated)
                lastFieryEyes = fieryEyes
            }
            let level = min(1, max(0, waterLevel.isFinite ? waterLevel : 0))
            if lastWaterLevel != level || widthChanged || lastAnimated != animated {
                setWater(level: level, width: width, animated: animated)
                lastWaterLevel = level
            }
            if lastMotion != displayedMotion || lastAnimated != animated || widthChanged || lastOnboardingPose != onboardingPose || lastReportReaction != reportReaction || lastEatingStyle != eatingStyle || lastNutritionMood != nutritionMood || costumeNeedsUpdate {
                if lastEatingStyle != nil || eatingStyle != nil { clearEatingStyle() }
                if let eatingStyle {
                    setEatingStyle(eatingStyle, animated: animated, width: width)
                } else if let reportReaction {
                    setReportReaction(reportReaction, animated: animated, width: width)
                } else if let onboardingPose {
                    setOnboardingPose(onboardingPose, animated: animated, width: width)
                } else {
                    if lastOnboardingPose != nil || lastReportReaction != nil || lastEatingStyle != nil || lastNutritionMood == .lowEnergy {
                        for (index, ear) in ears.enumerated() {
                            transitionPose(ear, rotation: SCNVector3(0, 0, index == 0 ? -0.055 : 0.055), animated: animated)
                        }
                    }
                    setPresentationMotion(displayedMotion, animated: animated, width: width)
                }
                let resting = displayedMotion == .idle && eatingStyle == nil && reportReaction == nil && onboardingPose == nil
                setCostumePose(costume, resting: resting, animated: animated)
                if nutritionMood == .lowEnergy && resting {
                    setLowEnergyPose(animated: animated)
                }
                lastMotion = displayedMotion
                lastOnboardingPose = onboardingPose
                lastReportReaction = reportReaction
                lastEatingStyle = eatingStyle
            }
            if lastNutritionMood != nutritionMood || lastAnimated != animated || widthChanged {
                setNutritionEffect(nutritionMood, animated: animated, width: width)
            }
            lastNutritionMood = nutritionMood
            lastAnimated = animated
            scene.isPaused = !animated
        }

        private var footSpacing: Float { character == .usagi ? 0.105 : 0.32 }

        private func rebuildCharacter(_ kind: CharacterKind) {
            clearEatingStyle()
            flames.forEach { $0.removeAllActions() }
            rabbit.removeAllActions()
            rabbit.childNodes.forEach { $0.removeFromParentNode() }
            feet.forEach { $0.removeFromParentNode() }
            arms.removeAll(); feet.removeAll(); ears.removeAll(); eyes.removeAll(); flames.removeAll()
            for node in [torso, bodyOutline, clothing, headwear, wardrobe, props, waterWave, muscleDetails, fullCostume, costumeHeldProps, nutritionEffect] {
                node.removeAllActions()
                node.removeAllAnimations()
                node.childNodes.forEach { $0.removeFromParentNode() }
                node.geometry = nil
            }
            rabbit.position = .init(0, 0, 0)
            rabbit.eulerAngles = .init(0, 0, 0)
            self.character = kind
            for node in [torso, clothing, headwear, wardrobe, props, waterWave, muscleDetails, fullCostume, nutritionEffect] { rabbit.addChildNode(node) }
            makeBody()
            makeFace()
            frameCharacter()
            lastBodyScale = nil; lastOutfit = nil; lastItems = nil
            lastFieryEyes = nil; lastCostume = nil; lastNutritionMood = nil
            lastMotion = nil; lastOnboardingPose = nil; lastReportReaction = nil; lastEatingStyle = nil; lastWaterLevel = nil; lastAnimated = nil
        }

        private func updateOrientation(heading: Double, cameraHeading: Double, animated: Bool) {
            let user = (heading.isFinite ? heading : 0).truncatingRemainder(dividingBy: 360)
            let map = (cameraHeading.isFinite ? cameraHeading : 0).truncatingRemainder(dividingBy: 360)
            let target = Self.wrappedAngle(.pi - (user - map) * .pi / 180)
            guard lastYaw == nil || abs(Self.wrappedAngle(target - (lastYaw ?? 0))) > 0.001 || (!animated && lastAnimated != false) else { return }
            let shouldAnimate = animated && lastYaw != nil
            let current = Double(orientation.presentation.eulerAngles.y)
            // Rotate through the shortest arc when a compass bearing crosses north.
            let destination = shouldAnimate ? current + Self.wrappedAngle(target - current) : target
            SCNTransaction.begin()
            SCNTransaction.animationDuration = shouldAnimate ? 0.2 : 0
            SCNTransaction.disableActions = !shouldAnimate
            orientation.eulerAngles.y = Float(destination)
            SCNTransaction.commit()
            lastYaw = target
        }

        private static func wrappedAngle(_ angle: Double) -> Double {
            atan2(sin(angle), cos(angle))
        }

        private func makeBody() {
            let mesh = bodyGeometry(width: 1)
            mesh.firstMaterial = material(fur)
            torso.geometry = mesh
            bodyOutline.geometry = outlinedGeometry(mesh)
            bodyOutline.scale = SCNVector3(1.016, 1.008, 1.016)
            rabbit.addChildNode(bodyOutline)
            torso.addChildNode(ellipsoid(size: SCNVector3(0.145, 0.15, 0.135), position: SCNVector3(0, 0.43, -0.50), color: character == .hachiware ? hachiwareBlue : .white, outlined: true))
            for side: Float in [-1, 1] {
                let ear = SCNNode()
                ear.eulerAngles.z = side * 0.055
                switch character {
                case .usagi:
                    ear.position = SCNVector3(side * 0.225 * Float(headFactor(at: 2.18)), 2.56, -0.015)
                    let outside = SCNSphere(radius: 1)
                    outside.segmentCount = 48
                    let shell = SCNNode(geometry: outside)
                    shell.scale = SCNVector3(0.185, 0.595, 0.12)
                    outside.firstMaterial = material(fur)
                    addOutline(to: shell, scale: 1.035)
                    ear.addChildNode(shell)
                    ear.addChildNode(earInset(side: CGFloat(side)))
                case .chiikawa:
                    ear.position = SCNVector3(side * 0.64, 2.10, -0.015)
                    ear.addChildNode(ellipsoid(size: SCNVector3(0.155, 0.20, 0.12), position: .init(0, 0.07, 0), color: fur, outlined: true))
                case .hachiware:
                    ear.position = SCNVector3(side * 0.64, 2.06, -0.05)
                    let path = UIBezierPath()
                    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * CGFloat(side), y: y) }
                    path.move(to: point(-0.23, -0.08))
                    path.addCurve(to: point(0.07, 0.43), controlPoint1: point(-0.19, 0.09), controlPoint2: point(0.01, 0.40))
                    path.addCurve(to: point(0.15, 0.45), controlPoint1: point(0.10, 0.48), controlPoint2: point(0.13, 0.49))
                    path.addCurve(to: point(0.25, -0.06), controlPoint1: point(0.21, 0.37), controlPoint2: point(0.26, 0.08))
                    path.addCurve(to: point(-0.23, -0.08), controlPoint1: point(0.10, -0.10), controlPoint2: point(-0.12, -0.12))
                    path.close()
                    path.flatness = 0.001
                    let shape = SCNShape(path: path, extrusionDepth: 0.19)
                    shape.chamferRadius = 0.045
                    shape.firstMaterial = material(hachiwareBlue)
                    let shell = SCNNode(geometry: shape)
                    addOutline(to: shell, scale: 1.045)
                    ear.addChildNode(shell)
                }
                rabbit.addChildNode(ear)
                ears.append(ear)

                let arm = SCNNode()
                arm.name = "character.arm"
                arm.position = SCNVector3(side * 0.76, 0.82, 0.06)
                arm.eulerAngles.z = side * 0.17
                arm.addChildNode(ellipsoid(size: SCNVector3(0.077, 0.155, 0.095), position: SCNVector3(0, -0.105, 0), color: fur, outlined: true))
                rabbit.addChildNode(arm)
                arms.append(arm)

                let foot = SCNNode()
                foot.position = SCNVector3(side * footSpacing, 0.045, 0)
                let paw = SCNCapsule(capRadius: 0.085, height: 0.22)
                paw.radialSegmentCount = 24
                let sole = SCNNode(geometry: paw)
                sole.scale.z = 1.25
                paw.firstMaterial = material(fur)
                addOutline(to: sole, scale: 1.035)
                foot.addChildNode(sole)
                orientation.addChildNode(foot)
                feet.append(foot)
            }
            guard scene.rootNode.childNode(withName: "character.shadow", recursively: false) == nil else { return }
            let shadow = ellipsoid(size: SCNVector3(0.53, 0.007, 0.30), position: SCNVector3(0, -0.075, 0), color: UIColor.black.withAlphaComponent(0.10))
            shadow.name = "character.shadow"
            shadow.geometry?.firstMaterial?.lightingModel = .constant
            shadow.geometry?.firstMaterial?.diffuse.contents = UIColor.black
            shadow.geometry?.firstMaterial?.transparency = 0.10
            shadow.geometry?.firstMaterial?.writesToDepthBuffer = false
            scene.rootNode.addChildNode(shadow)
        }

        private func earInset(side: CGFloat) -> SCNNode {
            let rings = 8, segments = 32
            var vertices: [SCNVector3] = []
            var indices: [Int32] = []
            for ring in 0...rings {
                let fraction = CGFloat(ring) / CGFloat(rings)
                for segment in 0...segments {
                    let angle = CGFloat(segment) / CGFloat(segments) * 2 * .pi
                    let x = side * 0.045 + cos(angle) * 0.060 * fraction
                    let y = 0.012 + sin(angle) * 0.49 * fraction
                    let z = 0.12 * sqrt(max(0.001, 1 - pow(x / 0.185, 2) - pow(y / 0.595, 2))) + 0.003
                    vertices.append(SCNVector3(Float(x), Float(y), Float(z)))
                    if ring < rings && segment < segments {
                        let a = Int32(ring * (segments + 1) + segment), b = a + Int32(segments + 1)
                        indices += [a, b, a + 1, a + 1, b, b + 1]
                    }
                }
            }
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
            let paint = flatMaterial(pink)
            paint.isDoubleSided = true
            geometry.firstMaterial = paint
            return SCNNode(geometry: geometry)
        }

        private func makeFace() {
            if character == .hachiware { rabbit.addChildNode(hachiwareCap()) }
            for side: Float in [-1, 1] {
                let eye = SCNNode()
                let x = CGFloat(side) * 0.30 * headFactor(at: 1.51)
                eye.position = SCNVector3(Float(x), 1.51, Float(surfaceDepth(x: x, y: 1.51)) + 0.015)
                eye.eulerAngles.y = side * 0.17
                eye.addChildNode(ellipsoid(size: SCNVector3(0.101, 0.102, 0.030), position: SCNVector3Zero, color: ink))
                let highlight = ellipsoid(size: SCNVector3(0.040, 0.027, 0.007), position: SCNVector3(-0.010, 0.038, 0.029), color: .white)
                highlight.geometry?.firstMaterial = flatMaterial(.white)
                eye.addChildNode(highlight)
                let glint = UIBezierPath()
                glint.move(to: CGPoint(x: -0.050, y: -0.030))
                glint.addCurve(to: CGPoint(x: 0.050, y: -0.030), controlPoint1: CGPoint(x: -0.027, y: -0.066), controlPoint2: CGPoint(x: 0.027, y: -0.066))
                let lowerGlint = stroke(glint, width: 0.013, color: .white)
                lowerGlint.geometry?.firstMaterial = flatMaterial(.white)
                lowerGlint.position.z = 0.029
                eye.addChildNode(lowerGlint)
                rabbit.addChildNode(eye)
                eye.name = "character.eye"
                eyes.append(eye)
                let flame = flameEye()
                flame.position = eye.position
                flame.eulerAngles = eye.eulerAngles
                flame.isHidden = true
                rabbit.addChildNode(flame)
                flames.append(flame)

                if character == .usagi {
                    let brow = cubic(CGPoint(x: -0.56, y: 1.68), CGPoint(x: -0.55, y: 1.87), CGPoint(x: -0.42, y: 1.95), CGPoint(x: -0.28, y: 1.95))
                    rabbit.addChildNode(surfaceStroke(brow.map { CGPoint(x: side < 0 ? $0.x : -$0.x, y: $0.y) }, thickness: 0.024, color: ink))
                } else if character == .chiikawa {
                    rabbit.addChildNode(surfaceStroke([CGPoint(x: CGFloat(side) * 0.38, y: 1.82), CGPoint(x: CGFloat(side) * 0.27, y: 1.84)], thickness: 0.022, color: ink))
                } else {
                    rabbit.addChildNode(surfacePatch(center: CGPoint(x: CGFloat(side) * 0.30, y: 1.82), radius: CGSize(width: 0.016, height: 0.012), color: ink))
                }
                let cheekX = CGFloat(side) * 0.60
                rabbit.addChildNode(surfacePatch(center: CGPoint(x: cheekX, y: 1.30), radius: CGSize(width: 0.18, height: 0.105), color: pink))
                for offset: CGFloat in [-0.105, -0.035, 0.035, 0.105] {
                    rabbit.addChildNode(surfaceStroke([
                        CGPoint(x: cheekX + offset - 0.013, y: 1.265),
                        CGPoint(x: cheekX + offset + 0.013, y: 1.335)
                    ], thickness: 0.021, color: ink, padding: 0.020))
                }
            }
            var mouth = cubic(CGPoint(x: -0.13, y: 1.32), CGPoint(x: -0.15, y: 1.21), CGPoint(x: -0.025, y: 1.20), CGPoint(x: 0, y: 1.30))
            mouth += cubic(CGPoint(x: 0, y: 1.30), CGPoint(x: 0.025, y: 1.20), CGPoint(x: 0.15, y: 1.21), CGPoint(x: 0.13, y: 1.32)).dropFirst()
            let mouthNode = surfaceStroke(mouth, thickness: 0.026, color: ink)
            mouthNode.name = "character.mouth"
            mouthNode.pivot = SCNMatrix4MakeTranslation(0, 1.25, 0)
            mouthNode.position.y = 1.25
            rabbit.addChildNode(mouthNode)
            if character == .usagi {
                let curl = cubic(CGPoint(x: -0.015, y: 1.245), CGPoint(x: -0.025, y: 1.15), CGPoint(x: 0.010, y: 1.12), CGPoint(x: 0.065, y: 1.12))
                rabbit.addChildNode(surfaceStroke(curl, thickness: 0.024, color: ink))
            } else {
                rabbit.addChildNode(surfaceStroke(cubic(CGPoint(x: -0.04, y: 1.16), CGPoint(x: -0.02, y: 1.14), CGPoint(x: 0.02, y: 1.14), CGPoint(x: 0.04, y: 1.16)), thickness: 0.023, color: ink))
            }
        }

        private func hachiwareCap() -> SCNNode {
            let rings = 36, sides = 96
            var vertices: [SCNVector3] = []
            var normals: [SCNVector3] = []
            var indices: [Int32] = []
            var frontSeam: [CGPoint] = []
            for ring in 0...rings {
                for side in 0...sides {
                    let angle = CGFloat(side) / CGFloat(sides) * 2 * .pi
                    let front = max(0, cos(angle))
                    let bottom = 1.84 + front * (0.035 + 0.205 * pow(1 - abs(sin(angle)), 5))
                    let y = bottom + (2.18 - bottom) * CGFloat(ring) / CGFloat(rings)
                    let section = bodySection(at: y)
                    let rx = section.x + 0.018, rz = section.z + 0.018
                    if ring == rings {
                        vertices.append(SCNVector3(0, 2.185, 0))
                        normals.append(SCNVector3(0, 1, 0))
                    } else {
                        vertices.append(SCNVector3(Float(rx * sin(angle)), Float(y), Float(rz * cos(angle))))
                        let low = bodySection(at: y - 0.001), high = bodySection(at: min(2.18, y + 0.001))
                        let dx = (high.x - low.x) / 0.002, dz = (high.z - low.z) / 0.002
                        let nx = sin(angle) / rx, nz = cos(angle) / rz
                        let ny = -(dx * pow(sin(angle), 2) / rx + dz * pow(cos(angle), 2) / rz)
                        let length = sqrt(nx * nx + ny * ny + nz * nz)
                        normals.append(SCNVector3(Float(nx / length), Float(ny / length), Float(nz / length)))
                    }
                    if ring < rings && side < sides {
                        let a = Int32(ring * (sides + 1) + side), b = a + Int32(sides + 1)
                        indices += [a, a + 1, b, a + 1, b + 1, b]
                    }
                }
            }
            for side in 0...64 {
                let angle = -CGFloat.pi / 2 + CGFloat(side) / 64 * .pi
                let y = 1.84 + cos(angle) * (0.035 + 0.205 * pow(1 - abs(sin(angle)), 5))
                frontSeam.append(CGPoint(x: bodySection(at: y).x * sin(angle), y: y))
            }
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
            geometry.firstMaterial = material(hachiwareBlue)
            let cap = SCNNode(geometry: geometry)
            cap.name = "character.hachiware.cap"
            cap.addChildNode(surfaceStroke(frontSeam, thickness: 0.026, color: ink, padding: 0.028))
            return cap
        }

        private func flameEye() -> SCNNode {
            let flame = SCNNode()
            flame.name = "character.fieryEye"
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: -0.105))
            path.addCurve(to: CGPoint(x: -0.095, y: 0.075), controlPoint1: CGPoint(x: -0.13, y: -0.10), controlPoint2: CGPoint(x: -0.14, y: 0.01))
            path.addCurve(to: CGPoint(x: -0.045, y: 0.18), controlPoint1: CGPoint(x: -0.06, y: 0.11), controlPoint2: CGPoint(x: -0.055, y: 0.15))
            path.addCurve(to: CGPoint(x: -0.015, y: 0.075), controlPoint1: CGPoint(x: -0.025, y: 0.15), controlPoint2: CGPoint(x: -0.025, y: 0.105))
            path.addCurve(to: CGPoint(x: 0.025, y: 0.24), controlPoint1: CGPoint(x: 0.04, y: 0.12), controlPoint2: CGPoint(x: 0.01, y: 0.19))
            path.addCurve(to: CGPoint(x: 0.09, y: 0.08), controlPoint1: CGPoint(x: 0.10, y: 0.18), controlPoint2: CGPoint(x: 0.055, y: 0.13))
            path.addCurve(to: CGPoint(x: 0, y: -0.105), controlPoint1: CGPoint(x: 0.18, y: -0.015), controlPoint2: CGPoint(x: 0.105, y: -0.105))
            path.close()
            path.flatness = 0.001
            for (scale, color, depth) in [(1.0, UIColor(red: 0.79, green: 0.20, blue: 0.08, alpha: 1), 0.024),
                                          (0.84, UIColor(red: 1, green: 0.44, blue: 0.08, alpha: 1), 0.042),
                                          (0.54, UIColor(red: 1, green: 0.88, blue: 0.32, alpha: 1), 0.060)] {
                let shape = SCNShape(path: path, extrusionDepth: 0.012)
                shape.chamferRadius = 0.003
                shape.firstMaterial = flatMaterial(color)
                let layer = SCNNode(geometry: shape)
                layer.scale = SCNVector3(Float(scale), Float(scale), 1)
                layer.position = SCNVector3(0, Float((scale - 1) * 0.08), Float(depth))
                flame.addChildNode(layer)
            }
            return flame
        }

        private func setFieryEyes(_ enabled: Bool, animated: Bool) {
            eyes.forEach { $0.isHidden = enabled }
            for flame in flames {
                flame.removeAllActions()
                flame.scale = SCNVector3(1, 1, 1)
                flame.isHidden = !enabled
                if enabled && animated {
                    flame.runAction(.repeatForever(.sequence([
                        eased(.scale(to: 1.06, duration: 0.55)),
                        eased(.scale(to: 1, duration: 0.55))
                    ])), forKey: "attendance.flame")
                }
            }
        }

        private func setMuscles(width: Float, outfit: Outfit) {
            muscleDetails.childNodes.forEach { $0.removeFromParentNode() }
            let strength = Float(muscleLevel)
            for (index, arm) in arms.enumerated() {
                arm.childNode(withName: "character.bicep", recursively: false)?.removeFromParentNode()
                arm.childNodes.first?.scale = SCNVector3(0.077 * (1 + strength * 0.9), 0.155 * (1 + strength * 0.16), 0.095 * (1 + strength * 0.5))
                guard strength > 0 else { continue }
                let side: Float = index == 0 ? -1 : 1
                let bicep = ellipsoid(size: SCNVector3(0.115, 0.11, 0.12), position: SCNVector3(side * 0.025, -0.025, 0.015), color: fur, outlined: true)
                bicep.name = "character.bicep"
                bicep.scale = SCNVector3(0.055 + strength * 0.06, 0.075 + strength * 0.035, 0.07 + strength * 0.05)
                arm.addChildNode(bicep)
            }
            guard strength > 0, outfit == .basic else { return }
            let contour = character == .usagi ? UIColor(red: 0.63, green: 0.51, blue: 0.35, alpha: 1) : UIColor(white: 0.62, alpha: 1)
            for side: CGFloat in [-1, 1] {
                let chest = cubic(CGPoint(x: side * 0.055, y: 0.84), CGPoint(x: side * 0.14, y: 0.76), CGPoint(x: side * 0.32, y: 0.77), CGPoint(x: side * 0.40, y: 0.86))
                muscleDetails.addChildNode(surfaceStroke(chest, thickness: 0.014, color: contour, width: width, padding: 0.017))
            }
            muscleDetails.opacity = muscleLevel
        }

        private func setOutfit(_ outfit: Outfit, width: Float) {
            clothing.childNodes.forEach { $0.removeFromParentNode() }
            headwear.childNodes.forEach { $0.removeFromParentNode() }
            guard outfit != .basic else { return }
            let shirtColor: UIColor = outfit == .sport ? UIColor(red: 0.12, green: 0.35, blue: 0.24, alpha: 1) : .white
            let shirt = SCNNode(geometry: bodyGeometry(width: width, range: 0.55...1.02, padding: 0.014))
            shirt.geometry?.firstMaterial = material(shirtColor)
            clothing.addChildNode(shirt)
            switch outfit {
            case .basic: break
            case .office:
                clothing.addChildNode(surfacePolygon([CGPoint(x: -0.06, y: 0.96), CGPoint(x: 0.06, y: 0.96), CGPoint(x: 0.035, y: 0.87), CGPoint(x: 0.08, y: 0.59), CGPoint(x: 0, y: 0.51), CGPoint(x: -0.08, y: 0.59), CGPoint(x: -0.035, y: 0.87)], color: navy, width: width))
            case .student:
                clothing.addChildNode(surfaceStroke([CGPoint(x: -0.56, y: 0.97), CGPoint(x: 0, y: 0.76), CGPoint(x: 0.56, y: 0.97)], thickness: 0.085, color: navy, width: width, padding: 0.035))
                for side: CGFloat in [-1, 1] {
                    clothing.addChildNode(surfacePolygon([CGPoint(x: 0, y: 0.77), CGPoint(x: side * 0.15, y: 0.84), CGPoint(x: side * 0.13, y: 0.66)], color: .systemRed, width: width))
                }
            case .sport:
                clothing.addChildNode(surfaceStroke([CGPoint(x: 0, y: 0.98), CGPoint(x: 0, y: 0.57)], thickness: 0.09, color: UIColor(white: 0.96, alpha: 1), width: width, padding: 0.035))
                let headband = SCNNode(geometry: bodyGeometry(width: 1, range: 2.02...2.10, padding: 0.013))
                headband.geometry?.firstMaterial = material(.white)
                headwear.addChildNode(headband)
            }
        }

        private func setItems(_ items: [WardrobeItem], width: Float) {
            wardrobe.childNodes.forEach { $0.removeFromParentNode() }
            for foot in feet {
                foot.childNodes.first?.childNode(withName: "wardrobe.shoe", recursively: false)?.removeFromParentNode()
            }
            for item in items {
                let group = SCNNode()
                group.name = "wardrobe.item.\(item.rawValue)"
                switch item {
                case .shorts:
                    let shorts = SCNNode(geometry: bodyGeometry(width: width, range: 0.17...0.58, padding: 0.027))
                    shorts.geometry?.firstMaterial = material(navy)
                    group.addChildNode(shorts)
                    group.addChildNode(surfaceStroke([CGPoint(x: 0, y: 0.17), CGPoint(x: 0, y: 0.39)], thickness: 0.018, color: ink, width: width, padding: 0.055))
                case .skirt:
                    let waist = bodySection(at: 0.55, width: width)
                    let skirt = SCNNode(geometry: SCNCone(topRadius: waist.x + 0.025, bottomRadius: waist.x + 0.12, height: 0.40))
                    skirt.position.y = 0.35
                    skirt.scale.z = Float(waist.z / waist.x)
                    skirt.geometry?.firstMaterial = material(UIColor(red: 0.75, green: 0.33, blue: 0.39, alpha: 1))
                    addOutline(to: skirt, scale: 1.015)
                    group.addChildNode(skirt)
                case .sneakers, .boots:
                    for foot in feet {
                        guard let sole = foot.childNodes.first else { continue }
                        let shoe = SCNNode()
                        shoe.name = "wardrobe.shoe"
                        let color = item == .sneakers ? UIColor(white: 0.94, alpha: 1) : UIColor(red: 0.42, green: 0.27, blue: 0.17, alpha: 1)
                        shoe.addChildNode(ellipsoid(size: .init(0.12, 0.10, 0.145), position: .init(0, -0.01, 0.025), color: color, outlined: true))
                        if item == .boots {
                            let cuff = SCNNode(geometry: SCNCylinder(radius: 0.105, height: 0.17))
                            cuff.position.y = 0.055
                            cuff.scale.z = 1.1
                            cuff.geometry?.firstMaterial = material(color)
                            shoe.addChildNode(cuff)
                        } else {
                            shoe.addChildNode(ellipsoid(size: .init(0.09, 0.018, 0.025), position: .init(0, 0.04, 0.15), color: navy))
                        }
                        sole.addChildNode(shoe)
                    }
                case .bow:
                    let bow = SCNNode()
                    bow.position = .init(0.42, 2.02, Float(surfaceDepth(x: 0.42, y: 2.02)) + 0.07)
                    for side: Float in [-1, 1] {
                        let loop = ellipsoid(size: .init(0.14, 0.10, 0.045), position: .init(side * 0.115, 0, 0), color: pink, outlined: true)
                        loop.eulerAngles.z = side * 0.25
                        bow.addChildNode(loop)
                    }
                    bow.addChildNode(ellipsoid(size: .init(0.06, 0.065, 0.06), position: .init(0, 0, 0.015), color: pink, outlined: true))
                    group.addChildNode(bow)
                case .glasses:
                    for side: Float in [-1, 1] {
                        let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.17, pipeRadius: 0.016))
                        ring.position = .init(side * 0.30 * Float(headFactor(at: 1.51)), 1.51, Float(surfaceDepth(x: 0.30 * headFactor(at: 1.51), y: 1.51)) + 0.075)
                        ring.eulerAngles.x = .pi / 2
                        ring.eulerAngles.y = side * 0.17
                        ring.geometry?.firstMaterial = material(navy)
                        group.addChildNode(ring)
                    }
                    group.addChildNode(surfaceStroke([CGPoint(x: -0.13, y: 1.51), CGPoint(x: 0.13, y: 1.51)], thickness: 0.025, color: navy, padding: 0.08))
                }
                wardrobe.addChildNode(group)
            }
        }

        private func setCostume(_ style: CostumeStyle?, width: Float, outfit: Outfit, items: [WardrobeItem]) {
            fullCostume.childNodes.forEach { $0.removeFromParentNode() }
            costumeHeldProps.childNodes.forEach { $0.removeFromParentNode() }
            for node in arms + ears {
                node.childNodes.filter { $0.name?.hasPrefix("costume.") == true }.forEach { $0.removeFromParentNode() }
            }
            guard let style else { return }
            let hasTop = outfit != .basic
            let hasBottom = items.contains { $0.category == .bottom }
            fullCostume.addChildNode(costumeHeldProps)
            let cream = UIColor(red: 1, green: 0.96, blue: 0.84, alpha: 1)
            switch style {
            case .mermaidIsland:
                if !hasBottom { addCostumeSkirt(width: width, grass: true) }
                for index in 0..<7 {
                    let x = CGFloat(index - 3) * 0.195
                    let y = 2.07 - 0.17 * pow(x / 0.60, 2)
                    let color = character == .hachiware && index.isMultiple(of: 2) ? UIColor(red: 0.70, green: 0.87, blue: 0.96, alpha: 1) : cream
                    let flower = costumeFlower(color: color, radius: 0.082)
                    flower.position = .init(Float(x), Float(y), Float(surfaceDepth(x: x, y: y)) + 0.09)
                    fullCostume.addChildNode(flower)
                }
                for side: Float in [-1, 1] {
                    let cup = ellipsoid(size: .init(0.16, 0.18, 0.14), position: .init(side * 0.24, 0.88, 0.78), color: UIColor(red: 0.87, green: 0.89, blue: 0.40, alpha: 1), outlined: true)
                    cup.name = "costume.cup"
                    let rim = SCNNode(geometry: SCNTorus(ringRadius: 0.77, pipeRadius: 0.055))
                    rim.geometry?.firstMaterial = material(UIColor(red: 0.58, green: 0.67, blue: 0.20, alpha: 1))
                    rim.position.y = 0.66
                    cup.addChildNode(rim)
                    costumeHeldProps.addChildNode(cup)
                    let strawPath = UIBezierPath()
                    strawPath.move(to: CGPoint(x: CGFloat(side) * 0.24, y: 0.99))
                    strawPath.addLine(to: CGPoint(x: CGFloat(side) * 0.19, y: 1.17))
                    strawPath.addLine(to: CGPoint(x: CGFloat(side) * 0.09, y: 1.20))
                    let straw = stroke(strawPath, width: 0.025, color: cream)
                    straw.position.z = 0.82
                    costumeHeldProps.addChildNode(straw)
                }
            case .pajamas:
                let color: UIColor = character == .chiikawa ? UIColor(red: 1, green: 0.70, blue: 0.76, alpha: 1) : character == .hachiware ? hachiwareBlue : UIColor(red: 1, green: 0.88, blue: 0.48, alpha: 1)
                if !hasTop || !hasBottom {
                    let range: ClosedRange<CGFloat> = (hasBottom ? 0.58 : 0.13)...(hasTop ? 0.55 : 1.10)
                    let onesie = SCNNode(geometry: bodyGeometry(width: width, range: range, padding: 0.035))
                    onesie.geometry?.firstMaterial = material(color)
                    fullCostume.addChildNode(onesie)
                }
                let hood = costumeHood(color: color)
                hood.name = "costume.hood"
                fullCostume.addChildNode(hood)
                for ear in ears {
                    guard let source = ear.childNodes.first, let geometry = source.geometry?.copy() as? SCNGeometry else { continue }
                    let cover = SCNNode(geometry: geometry)
                    cover.name = "costume.earCover"
                    cover.position = source.position
                    cover.position.z -= 0.016
                    cover.scale = SCNVector3(source.scale.x * 1.12, source.scale.y * 1.08, source.scale.z * 1.12)
                    geometry.firstMaterial = material(color)
                    ear.addChildNode(cover)
                }
                if !hasTop {
                    addCostumeSleeves(color: color)
                    for y: CGFloat in [0.81, 0.58] {
                        fullCostume.addChildNode(ellipsoid(size: .init(0.035, 0.035, 0.025), position: .init(0, Float(y), Float(surfaceDepth(x: 0, y: y, width: width)) + 0.06), color: ink))
                    }
                }
                let bag = ellipsoid(size: .init(0.16, 0.19, 0.075), position: .init(Float(bodySection(at: 0.70, width: width).x) + 0.05, 0.48, 0.18), color: .white, outlined: true)
                bag.name = "costume.bag"
                let handle = SCNNode(geometry: SCNTorus(ringRadius: 0.54, pipeRadius: 0.08))
                handle.eulerAngles.x = .pi / 2
                handle.position = .init(0, 1.03, 0)
                handle.geometry?.firstMaterial = material(.white)
                bag.addChildNode(handle)
                fullCostume.addChildNode(bag)
            case .gyaru:
                let cardiganColor = character == .hachiware ? UIColor(red: 0.57, green: 0.58, blue: 0.83, alpha: 1) : cream
                if !hasTop {
                    let cardigan = SCNNode(geometry: bodyGeometry(width: width, range: 0.45...1.05, padding: 0.04))
                    cardigan.geometry?.firstMaterial = material(cardiganColor)
                    fullCostume.addChildNode(cardigan)
                    addCostumeSleeves(color: cardiganColor)
                    fullCostume.addChildNode(surfaceStroke([CGPoint(x: 0, y: 0.91), CGPoint(x: 0, y: 0.48)], thickness: 0.016, color: UIColor(red: 0.71, green: 0.64, blue: 0.52, alpha: 1), width: width, padding: 0.055))
                    for y: CGFloat in [0.72, 0.55] {
                        fullCostume.addChildNode(ellipsoid(size: .init(0.025, 0.025, 0.015), position: .init(0.045, Float(y), Float(surfaceDepth(x: 0.045, y: y, width: width)) + 0.07), color: ink))
                    }
                    for index in -5...5 {
                        let x = CGFloat(index) * 0.105 * CGFloat(width)
                        fullCostume.addChildNode(surfaceStroke([CGPoint(x: x, y: 0.63), CGPoint(x: x + 0.015, y: 0.67)], thickness: 0.011, color: ink, width: width, padding: 0.055))
                    }
                }
                if !hasBottom { addCostumeSkirt(width: width, grass: false) }
                let bow = costumeBow(color: character == .chiikawa ? pink : character == .hachiware ? cream : UIColor(red: 0.95, green: 0.76, blue: 0.28, alpha: 1))
                let bowX: CGFloat = character == .chiikawa ? -0.48 : 0
                let bowY: CGFloat = character == .chiikawa ? 0.63 : 0.98
                bow.position = .init(Float(bowX), Float(bowY), Float(surfaceDepth(x: bowX, y: bowY, width: width)) + 0.12)
                fullCostume.addChildNode(bow)
                let flowerX: CGFloat = character == .hachiware ? -0.67 : 0.58
                let flower = costumeFlower(color: UIColor(red: 1, green: 0.26, blue: 0.57, alpha: 1), radius: 0.15)
                flower.position = .init(Float(flowerX), 2.06, Float(surfaceDepth(x: flowerX, y: 2.06)) + 0.13)
                let stamenPath = UIBezierPath()
                stamenPath.move(to: .zero)
                stamenPath.addQuadCurve(to: CGPoint(x: 0.13, y: 0.16), controlPoint: CGPoint(x: 0.12, y: 0.04))
                let stamen = stroke(stamenPath, width: 0.017, color: cream)
                stamen.position.z = 0.085
                flower.addChildNode(stamen)
                flower.addChildNode(ellipsoid(size: .init(0.03, 0.03, 0.018), position: .init(0.13, 0.16, 0.09), color: .systemYellow))
                fullCostume.addChildNode(flower)
                for index in 0..<2 {
                    let x = CGFloat(0.34 + Double(index) * 0.13), y = CGFloat(0.82 - Double(index) * 0.10)
                    let heart = costumeHeart()
                    heart.position = .init(Float(x), Float(y), Float(surfaceDepth(x: x, y: y, width: width)) + 0.075)
                    fullCostume.addChildNode(heart)
                }
                for side: Float in [-1, 1] {
                    let sparkle = costumeSparkle(color: .white, radius: 0.06)
                    sparkle.position = .init(side * 0.81, 1.43, Float(surfaceDepth(x: CGFloat(side) * 0.81, y: 1.43)) + 0.045)
                    fullCostume.addChildNode(sparkle)
                }
                for arm in arms {
                    let gesture = SCNNode()
                    gesture.name = "costume.peace"
                    for side: Float in [-1, 1] {
                        let finger = ellipsoid(size: .init(0.029, 0.075, 0.04), position: .init(side * 0.045, -0.27, 0.015), color: fur, outlined: true)
                        finger.eulerAngles.z = side * -0.25
                        gesture.addChildNode(finger)
                    }
                    arm.addChildNode(gesture)
                }
            }
        }

        private func addCostumeSleeves(color: UIColor) {
            for arm in arms {
                let sleeve = ellipsoid(size: .init(0.12, 0.13, 0.13), position: .init(0, -0.035, -0.012), color: color, outlined: true)
                sleeve.name = "costume.sleeve"
                arm.addChildNode(sleeve)
            }
        }

        private func addCostumeSkirt(width: Float, grass: Bool) {
            let waist = bodySection(at: 0.55, width: width)
            let count = grass ? 28 : 20
            let green = UIColor(red: 0.66, green: 0.84, blue: 0.39, alpha: 1)
            let skirtColor = character == .chiikawa ? navy : UIColor(red: 0.43, green: 0.46, blue: 0.53, alpha: 1)
            for index in 0..<count {
                let a = CGFloat(index) * 2 * .pi / CGFloat(count)
                let b = CGFloat(index + 1) * 2 * .pi / CGFloat(count)
                let middle = (a + b) / 2
                let bottom: CGFloat = grass ? 0.19 + (index.isMultiple(of: 2) ? 0.03 : 0) : 0.19
                let angles = [a, middle, b]
                var vertices: [SCNVector3] = []
                for y in [CGFloat(0.58), bottom] {
                    let flare: CGFloat = y == 0.58 ? 0.04 : 0.14
                    for (offset, angle) in angles.enumerated() {
                        let pleat: CGFloat = offset == 1 ? 0.018 : 0
                        vertices.append(.init(Float((waist.x + flare + pleat) * sin(angle)), Float(y), Float((waist.z + flare + pleat) * cos(angle))))
                    }
                }
                let mesh = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)], elements: [SCNGeometryElement(indices: [Int32(0), 3, 1, 1, 3, 4, 1, 4, 2, 2, 4, 5], primitiveType: .triangles)])
                let color = grass ? green : skirtColor
                mesh.firstMaterial = material(index.isMultiple(of: 2) ? color : (grass ? UIColor(red: 0.55, green: 0.74, blue: 0.29, alpha: 1) : UIColor(red: 0.32, green: 0.35, blue: 0.43, alpha: 1)))
                mesh.firstMaterial?.isDoubleSided = true
                let panel = SCNNode(geometry: mesh)
                panel.name = grass ? "costume.grass" : "costume.pleat"
                fullCostume.addChildNode(panel)
            }
            let belt = SCNNode(geometry: bodyGeometry(width: width, range: 0.54...0.61, padding: 0.055))
            belt.geometry?.firstMaterial = material(grass ? UIColor(red: 0.49, green: 0.67, blue: 0.26, alpha: 1) : skirtColor)
            fullCostume.addChildNode(belt)
        }

        private func costumeFlower(color: UIColor, radius: Float) -> SCNNode {
            let flower = SCNNode()
            flower.name = "costume.flower"
            for index in 0..<5 {
                let angle = Float(index) * 2 * .pi / 5
                let petal = ellipsoid(size: .init(radius * 0.58, radius * 0.80, radius * 0.28), position: .init(sin(angle) * radius * 0.65, cos(angle) * radius * 0.65, 0), color: color)
                petal.eulerAngles.z = -angle
                flower.addChildNode(petal)
            }
            flower.addChildNode(ellipsoid(size: .init(radius * 0.35, radius * 0.35, radius * 0.28), position: .init(0, 0, radius * 0.22), color: UIColor(red: 1, green: 0.77, blue: 0.32, alpha: 1)))
            return flower
        }

        private func costumeHood(color: UIColor) -> SCNNode {
            var vertices: [SCNVector3] = [], normals: [SCNVector3] = []
            var indices: [Int32] = []
            let segments = 80, sides = 12
            for index in 0...segments {
                let angle = CGFloat(index) * 2 * .pi / CGFloat(segments)
                let x = cos(angle) * 0.91, y = 1.56 + sin(angle) * 0.615
                let z = surfaceDepth(x: x, y: y) + 0.015
                for side in 0...sides {
                    let turn = CGFloat(side) * 2 * .pi / CGFloat(sides)
                    let nx = cos(angle) * cos(turn), ny = sin(angle) * cos(turn), nz = sin(turn)
                    vertices.append(.init(Float(x + nx * 0.10), Float(y + ny * 0.10), Float(z + nz * 0.10)))
                    normals.append(.init(Float(nx), Float(ny), Float(nz)))
                    if index < segments && side < sides {
                        let a = Int32(index * (sides + 1) + side), b = a + Int32(sides + 1)
                        indices += [a, b, a + 1, a + 1, b, b + 1]
                    }
                }
            }
            let mesh = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
            mesh.firstMaterial = material(color)
            mesh.firstMaterial?.isDoubleSided = true
            let hood = SCNNode(geometry: mesh)
            let shell = bodyGeometry(width: 1, range: 1.02...2.18, padding: 0.025)
            var shellIndices: [Int32] = []
            for ring in 0..<96 {
                let y = 1.02 + 1.16 * (CGFloat(ring) + 0.5) / 96
                for side in 0..<64 {
                    let angle = (CGFloat(side) + 0.5) * 2 * .pi / 64
                    let x = bodySection(at: y).x * sin(angle)
                    let faceOpening = pow(x / 0.91, 2) + pow((y - 1.56) / 0.615, 2) < 1
                    if cos(angle) > 0 && faceOpening { continue }
                    let a = Int32(ring * 65 + side), b = a + 65
                    shellIndices += [a, a + 1, b, a + 1, b + 1, b]
                }
            }
            let fabric = SCNGeometry(sources: shell.sources, elements: [SCNGeometryElement(indices: shellIndices, primitiveType: .triangles)])
            fabric.firstMaterial = material(color)
            hood.addChildNode(SCNNode(geometry: fabric))
            return hood
        }

        private func costumeBow(color: UIColor) -> SCNNode {
            let bow = SCNNode()
            bow.name = "costume.leopardBow"
            let brown = UIColor(red: 0.42, green: 0.28, blue: 0.16, alpha: 1)
            for side: Float in [-1, 1] {
                let loop = ellipsoid(size: .init(0.21, 0.14, 0.065), position: .init(side * 0.17, 0, 0), color: color, outlined: true)
                loop.eulerAngles.z = side * 0.18
                bow.addChildNode(loop)
                for index in 0..<5 {
                    let x = side * 0.17 + Float((index % 3) - 1) * 0.085
                    let y = Float(index / 3) * 0.10 - 0.045
                    let spot = ellipsoid(size: .init(0.028, 0.020, 0.008), position: .init(x, y, 0.068), color: brown)
                    spot.eulerAngles.z = Float(index) * 0.8
                    spot.addChildNode(ellipsoid(size: .init(0.52, 0.46, 0.30), position: .init(0.10, -0.05, 0.95), color: color))
                    bow.addChildNode(spot)
                }
            }
            bow.addChildNode(ellipsoid(size: .init(0.07, 0.09, 0.075), position: .init(0, 0, 0.015), color: color, outlined: true))
            return bow
        }

        private func costumeHeart() -> SCNNode {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: -0.055))
            path.addCurve(to: CGPoint(x: 0, y: 0.03), controlPoint1: CGPoint(x: -0.10, y: 0.01), controlPoint2: CGPoint(x: -0.04, y: 0.09))
            path.addCurve(to: CGPoint(x: 0, y: -0.055), controlPoint1: CGPoint(x: 0.04, y: 0.09), controlPoint2: CGPoint(x: 0.10, y: 0.01))
            path.close()
            path.flatness = 0.001
            let shape = SCNShape(path: path, extrusionDepth: 0.012)
            shape.firstMaterial = material(UIColor(red: 1, green: 0.27, blue: 0.52, alpha: 1))
            let heart = SCNNode(geometry: shape)
            heart.name = "costume.heart"
            return heart
        }

        private func costumeSparkle(color: UIColor, radius: CGFloat) -> SCNNode {
            let path = UIBezierPath()
            for index in 0..<8 {
                let angle = CGFloat(index) * .pi / 4
                let length = index.isMultiple(of: 2) ? radius : radius * 0.27
                let point = CGPoint(x: cos(angle) * length, y: sin(angle) * length)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.close()
            let shape = SCNShape(path: path, extrusionDepth: 0.012)
            shape.chamferRadius = 0.003
            shape.firstMaterial = flatMaterial(color)
            return SCNNode(geometry: shape)
        }

        private func setCostumePose(_ style: CostumeStyle?, resting: Bool, animated: Bool) {
            costumeHeldProps.isHidden = !resting
            for arm in arms { arm.childNode(withName: "costume.peace", recursively: false)?.isHidden = !resting }
            guard resting else { return }
            if style == .mermaidIsland {
                holdHands(at: 0.95, apart: 0.40)
            } else if style == .gyaru {
                for (index, arm) in arms.enumerated() {
                    let side: Float = index == 0 ? -1 : 1
                    transitionPose(arm, position: .init(arm.position.x, 1.10, 0.45), rotation: .init(-0.10, 0, side * 2.12), animated: animated)
                }
            }
        }

        private func setLowEnergyPose(animated: Bool) {
            rabbit.removeAllActions()
            rabbit.position = .init(0, -0.015, 0)
            rabbit.eulerAngles = .init(0.06, 0, 0.035)
            for (index, ear) in ears.enumerated() {
                transitionPose(ear, rotation: .init(0.07, 0, index == 0 ? -0.14 : 0.14), animated: animated)
            }
            guard animated else { return }
            rabbit.runAction(.repeatForever(.sequence([
                eased(.move(to: .init(0, -0.010, 0), duration: 2)),
                eased(.move(to: .init(0, -0.015, 0), duration: 2))
            ])), forKey: "nutrition.rest")
        }

        private func setNutritionEffect(_ mood: NutritionMood, animated: Bool, width: Float) {
            nutritionEffect.enumerateChildNodes { node, _ in node.removeAllActions() }
            nutritionEffect.childNodes.forEach { $0.removeFromParentNode() }
            guard mood == .sparkling else { return }
            let gold = UIColor(red: 0.91, green: 0.64, blue: 0.12, alpha: 1)
            for index in 0..<6 {
                let side: Float = index.isMultiple(of: 2) ? -1 : 1
                let row = index / 2
                let sparkle = costumeSparkle(color: gold, radius: row == 1 ? 0.075 : 0.05)
                sparkle.name = "nutrition.sparkle"
                sparkle.position = .init(side * (1.06 + Float(row % 2) * 0.10 + max(0, width - 1) * 0.08), 0.78 + Float(row) * 0.62, 0.15)
                nutritionEffect.addChildNode(sparkle)
                if animated {
                    sparkle.runAction(.repeatForever(.sequence([
                        .wait(duration: Double(index) * 0.12),
                        eased(.group([.fadeOpacity(to: 0.40, duration: 1.25), .scale(to: 0.72, duration: 1.25)])),
                        eased(.group([.fadeOpacity(to: 1, duration: 1.25), .scale(to: 1, duration: 1.25)]))
                    ])), forKey: "nutrition.glow")
                }
            }
        }

        private func setMotion(walking: Bool, animated: Bool) {
            let halfStep = 0.525
            let bodyStart = prepareMotion(rabbit, position: SCNVector3Zero, rotation: SCNVector3Zero, animated: animated)
            if animated {
                let breath = SCNAction.sequence([
                    eased(.move(to: SCNVector3(0, walking ? 0.009 : 0.008, 0), duration: walking ? halfStep / 2 : 1.3)),
                    eased(.move(to: SCNVector3Zero, duration: walking ? halfStep / 2 : 1.3))
                ])
                rabbit.runAction(.sequence([bodyStart, .repeatForever(breath)]), forKey: "body")
            }
            for (index, arm) in arms.enumerated() {
                let rest = Float(index == 0 ? -0.17 : 0.17)
                let swing = Float(index == 0 ? 0.14 : -0.14)
                let start = prepareMotion(arm, position: nil,
                                          rotation: SCNVector3(walking && animated ? swing : 0, 0, rest), animated: animated)
                guard animated else { continue }
                if walking {
                    let cycle = SCNAction.sequence([
                        eased(.rotateTo(x: CGFloat(-swing), y: 0, z: CGFloat(rest), duration: halfStep, usesShortestUnitArc: true)),
                        eased(.rotateTo(x: CGFloat(swing), y: 0, z: CGFloat(rest), duration: halfStep, usesShortestUnitArc: true))
                    ])
                    arm.runAction(.sequence([start, .repeatForever(cycle)]), forKey: "gait")
                } else {
                    arm.runAction(start, forKey: "settle")
                }
            }
            for (index, foot) in feet.enumerated() {
                guard let sole = foot.childNodes.first else { continue }
                let startZ: Float = walking && animated ? (index == 0 ? 0.08 : -0.08) : 0
                let start = prepareMotion(sole, position: SCNVector3(0, 0, startZ), rotation: SCNVector3Zero, animated: animated)
                guard animated else { continue }
                if walking {
                    // Feet stay outside the breathing rig, so the stance foot remains grounded.
                    let stance = SCNAction.move(to: SCNVector3(0, 0, -0.08), duration: halfStep)
                    let lift = eased(.group([
                        .move(to: SCNVector3(0, 0.045, 0), duration: halfStep / 2),
                        .rotateTo(x: -0.04, y: 0, z: 0, duration: halfStep / 2, usesShortestUnitArc: true)
                    ]))
                    let land = eased(.group([
                        .move(to: SCNVector3(0, 0, 0.08), duration: halfStep / 2),
                        .rotateTo(x: 0, y: 0, z: 0, duration: halfStep / 2, usesShortestUnitArc: true)
                    ]))
                    let cycle = SCNAction.sequence(index == 0 ? [stance, lift, land] : [lift, land, stance])
                    sole.runAction(.sequence([start, .repeatForever(cycle)]), forKey: "gait")
                } else {
                    sole.runAction(start, forKey: "settle")
                }
            }
        }

        private func setOnboardingPose(_ pose: UsagiOnboardingPose, animated: Bool, width: Float) {
            props.childNodes.forEach { $0.removeFromParentNode() }
            let shoulder = Float(bodySection(at: 0.82, width: width).x) - 0.01
            let bodyRotation: SCNVector3
            switch pose {
            case .height: bodyRotation = SCNVector3(-0.015, 0, 0)
            case .weight: bodyRotation = SCNVector3(0.025, 0.28, 0)
            case .gender: bodyRotation = SCNVector3(0, -0.12, -0.08)
            case .goal: bodyRotation = SCNVector3(-0.025, -0.12, 0.015)
            }
            transitionPose(rabbit, position: .init(0, 0, 0), rotation: bodyRotation, animated: animated)
            for (index, arm) in arms.enumerated() {
                let side: Float = index == 0 ? -1 : 1
                arm.isHidden = false
                var position = SCNVector3(side * shoulder, 0.82, 0.06)
                let rotation: SCNVector3
                switch pose {
                case .height:
                    rotation = SCNVector3(-0.15, 0, side * 2.35)
                case .weight:
                    position = SCNVector3(side * 0.20, 0.79,
                                          Float(surfaceDepth(x: 0.20, y: 0.79, width: width)) + 0.06)
                    rotation = SCNVector3(-0.65, 0, side * 0.35)
                case .gender:
                    rotation = SCNVector3(-0.20, 0, index == 0 ? -0.32 : 1.65)
                case .goal:
                    rotation = SCNVector3(index == 0 ? -0.7 : 0.4, 0, index == 0 ? -1.85 : 0.45)
                }
                transitionPose(arm, position: position, rotation: rotation, animated: animated)
            }
            for (index, ear) in ears.enumerated() {
                let side: Float = index == 0 ? -1 : 1
                let lean: Float = switch pose {
                case .height: side * 0.015
                case .weight: side * 0.09
                case .gender: index == 0 ? -0.18 : 0.04
                case .goal: side * 0.075
                }
                transitionPose(ear, rotation: SCNVector3(0, 0, lean), animated: animated)
            }
            for (index, foot) in feet.enumerated() {
                guard let sole = foot.childNodes.first else { continue }
                let stride: Float = pose == .goal ? (index == 0 ? 0.07 : -0.07) : 0
                transitionPose(sole, position: SCNVector3(0, 0, stride), rotation: .init(0, 0, 0), animated: animated)
            }
        }

        private func transitionPose(_ node: SCNNode, position: SCNVector3? = nil, rotation: SCNVector3, animated: Bool) {
            let visiblePosition = node.presentation.position
            let visibleRotation = node.presentation.eulerAngles
            node.removeAllActions()
            node.eulerAngles = animated ? visibleRotation : rotation
            if let position { node.position = animated ? visiblePosition : position }
            guard animated else { return }
            var actions: [SCNAction] = [.rotateTo(x: CGFloat(rotation.x), y: CGFloat(rotation.y), z: CGFloat(rotation.z), duration: 0.3, usesShortestUnitArc: true)]
            if let position { actions.append(.move(to: position, duration: 0.3)) }
            node.runAction(eased(.group(actions)), forKey: "onboarding.pose")
        }

        private func setReportReaction(_ reaction: HealthReportReaction, animated: Bool, width: Float) {
            switch reaction {
            case .celebrate: setOnboardingPose(.height, animated: animated, width: width)
            case .encourage: setOnboardingPose(.goal, animated: animated, width: width)
            case .curious: setOnboardingPose(.gender, animated: animated, width: width)
            case .rest:
                for (index, ear) in ears.enumerated() {
                    transitionPose(ear, rotation: SCNVector3(0, 0, index == 0 ? -0.055 : 0.055), animated: animated)
                }
                setPresentationMotion(.idle, animated: animated, width: width)
            }
            guard animated else { return }
            func repeatMotion(_ node: SCNNode, _ actions: [SCNAction]) {
                node.runAction(.sequence([.wait(duration: 0.3), .repeatForever(.sequence(actions))]), forKey: "report.reaction")
            }
            switch reaction {
            case .celebrate:
                for (index, arm) in arms.enumerated() {
                    let side: CGFloat = index == 0 ? -1 : 1
                    repeatMotion(arm, [
                        eased(.rotateTo(x: -0.15, y: 0, z: side * 2.05, duration: 0.65)),
                        eased(.rotateTo(x: -0.15, y: 0, z: side * 2.35, duration: 0.65)),
                        .wait(duration: 0.5)
                    ])
                }
            case .encourage:
                repeatMotion(rabbit, [
                    eased(.rotateTo(x: 0.05, y: -0.12, z: 0.015, duration: 0.75)),
                    eased(.rotateTo(x: -0.025, y: -0.12, z: 0.015, duration: 0.75)),
                    .wait(duration: 0.6)
                ])
            case .curious:
                repeatMotion(rabbit, [
                    eased(.rotateTo(x: 0, y: -0.12, z: 0.04, duration: 1.1)),
                    eased(.rotateTo(x: 0, y: -0.12, z: -0.08, duration: 1.1)),
                    .wait(duration: 0.7)
                ])
            case .rest: break
            }
        }

        private func setPresentationMotion(_ motion: UsagiMotion, animated: Bool, width: Float) {
            props.childNodes.forEach { $0.removeFromParentNode() }
            let shoulder = Float(bodySection(at: 0.82, width: width).x) - 0.01
            for (index, arm) in arms.enumerated() {
                arm.isHidden = false
                arm.position = SCNVector3(index == 0 ? -shoulder : shoulder, 0.82, 0.06)
            }
            setMotion(walking: motion == .walking, animated: animated)
            switch motion {
            case .idle, .walking:
                break
            case .exercising:
                for (index, arm) in arms.enumerated() {
                    arm.removeAllActions()
                    let side: CGFloat = index == 0 ? -1 : 1
                    arm.eulerAngles = SCNVector3(-0.2, 0, Float(side * 1.25))
                    if animated {
                        arm.runAction(.repeatForever(.sequence([
                            eased(.rotateTo(x: -0.2, y: 0, z: side * 0.55, duration: 0.6, usesShortestUnitArc: true)),
                            eased(.rotateTo(x: -0.2, y: 0, z: side * 1.25, duration: 0.6, usesShortestUnitArc: true))
                        ])), forKey: "stretch")
                    }
                }
            case .grazing:
                holdHands(at: 1.10, apart: 0.17)
                let grass = SCNNode()
                for side: CGFloat in [-1, 1] {
                    let leaf = UIBezierPath()
                    leaf.move(to: .zero)
                    leaf.addCurve(to: CGPoint(x: side * 0.12, y: 0.37), controlPoint1: CGPoint(x: side * 0.19, y: 0.09), controlPoint2: CGPoint(x: side * 0.18, y: 0.27))
                    leaf.addCurve(to: .zero, controlPoint1: CGPoint(x: side * 0.03, y: 0.30), controlPoint2: CGPoint(x: side * 0.01, y: 0.14))
                    leaf.close()
                    leaf.flatness = 0.001
                    let geometry = SCNShape(path: leaf, extrusionDepth: 0.018)
                    let green = flatMaterial(UIColor(red: 0.25, green: 0.55, blue: 0.22, alpha: 1))
                    green.isDoubleSided = true
                    geometry.firstMaterial = green
                    grass.addChildNode(SCNNode(geometry: geometry))
                }
                grass.position = SCNVector3(0, 1.06, 0.69)
                props.addChildNode(grass)
                if animated { grass.runAction(.repeatForever(.sequence([eased(.rotateBy(x: 0, y: 0, z: 0.10, duration: 0.3)), eased(.rotateBy(x: 0, y: 0, z: -0.10, duration: 0.3))])), forKey: "chew") }
            case .sweating:
                for index in 0..<3 {
                    let drop = ellipsoid(size: SCNVector3(0.035, 0.065, 0.025), position: SCNVector3(0.70 + Float(index) * 0.10, 1.98 - Float(index) * 0.14, 0.48), color: .systemCyan)
                    props.addChildNode(drop)
                    if animated {
                        drop.runAction(.repeatForever(.sequence([
                            .wait(duration: Double(index) * 0.16),
                            .group([.moveBy(x: 0.025, y: -0.18, z: 0, duration: 0.8), .fadeOut(duration: 0.8)]),
                            .moveBy(x: -0.025, y: 0.18, z: 0, duration: 0), .fadeIn(duration: 0), .wait(duration: 0.4)
                        ])), forKey: "sweat")
                    }
                }
            case .eating:
                holdHands(at: 0.76, apart: 0.30)
                arms[1].isHidden = true
                let bowl = SCNNode(geometry: SCNCylinder(radius: 0.29, height: 0.19))
                bowl.geometry?.firstMaterial = material(UIColor(red: 0.75, green: 0.12, blue: 0.13, alpha: 1))
                bowl.position = SCNVector3(0, 0.68, 0.69)
                props.addChildNode(bowl)
                let sauce = ellipsoid(size: SCNVector3(0.25, 0.025, 0.25), position: SCNVector3(0, 0.79, 0.69), color: .systemOrange)
                props.addChildNode(sauce)
                for index in 0..<3 {
                    sauce.addChildNode(ellipsoid(size: SCNVector3(0.27, 0.9, 0.12), position: SCNVector3(Float(index - 1) * 0.55, 0.8, Float(index % 2) * 0.35), color: UIColor(red: 1, green: 0.48, blue: 0.16, alpha: 1)))
                }
                let bite = SCNNode()
                bite.position = SCNVector3(0.12, 1.20, 0.74)
                bite.addChildNode(ellipsoid(size: SCNVector3(0.11, 0.045, 0.045), position: .init(0, 0.03, 0), color: .systemOrange, outlined: true))
                let fork = SCNNode(geometry: SCNCylinder(radius: 0.012, height: 0.20))
                fork.geometry?.firstMaterial = material(UIColor(white: 0.66, alpha: 1))
                fork.position = SCNVector3(0.07, -0.08, 0)
                bite.addChildNode(fork)
                bite.addChildNode(ellipsoid(size: SCNVector3(0.075, 0.09, 0.08), position: SCNVector3(0.08, -0.13, 0.015), color: fur, outlined: true))
                props.addChildNode(bite)
                if animated { bite.runAction(.repeatForever(.sequence([eased(.move(to: SCNVector3(0.12, 0.80, 0.78), duration: 0.65)), .wait(duration: 0.25), eased(.move(to: SCNVector3(0.12, 1.20, 0.74), duration: 0.65)), .wait(duration: 0.4)])), forKey: "dip") }
            case .drinking:
                holdHands(at: 1.10, apart: 0.18)
                let cup = SCNNode(geometry: SCNCylinder(radius: 0.16, height: 0.26))
                cup.geometry?.firstMaterial = material(UIColor(red: 0.39, green: 0.77, blue: 0.94, alpha: 1))
                cup.position = SCNVector3(0, 1.10, 0.77)
                let rim = SCNNode(geometry: SCNTorus(ringRadius: 0.16, pipeRadius: 0.015))
                rim.geometry?.firstMaterial = material(.white)
                rim.position.y = 0.13
                cup.addChildNode(rim)
                props.addChildNode(cup)
                if animated { cup.runAction(.repeatForever(.sequence([eased(.rotateTo(x: 0.28, y: 0, z: 0, duration: 0.6)), .wait(duration: 0.35), eased(.rotateTo(x: 0, y: 0, z: 0, duration: 0.6)), .wait(duration: 0.35)])), forKey: "sip") }
            }
        }

        private func holdHands(at height: Float, apart: Float) {
            for (index, arm) in arms.enumerated() {
                arm.removeAllActions()
                arm.position = SCNVector3(index == 0 ? -apart : apart, height, 0.67)
                arm.eulerAngles = SCNVector3(-0.5, 0, index == 0 ? -0.25 : 0.25)
            }
        }

        private func clearEatingStyle() {
            props.enumerateChildNodes { node, _ in
                node.removeAllActions()
                node.removeAllAnimations()
            }
            props.childNodes.forEach { $0.removeFromParentNode() }
            if let mouth = rabbit.childNode(withName: "character.mouth", recursively: false) {
                mouth.removeAllActions()
                mouth.scale = SCNVector3(1, 1, 1)
            }
        }

        private func setEatingStyle(_ style: FoodEatingStyle, animated: Bool, width: Float) {
            setPresentationMotion(.idle, animated: animated, width: width)
            for (index, ear) in ears.enumerated() {
                transitionPose(ear, rotation: SCNVector3(0, 0, index == 0 ? -0.055 : 0.055), animated: animated)
            }
            let meal = SCNNode()
            meal.name = "food.eating.\(style.rawValue)"
            props.addChildNode(meal)
            if animated, let mouth = rabbit.childNode(withName: "character.mouth", recursively: false) {
                mouth.runAction(.repeatForever(.sequence([
                    .wait(duration: 0.3),
                    .repeat(.sequence([
                        eased(foodHeight(from: 1, to: 0.65, duration: 0.18)),
                        eased(foodHeight(from: 0.65, to: 1, duration: 0.18))
                    ]), count: 3), .wait(duration: 1.72)
                ])), forKey: "food.chew")
            }
            if style == .grass {
                holdHands(at: 1.10, apart: 0.17)
                let leaves = SCNNode()
                leaves.name = "food.leaves"
                leaves.position = SCNVector3(0, 1.06, 0.77)
                for side: CGFloat in [-1, 1] {
                    let path = UIBezierPath()
                    path.move(to: .zero)
                    path.addCurve(to: CGPoint(x: side * 0.20, y: 0.29), controlPoint1: CGPoint(x: side * 0.24, y: 0.06), controlPoint2: CGPoint(x: side * 0.25, y: 0.23))
                    path.addCurve(to: .zero, controlPoint1: CGPoint(x: side * 0.06, y: 0.30), controlPoint2: CGPoint(x: side * 0.02, y: 0.12))
                    path.close()
                    path.flatness = 0.001
                    let shape = SCNShape(path: path, extrusionDepth: 0.018)
                    shape.firstMaterial = material(UIColor(red: 0.23, green: 0.57, blue: 0.20, alpha: 1))
                    shape.firstMaterial?.isDoubleSided = true
                    leaves.addChildNode(SCNNode(geometry: shape))
                    let vein = UIBezierPath()
                    vein.move(to: .zero)
                    vein.addQuadCurve(to: CGPoint(x: side * 0.19, y: 0.27), controlPoint: CGPoint(x: side * 0.08, y: 0.16))
                    let stem = stroke(vein, width: 0.012, color: UIColor(red: 0.63, green: 0.77, blue: 0.33, alpha: 1))
                    stem.position.z = 0.02
                    leaves.addChildNode(stem)
                }
                meal.addChildNode(leaves)
                if animated {
                    leaves.runAction(.repeatForever(.sequence([
                        eased(.move(to: SCNVector3(0, 1.13, 0.72), duration: 0.45)),
                        .repeat(.sequence([eased(.rotateTo(x: 0, y: 0, z: 0.07, duration: 0.18)), eased(.rotateTo(x: 0, y: 0, z: -0.04, duration: 0.18))]), count: 3),
                        eased(.move(to: SCNVector3(0, 1.02, 0.77), duration: 0.65)),
                        .wait(duration: 0.92)
                    ])), forKey: "food.bite")
                    leaves.runAction(.repeatForever(.sequence([
                        .wait(duration: 0.45), eased(foodHeight(from: 1, to: 0.60, duration: 1.08)),
                        .wait(duration: 0.65), eased(foodHeight(from: 0.60, to: 1, duration: 0.30)), .wait(duration: 0.62)
                    ])), forKey: "food.consume")
                }
                return
            }

            holdHands(at: 0.83, apart: 0.33)
            arms[1].isHidden = true
            let red = UIColor(red: 0.86, green: 0.19, blue: 0.10, alpha: 1)
            let bowl = SCNNode(geometry: SCNCone(topRadius: 0.34, bottomRadius: 0.23, height: 0.23))
            bowl.name = "food.bowl"
            bowl.position = SCNVector3(-0.06, 0.72, 0.80)
            bowl.geometry?.firstMaterial = material(style == .tteokbokki ? red : style == .rice ? UIColor(red: 0.28, green: 0.56, blue: 0.46, alpha: 1) : navy)
            let rim = SCNNode(geometry: SCNTorus(ringRadius: 0.33, pipeRadius: 0.022))
            rim.position.y = 0.115
            rim.geometry?.firstMaterial = material(UIColor(white: 0.96, alpha: 1))
            bowl.addChildNode(rim)
            let foodColor = style == .tteokbokki ? red : style == .rice ? UIColor.white : UIColor(red: 1, green: 0.84, blue: 0.42, alpha: 1)
            bowl.addChildNode(ellipsoid(size: SCNVector3(0.305, style == .rice ? 0.08 : 0.025, 0.305), position: SCNVector3(0, 0.12, 0), color: foodColor))
            meal.addChildNode(bowl)

            let utensil = SCNNode()
            utensil.name = "food.utensil"
            utensil.position = SCNVector3(0.045, 1.25, 0.79)
            meal.addChildNode(utensil)
            let bite = SCNNode()
            bite.name = "food.bite"
            utensil.addChildNode(bite)
            if style == .noodles {
                for index in 0..<5 {
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: -0.21, y: CGFloat(index) * 0.055 - 0.10))
                    path.addCurve(to: CGPoint(x: 0.21, y: CGFloat(index) * 0.05 - 0.10), controlPoint1: CGPoint(x: -0.10, y: CGFloat(index) * 0.05 - 0.20), controlPoint2: CGPoint(x: 0.08, y: CGFloat(index) * 0.05 + 0.03))
                    let curl = stroke(path, width: 0.027, color: foodColor)
                    curl.eulerAngles.x = -.pi / 2
                    curl.position.y = 0.15
                    bowl.addChildNode(curl)
                }
                bite.name = "food.noodles"
                for index in 0..<4 {
                    let path = UIBezierPath()
                    let x = CGFloat(index) * 0.035 - 0.045
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addCurve(to: CGPoint(x: x - 0.035, y: -0.36), controlPoint1: CGPoint(x: x + 0.045, y: -0.12), controlPoint2: CGPoint(x: x - 0.06, y: -0.24))
                    bite.addChildNode(stroke(path, width: 0.018, color: foodColor))
                }
                for offset: CGFloat in [-0.025, 0.025] {
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: -0.08, y: offset))
                    path.addLine(to: CGPoint(x: 0.38, y: -0.10 + offset))
                    utensil.addChildNode(stroke(path, width: 0.018, color: UIColor(red: 0.55, green: 0.31, blue: 0.12, alpha: 1)))
                }
            } else {
                for index in 0..<9 {
                    let piece = ellipsoid(size: style == .rice ? SCNVector3(0.028, 0.019, 0.055) : SCNVector3(0.055, 0.035, 0.12), position: SCNVector3(Float(index % 3 - 1) * 0.15, 0.16 + Float(index % 2) * 0.012, Float(index / 3 - 1) * 0.13), color: style == .rice ? .white : UIColor(red: 1, green: 0.39, blue: 0.18, alpha: 1))
                    piece.eulerAngles.y = Float(index) * 0.6
                    bowl.addChildNode(piece)
                }
                let handle = UIBezierPath()
                handle.move(to: CGPoint(x: 0.03, y: -0.025))
                handle.addLine(to: CGPoint(x: 0.37, y: -0.14))
                utensil.addChildNode(stroke(handle, width: 0.022, color: UIColor(white: 0.65, alpha: 1)))
                if style == .rice {
                    utensil.addChildNode(ellipsoid(size: SCNVector3(0.105, 0.018, 0.065), position: SCNVector3(-0.015, -0.027, 0), color: UIColor(white: 0.72, alpha: 1)))
                    bite.addChildNode(ellipsoid(size: SCNVector3(0.085, 0.04, 0.055), position: .init(0, 0.012, 0), color: .white))
                } else {
                    let riceCake = ellipsoid(size: SCNVector3(0.12, 0.05, 0.05), position: .init(0, 0.015, 0), color: UIColor(red: 1, green: 0.34, blue: 0.12, alpha: 1), outlined: true)
                    riceCake.eulerAngles.z = -0.20
                    bite.addChildNode(riceCake)
                }
            }
            utensil.addChildNode(ellipsoid(size: SCNVector3(0.075, 0.085, 0.075), position: SCNVector3(0.30, -0.12, 0.025), color: fur, outlined: true))
            if animated {
                utensil.runAction(.repeatForever(.sequence([
                    .wait(duration: 0.90), eased(.move(to: SCNVector3(0.05, 0.91, 0.87), duration: 0.65)),
                    .wait(duration: 0.45), eased(.move(to: SCNVector3(0.045, 1.25, 0.79), duration: 0.75)), .wait(duration: 0.35)
                ])), forKey: "food.scoop")
                let refill: [SCNAction] = style == .noodles ? [
                    .fadeIn(duration: 0.20), .wait(duration: 0.20),
                    eased(foodHeight(from: 0.12, to: 1, duration: 0.75)), .wait(duration: 0.35)
                ] : [.scale(to: 1, duration: 0), .fadeIn(duration: 0.20), .wait(duration: 1.30)]
                bite.runAction(.repeatForever(.sequence([
                    .wait(duration: 0.15), eased(foodHeight(from: 1, to: style == .noodles ? 0.12 : 0.35, duration: 0.65)),
                    .fadeOut(duration: 0.10), .wait(duration: 0.70)
                ] + refill)), forKey: style == .noodles ? "food.slurp" : "food.consume")
            }
        }

        private func foodHeight(from: Float, to: Float, duration: TimeInterval) -> SCNAction {
            .customAction(duration: duration) { node, elapsed in
                node.scale.y = from + (to - from) * Float(min(1, Double(elapsed) / duration))
            }
        }

        private func setWater(level: Double, width: Float, animated: Bool) {
            waterWave.removeAllAnimations()
            waterWave.morpher = nil
            waterWave.geometry = nil
            guard level > 0 else { return }
            let geometry = waterGeometry(level: level, width: width, phase: 0)
            let paint = flatMaterial(UIColor(red: 0.10, green: 0.59, blue: 0.86, alpha: 1))
            paint.transparency = 0.32
            paint.isDoubleSided = true
            paint.writesToDepthBuffer = false
            geometry.firstMaterial = paint
            waterWave.geometry = geometry
            let morpher = SCNMorpher()
            morpher.targets = [waterGeometry(level: level, width: width, phase: .pi)]
            waterWave.morpher = morpher
            if animated {
                let ripple = CABasicAnimation(keyPath: "morpher.weights[0]")
                ripple.fromValue = 0
                ripple.toValue = 1
                ripple.duration = 1.15
                ripple.autoreverses = true
                ripple.repeatCount = .infinity
                ripple.usesSceneTimeBase = true
                waterWave.addAnimation(ripple, forKey: "ripple")
            }
        }

        private func waterGeometry(level: Double, width: Float, phase: CGFloat) -> SCNGeometry {
            let rows = 12, columns = 24
            var vertices: [SCNVector3] = []
            var indices: [Int32] = []
            for row in 0...rows {
                for column in 0...columns {
                    let across = CGFloat(column) / CGFloat(columns)
                    let surface = 0.18 + CGFloat(level) * 0.78 + sin(across * 2 * .pi + phase) * 0.018
                    let y = 0.15 + (surface - 0.15) * CGFloat(row) / CGFloat(rows)
                    let x = (across * 2 - 1) * bodySection(at: y, width: width).x * 0.75
                    vertices.append(SCNVector3(Float(x), Float(y), Float(surfaceDepth(x: x, y: y, width: width) + 0.045)))
                    if row < rows && column < columns {
                        let a = Int32(row * (columns + 1) + column), b = a + Int32(columns + 1)
                        indices += [a, a + 1, b, a + 1, b + 1, b]
                    }
                }
            }
            return SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        }

        private func prepareMotion(_ node: SCNNode, position: SCNVector3?, rotation: SCNVector3, animated: Bool) -> SCNAction {
            let visiblePosition = node.presentation.position
            let visibleRotation = node.presentation.eulerAngles
            node.removeAllActions()
            node.eulerAngles = animated ? visibleRotation : rotation
            if let position { node.position = animated ? visiblePosition : position }
            var actions: [SCNAction] = [
                .rotateTo(x: CGFloat(rotation.x), y: CGFloat(rotation.y), z: CGFloat(rotation.z), duration: 0.18, usesShortestUnitArc: true)
            ]
            if let position { actions.append(.move(to: position, duration: 0.18)) }
            return eased(.group(actions))
        }

        private func makeLightsAndCamera() {
            let lens = SCNCamera()
            lens.usesOrthographicProjection = true
            lens.orthographicScale = 1.85
            lens.zNear = 0.1
            lens.zFar = 30
            lens.wantsHDR = false
            camera.camera = lens
            camera.position = SCNVector3(0, 2.7, 7.5)
            camera.look(at: SCNVector3(0, 1.53, 0))
            scene.rootNode.addChildNode(camera)
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.color = UIColor.white
            ambient.light?.intensity = 650
            scene.rootNode.addChildNode(ambient)
            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .directional
            key.light?.intensity = 500
            key.eulerAngles = SCNVector3(-0.45, -0.55, 0)
            scene.rootNode.addChildNode(key)
        }

        private func frameCharacter() {
            let isUsagi = character == .usagi
            // Keep raised, stronger arms inside portrait snapshots for the compact characters.
            camera.camera?.orthographicScale = isUsagi ? 1.85 : 1.65 + Double(muscleLevel) * 0.20
            camera.position = SCNVector3(0, isUsagi ? 2.7 : 2.45, 7.5)
            camera.look(at: SCNVector3(0, isUsagi ? 1.53 : 1.26, 0))
        }

        private func material(_ color: UIColor) -> SCNMaterial {
            let result = SCNMaterial()
            result.diffuse.contents = color
            result.lightingModel = .lambert
            result.roughness.contents = 0.8
            result.metalness.contents = 0
            return result
        }

        private func ellipsoid(size: SCNVector3, position: SCNVector3, color: UIColor, outlined: Bool = false) -> SCNNode {
            let sphere = SCNSphere(radius: 1)
            sphere.segmentCount = 40
            let node = SCNNode(geometry: sphere)
            node.scale = size
            node.position = position
            sphere.firstMaterial = material(color)
            if outlined { addOutline(to: node, scale: 1.035) }
            return node
        }

        private func stroke(_ path: UIBezierPath, width: CGFloat, color: UIColor) -> SCNNode {
            let outline = path.cgPath.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1)
            let smoothPath = UIBezierPath(cgPath: outline)
            smoothPath.flatness = 0.001
            let geometry = SCNShape(path: smoothPath, extrusionDepth: 0.016)
            geometry.chamferRadius = 0.005
            geometry.firstMaterial = material(color)
            return SCNNode(geometry: geometry)
        }

        private func flatMaterial(_ color: UIColor) -> SCNMaterial {
            let result = material(color)
            result.lightingModel = .constant
            return result
        }

        private func outlinedGeometry(_ geometry: SCNGeometry) -> SCNGeometry? {
            guard let hull = geometry.copy() as? SCNGeometry else { return nil }
            let edge = flatMaterial(ink)
            edge.cullMode = .front
            hull.materials = [edge]
            return hull
        }

        private func addOutline(to node: SCNNode, scale: Float) {
            guard let geometry = node.geometry else { return }
            let hull = SCNNode(geometry: outlinedGeometry(geometry))
            hull.scale = SCNVector3(scale, scale, scale)
            node.addChildNode(hull)
        }

        // The profile follows the official front silhouette; depth remains a 3D interpretation.
        private let usagiProfile: [(y: CGFloat, x: CGFloat, z: CGFloat)] = [
            (0.10, 0.001, 0.001), (0.17, 0.32, 0.26), (0.30, 0.51, 0.37),
            (0.50, 0.65, 0.46), (0.72, 0.73, 0.50), (0.88, 0.77, 0.53),
            (1.04, 0.88, 0.57), (1.27, 1.00, 0.62), (1.48, 1.02, 0.64),
            (1.70, 0.94, 0.60), (1.90, 0.77, 0.50), (2.06, 0.49, 0.34),
            (2.16, 0.19, 0.13), (2.18, 0.001, 0.001)
        ]

        private let compactProfile: [(y: CGFloat, x: CGFloat, z: CGFloat)] = [
            (0.10, 0.001, 0.001), (0.17, 0.36, 0.26), (0.30, 0.54, 0.37),
            (0.50, 0.66, 0.46), (0.72, 0.73, 0.50), (0.88, 0.76, 0.53),
            (1.04, 0.90, 0.57), (1.27, 1.00, 0.62), (1.48, 1.02, 0.64),
            (1.70, 0.99, 0.62), (1.90, 0.87, 0.52), (2.06, 0.62, 0.37),
            (2.16, 0.28, 0.17), (2.18, 0.001, 0.001)
        ]

        private func bodySection(at y: CGFloat, width: Float = 1) -> (x: CGFloat, z: CGFloat) {
            let bodyProfile = character == .usagi ? usagiProfile : compactProfile
            let index = min(bodyProfile.count - 2, max(0, bodyProfile.lastIndex(where: { $0.y <= y }) ?? 0))
            let a = bodyProfile[index]
            let b = bodyProfile[index + 1]
            let before = bodyProfile[max(0, index - 1)]
            let after = bodyProfile[min(bodyProfile.count - 1, index + 2)]
            let t = min(1, max(0, (y - a.y) / (b.y - a.y)))
            func interpolate(_ p0: CGFloat, _ p1: CGFloat, _ p2: CGFloat, _ p3: CGFloat) -> CGFloat {
                let m1 = (p2 - p0) / (b.y - before.y) * (b.y - a.y)
                let m2 = (p3 - p1) / (after.y - a.y) * (b.y - a.y)
                return max(0.001, (2 * t * t * t - 3 * t * t + 1) * p1 + (t * t * t - 2 * t * t + t) * m1 + (-2 * t * t * t + 3 * t * t) * p2 + (t * t * t - t * t) * m2)
            }
            var radiusX = interpolate(before.x, a.x, b.x, after.x)
            var radiusZ = interpolate(before.z, a.z, b.z, after.z)
            if y < 0.30 {
                // Interpolating squared radii closes the belly with a round pole instead of a cone.
                let u = min(1, max(0, (y - 0.10) / 0.20))
                func rounded(_ radius: CGFloat, slope: CGFloat) -> CGFloat {
                    let squared = radius * radius
                    return max(0.001, sqrt(max(0, (-2 * u * u * u + 3 * u * u) * squared
                        + (u * u * u - 2 * u * u + u) * 2 * squared
                        + (u * u * u - u * u) * 2 * radius * slope * 0.20)))
                }
                let edge = bodyProfile[2]
                radiusX = rounded(edge.x, slope: (bodyProfile[3].x - bodyProfile[1].x) / (bodyProfile[3].y - bodyProfile[1].y))
                radiusZ = rounded(edge.z, slope: (bodyProfile[3].z - bodyProfile[1].z) / (bodyProfile[3].y - bodyProfile[1].y))
            }
            let blend = min(1, max(0, (y - 0.35) / 0.80))
            let lowerBodyWeight = 1 - blend * blend * (3 - 2 * blend)
            let strengthBlend = min(1, max(0, (y - 0.35) / 0.75))
            let strength = muscleLevel * pow(sin(.pi * strengthBlend), 2)
            let head = headFactor(at: y)
            return (radiusX * 1.055 * (1 + CGFloat(width - 1) * lowerBodyWeight + strength * 0.12) * head,
                    radiusZ * (1 + strength * 0.16) * head)
        }

        private func headFactor(at y: CGFloat) -> CGFloat {
            guard character == .usagi else { return 1 }
            // Blend into the cheek profile without changing the lower body or creating a neck seam.
            let t = min(1, max(0, (y - 1.04) / 0.23))
            return 1 - 0.04 * t * t * (3 - 2 * t)
        }

        private func bodyGeometry(width: Float, range: ClosedRange<CGFloat> = 0.10...2.18, padding: CGFloat = 0) -> SCNGeometry {
            let rings = 96
            let sides = 64
            var vertices: [SCNVector3] = []
            var normals: [SCNVector3] = []
            var indices: [Int32] = []
            for ring in 0...rings {
                let y = range.lowerBound + (range.upperBound - range.lowerBound) * CGFloat(ring) / CGFloat(rings)
                let section = bodySection(at: y, width: width)
                let low = bodySection(at: max(0.10, y - 0.002), width: width)
                let high = bodySection(at: min(2.18, y + 0.002), width: width)
                let span = max(0.001, min(2.18, y + 0.002) - max(0.10, y - 0.002))
                let dx = (high.x - low.x) / span
                let dz = (high.z - low.z) / span
                let rx = section.x + padding
                let rz = section.z + padding
                for side in 0...sides {
                    let angle = CGFloat(side) / CGFloat(sides) * 2 * .pi
                    let sine = sin(angle), cosine = cos(angle)
                    vertices.append(SCNVector3(Float(rx * sine), Float(y), Float(rz * cosine)))
                    let nx = sine / rx, ny = -(dx * sine * sine / rx + dz * cosine * cosine / rz), nz = cosine / rz
                    let length = sqrt(nx * nx + ny * ny + nz * nz)
                    normals.append(SCNVector3(Float(nx / length), Float(ny / length), Float(nz / length)))
                    if ring < rings && side < sides {
                        let a = Int32(ring * (sides + 1) + side)
                        let b = a + Int32(sides + 1)
                        indices += [a, a + 1, b, a + 1, b + 1, b]
                    }
                }
            }
            return SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
                               elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        }

        private func surfaceDepth(x: CGFloat, y: CGFloat, width: Float = 1) -> CGFloat {
            let section = bodySection(at: y, width: width)
            return section.z * sqrt(max(0.001, 1 - x * x / (section.x * section.x)))
        }

        private func cubic(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> [CGPoint] {
            (0...20).map { index in
                let t = CGFloat(index) / 20, u = 1 - t
                return CGPoint(x: u * u * u * a.x + 3 * u * u * t * b.x + 3 * u * t * t * c.x + t * t * t * d.x,
                               y: u * u * u * a.y + 3 * u * u * t * b.y + 3 * u * t * t * c.y + t * t * t * d.y)
            }
        }

        private func surfaceStroke(_ controlPoints: [CGPoint], thickness: CGFloat, color: UIColor, width: Float = 1, padding: CGFloat = 0.014) -> SCNNode {
            var points: [CGPoint] = []
            for (a, b) in zip(controlPoints, controlPoints.dropFirst()) {
                let steps = max(1, Int(ceil(hypot(b.x - a.x, b.y - a.y) / 0.025)))
                for step in 0..<steps {
                    let t = CGFloat(step) / CGFloat(steps)
                    points.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                }
            }
            if let last = controlPoints.last { points.append(last) }
            var vertices: [SCNVector3] = []
            var indices: [Int32] = []
            for index in points.indices {
                let point = points[index]
                let before = points[max(0, index - 1)], after = points[min(points.count - 1, index + 1)]
                let dx = after.x - before.x, dy = after.y - before.y
                let length = max(0.001, hypot(dx, dy))
                for sign: CGFloat in [-1, 1] {
                    let y = point.y + sign * dx / length * thickness / 2
                    let x = (point.x - sign * dy / length * thickness / 2) * headFactor(at: y)
                    vertices.append(SCNVector3(Float(x), Float(y), Float(surfaceDepth(x: x, y: y, width: width) + padding)))
                }
                if index < points.count - 1 {
                    let a = Int32(index * 2)
                    indices += [a, a + 2, a + 1, a + 1, a + 2, a + 3]
                }
            }
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
            let paint = flatMaterial(color)
            paint.isDoubleSided = true
            geometry.firstMaterial = paint
            let node = SCNNode(geometry: geometry)
            for point in [points.first, points.last].compactMap({ $0 }) {
                let cap = ellipsoid(size: SCNVector3(Float(thickness / 2), Float(thickness / 2), 0.003), position: SCNVector3(Float(point.x * headFactor(at: point.y)), Float(point.y), Float(surfaceDepth(x: point.x * headFactor(at: point.y), y: point.y, width: width) + padding)), color: color)
                cap.geometry?.firstMaterial = paint
                node.addChildNode(cap)
            }
            return node
        }

        private func surfacePatch(center: CGPoint, radius: CGSize, color: UIColor) -> SCNNode {
            let points = (0..<40).map { index in
                let angle = CGFloat(index) / 40 * 2 * .pi
                return CGPoint(x: center.x + cos(angle) * radius.width, y: center.y + sin(angle) * radius.height)
            }
            return surfacePolygon(points, color: color, padding: 0.010)
        }

        private func surfacePolygon(_ points: [CGPoint], color: UIColor, width: Float = 1, padding: CGFloat = 0.033) -> SCNNode {
            let center = CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count), y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
            let all = [center] + points
            let vertices = all.map {
                let x = $0.x * headFactor(at: $0.y)
                return SCNVector3(Float(x), Float($0.y), Float(surfaceDepth(x: x, y: $0.y, width: width) + padding))
            }
            var indices: [Int32] = []
            for index in points.indices { indices += [0, Int32(index + 1), Int32((index + 1) % points.count + 1)] }
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
            let paint = flatMaterial(color)
            paint.isDoubleSided = true
            geometry.firstMaterial = paint
            return SCNNode(geometry: geometry)
        }

        private func eased(_ action: SCNAction) -> SCNAction {
            action.timingMode = .easeInEaseOut
            return action
        }
    }
}

#Preview {
    MapUsagiView(bodyScale: 1.15, outfit: .student, isWalking: true)
        .frame(width: 180, height: 230)
        .background(Color(red: 0.88, green: 0.93, blue: 0.83))
}
