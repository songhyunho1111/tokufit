import SwiftUI

enum OnboardingPalette {
    static let night = Color(red: 4 / 255, green: 12 / 255, blue: 9 / 255)
    static let control = Color(red: 23 / 255, green: 52 / 255, blue: 42 / 255)
    static let ivory = Color(red: 239 / 255, green: 245 / 255, blue: 238 / 255)
    static let secondary = Color(red: 182 / 255, green: 200 / 255, blue: 189 / 255)
    static let accent = Color(red: 189 / 255, green: 229 / 255, blue: 203 / 255)
    static let continueFill = Color(red: 217 / 255, green: 235 / 255, blue: 221 / 255)
    static let error = Color(red: 1, green: 0.74, blue: 0.68)
}

struct OnboardingBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(stops: [
                    .init(color: Color(red: 24 / 255, green: 61 / 255, blue: 50 / 255), location: 0),
                    .init(color: Color(red: 11 / 255, green: 37 / 255, blue: 30 / 255), location: 0.48),
                    .init(color: OnboardingPalette.night, location: 1)
                ], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(red: 58 / 255, green: 112 / 255, blue: 87 / 255).opacity(0.24), .clear],
                               center: UnitPoint(x: 0.5, y: 0.28), startRadius: 0,
                               endRadius: max(geometry.size.width, geometry.size.height * 0.55))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct OnboardingContinueStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: Design.controlHeight)
            .foregroundStyle(isEnabled ? OnboardingPalette.night : OnboardingPalette.secondary)
            .background(
                isEnabled ? OnboardingPalette.continueFill.opacity(configuration.isPressed ? 0.85 : 1) : OnboardingPalette.control,
                in: RoundedRectangle(cornerRadius: Design.controlRadius)
            )
    }
}
