import REPickShared
import SwiftUI

enum OnboardingPalette {
    static let background = Color(red: 246 / 255, green: 247 / 255, blue: 248 / 255)
    static let cream = Color.white
    static let control = Color(red: 242 / 255, green: 243 / 255, blue: 245 / 255)
    static let ink = Color(red: 59 / 255, green: 48 / 255, blue: 32 / 255)
    static let secondary = Color(red: 102 / 255, green: 84 / 255, blue: 58 / 255)
    static let accent = Color(red: 120 / 255, green: 89 / 255, blue: 22 / 255)
    static let continueFill = Color(red: 249 / 255, green: 225 / 255, blue: 148 / 255)
    static let error = Color(red: 180 / 255, green: 35 / 255, blue: 24 / 255)
}

struct OnboardingBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(stops: [
                    .init(color: OnboardingPalette.cream, location: 0),
                    .init(color: Color(red: 250 / 255, green: 250 / 255, blue: 251 / 255), location: 0.48),
                    .init(color: OnboardingPalette.background, location: 1)
                ], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color.white.opacity(0.45), .clear],
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
            .font(AppFont.font(.body, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: Design.controlHeight)
            .foregroundStyle(isEnabled ? OnboardingPalette.ink : OnboardingPalette.secondary)
            .background(
                isEnabled ? OnboardingPalette.continueFill.opacity(configuration.isPressed ? 0.85 : 1) : OnboardingPalette.control,
                in: RoundedRectangle(cornerRadius: Design.controlRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Design.controlRadius)
                    .strokeBorder(OnboardingPalette.accent.opacity(isEnabled ? 0.6 : 0.2), lineWidth: 1)
            }
    }
}
