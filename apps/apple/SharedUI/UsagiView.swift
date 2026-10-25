import REPickShared
import SwiftUI

enum UsagiMotion: String, CaseIterable, Identifiable {
    case idle, walking, exercising, grazing, sweating, eating, drinking

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .idle: "쉬는 우사기"
        case .walking: "걷는 우사기"
        case .exercising: "운동하는 우사기"
        case .grazing: "풀 뜯어먹는 우사기"
        case .sweating: "땀 흘리는 우사기"
        case .eating: "떡볶이 먹는 우사기"
        case .drinking: "물을 마시는 우사기"
        }
    }

    fileprivate func frame(at time: Double) -> Int {
        switch self {
        case .idle: 0
        case .walking: 1
        case .exercising: 2
        case .grazing: 3
        case .sweating: 4
        case .eating: Int(time / 0.7) % 2 == 0 ? 5 : 7
        case .drinking: 6
        }
    }
}

struct UsagiView: View {
    var bodyScale: Double = 1
    var outfit: Outfit = .basic
    var motion: UsagiMotion = .idle
    var waterLevel: Double = 0
    var isAnimating = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var canAnimate: Bool { isAnimating && !reduceMotion && scenePhase == .active }

    private var atlasName: String {
        switch outfit {
        case .basic: "UsagiBasic"
        case .student: "UsagiStudent"
        case .office: "UsagiOffice"
        case .sport: "UsagiSport"
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !canAnimate)) { timeline in
            Canvas { context, size in
                let time = canAnimate ? timeline.date.timeIntervalSinceReferenceDate : 0
                let scale = min(1.6, max(0.75, bodyScale.isFinite ? bodyScale : 1))
                let water = min(1, max(0, waterLevel.isFinite ? waterLevel : 0))
                // shortcut: scale the whole sprite until separate torso layers are available.
                let width = 0.85 + (scale - 0.75) / 0.85 * 0.30
                let sprite = context.resolve(Image(atlasName).interpolation(.high))
                draw(sprite, in: context, size: size, time: time, width: width, water: water)
            }
        }
        .aspectRatio(0.8, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(motion.label)
    }

    private func draw(
        _ sprite: GraphicsContext.ResolvedImage,
        in context: GraphicsContext,
        size: CGSize,
        time: Double,
        width: Double,
        water: Double
    ) {
        let side = min(size.height, size.width / 0.8) * 0.95
        let frame = motion.frame(at: time)
        // shortcut: single-pose motions sway until additional articulated frames are available.
        let energetic = motion == .walking || motion == .exercising
        let rhythm = sin(time * (energetic ? 6 : 2))
        let bounce = energetic ? -abs(rhythm) * side * 0.015 : rhythm * side * 0.003
        let angle = energetic ? rhythm * 1.5 : rhythm * 0.45
        let mirror = motion == .walking && Int(time / 0.45) % 2 == 1 ? -1.0 : 1.0
        var drawing = context
        drawing.translateBy(x: size.width / 2, y: size.height / 2 + bounce)
        drawing.rotate(by: .degrees(angle))
        drawing.scaleBy(x: width * mirror, y: 1)
        drawing.translateBy(x: -side / 2, y: -side / 2)

        // The source atlas stays intact; clipping selects one square from its 4 × 2 grid.
        drawing.clip(to: Path(CGRect(x: 0, y: 0, width: side, height: side)))
        drawing.draw(sprite, in: CGRect(
            x: -Double(frame % 4) * side,
            y: -Double(frame / 4) * side,
            width: side * 4,
            height: side * 2
        ))
        if water > 0, motion != .eating {
            drawWater(in: drawing, side: side, level: water, time: time)
        }
    }

    private func drawWater(in context: GraphicsContext, side: Double, level: Double, time: Double) {
        let belly = CGRect(x: side * 0.40, y: side * 0.74, width: side * 0.24, height: side * 0.14)
        var water = context
        water.clip(to: Path(ellipseIn: belly))
        let wave = WaterSurface(level: level, phase: time * 1.8).path(in: belly)
        water.fill(wave, with: .color(Color(red: 0.12, green: 0.64, blue: 0.87).opacity(0.30)))
        let glint = CGRect(x: belly.midX - side * 0.065, y: belly.maxY - side * 0.035, width: side * 0.014, height: side * 0.014)
        water.fill(Path(ellipseIn: glint), with: .color(.white.opacity(0.55)))
    }
}

private struct WaterSurface: Shape {
    var level: Double
    var phase: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let surface = rect.maxY - rect.height * level
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for step in 0...24 {
            let fraction = Double(step) / 24
            path.addLine(to: CGPoint(
                x: rect.minX + rect.width * fraction,
                y: surface + sin(fraction * .pi * 2 + phase) * rect.height * 0.055
            ))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview("Usagi sprites") {
    HStack {
        UsagiView(outfit: .student, motion: .grazing)
        UsagiView(bodyScale: 1.5, outfit: .office, motion: .eating)
        UsagiView(outfit: .sport, motion: .exercising, waterLevel: 0.65)
    }
    .frame(height: 220)
    .padding()
    .background(Color(red: 0.98, green: 0.97, blue: 0.93))
}
