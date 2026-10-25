import SwiftUI

struct CompanionRoomView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let dark = colorScheme == .dark
            let wall = dark ? Color(red: 0.16, green: 0.23, blue: 0.20) : Color(red: 0.83, green: 0.87, blue: 0.78)
            let wood = dark ? Color(red: 0.30, green: 0.25, blue: 0.20) : Color(red: 0.71, green: 0.57, blue: 0.42)
            let trim = dark ? Color(red: 0.44, green: 0.42, blue: 0.33) : Color(red: 0.95, green: 0.91, blue: 0.79)
            let floorY = height * 0.69

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(wall))
            context.fill(Path(CGRect(x: 0, y: floorY, width: width, height: height - floorY)), with: .color(wood))
            context.fill(Path(CGRect(x: 0, y: floorY - 4, width: width, height: 5)), with: .color(trim))

            var boards = Path()
            for fraction in [0.0, 0.25, 0.50, 0.75, 1.0] {
                boards.move(to: CGPoint(x: width * 0.5 + (fraction - 0.5) * width * 0.55, y: floorY + 5))
                boards.addLine(to: CGPoint(x: width * fraction, y: height))
            }
            for fraction in [0.80, 0.94] {
                boards.move(to: CGPoint(x: 0, y: height * fraction))
                boards.addLine(to: CGPoint(x: width, y: height * fraction))
            }
            context.stroke(boards, with: .color(.black.opacity(dark ? 0.12 : 0.07)), lineWidth: 1)

            let window = CGRect(x: width * 0.055, y: height * 0.10, width: width * 0.23, height: height * 0.34)
            let windowShape = Path(roundedRect: window, cornerRadius: 8)
            var sky = context
            sky.clip(to: windowShape)
            sky.fill(windowShape, with: .linearGradient(
                Gradient(colors: dark
                    ? [Color(red: 0.12, green: 0.23, blue: 0.33), Color(red: 0.27, green: 0.40, blue: 0.44)]
                    : [Color(red: 0.63, green: 0.81, blue: 0.85), Color(red: 0.91, green: 0.95, blue: 0.86)]),
                startPoint: CGPoint(x: window.midX, y: window.minY),
                endPoint: CGPoint(x: window.midX, y: window.maxY)))
            sky.fill(Path(ellipseIn: CGRect(x: window.maxX - 24, y: window.minY + 13, width: 15, height: 15)),
                     with: .color(Color(red: 1, green: 0.93, blue: 0.68).opacity(dark ? 0.80 : 1)))
            var hill = Path()
            hill.move(to: CGPoint(x: window.minX, y: window.maxY))
            hill.addLine(to: CGPoint(x: window.minX, y: window.maxY - 18))
            hill.addQuadCurve(to: CGPoint(x: window.maxX, y: window.maxY - 12),
                             control: CGPoint(x: window.midX, y: window.maxY - 37))
            hill.addLine(to: CGPoint(x: window.maxX, y: window.maxY))
            hill.closeSubpath()
            sky.fill(hill, with: .color(Color(red: 0.38, green: 0.55, blue: 0.42)))
            context.stroke(windowShape, with: .color(trim), lineWidth: 5)
            var mullions = Path()
            mullions.move(to: CGPoint(x: window.midX, y: window.minY))
            mullions.addLine(to: CGPoint(x: window.midX, y: window.maxY))
            mullions.move(to: CGPoint(x: window.minX, y: window.midY))
            mullions.addLine(to: CGPoint(x: window.maxX, y: window.midY))
            context.stroke(mullions, with: .color(trim), lineWidth: 3)
            context.fill(Path(roundedRect: CGRect(x: window.minX - 5, y: window.minY - 3,
                                                 width: width * 0.035, height: window.height + 10), cornerRadius: 3),
                         with: .color(trim))
            context.fill(Path(roundedRect: CGRect(x: window.minX - 6, y: window.maxY + 2,
                                                 width: window.width + 12, height: 6), cornerRadius: 2),
                         with: .color(wood))

            let shelf = CGRect(x: width * 0.76, y: height * 0.43, width: width * 0.19, height: 6)
            context.fill(Path(roundedRect: shelf, cornerRadius: 2), with: .color(wood))
            let bookColors = [Color(red: 0.61, green: 0.65, blue: 0.50), Color(red: 0.70, green: 0.44, blue: 0.36)]
            for index in 0..<2 {
                context.fill(Path(roundedRect: CGRect(x: shelf.minX + CGFloat(index) * 9 + 5,
                                                     y: shelf.minY - 27 + CGFloat(index) * 4,
                                                     width: 7, height: 27 - CGFloat(index) * 4), cornerRadius: 1),
                             with: .color(bookColors[index]))
            }
            let plantX = shelf.maxX - 17
            let plantY = shelf.minY - 17
            var stem = Path()
            stem.move(to: CGPoint(x: plantX, y: plantY + 5))
            stem.addQuadCurve(to: CGPoint(x: plantX - 2, y: plantY - 24),
                             control: CGPoint(x: plantX + 4, y: plantY - 8))
            context.stroke(stem, with: .color(Color(red: 0.25, green: 0.42, blue: 0.28)), lineWidth: 2)
            for side in [-1.0, 1.0] {
                context.fill(Path(ellipseIn: CGRect(x: plantX + side * 9 - 7, y: plantY - (side > 0 ? 23 : 16), width: 14, height: 8)),
                             with: .color(Color(red: 0.33, green: 0.51, blue: 0.34)))
            }
            context.fill(Path(roundedRect: CGRect(x: plantX - 10, y: plantY, width: 20, height: 17), cornerRadius: 4),
                         with: .color(Color(red: 0.70, green: 0.48, blue: 0.34)))

            let rug = CGRect(x: width * 0.23, y: height * 0.78, width: width * 0.54, height: height * 0.14)
            context.fill(Path(ellipseIn: rug), with: .color(dark
                ? Color(red: 0.42, green: 0.46, blue: 0.35)
                : Color(red: 0.88, green: 0.86, blue: 0.68)))
            context.stroke(Path(ellipseIn: rug.insetBy(dx: 7, dy: 4)), with: .color(trim.opacity(0.55)), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
