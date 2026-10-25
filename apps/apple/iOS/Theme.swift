import REPickShared
import SwiftUI
import UIKit

enum Design {
    static let pagePadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 24
    static let cardPadding: CGFloat = 16
    static let cardRadius: CGFloat = 20
    static let controlRadius: CGFloat = 14
    static let controlHeight: CGFloat = 48
    static let contentWidth: CGFloat = 640
}

extension Color {
    static let repickCream = adaptive(0xFAFAFA, 0x1C1C1E)
    static let repickSurface = adaptive(0xFFFFFF, 0x2C2C2E)
    static let repickInk = adaptive(0x3B3020, 0xFEEFCE)
    static let repickSecondaryText = adaptive(0x66543A, 0xD8C8A9)
    static let repickGold = adaptive(0x785916, 0xF9E194)
    static let repickGreen = repickGold
    static let repickYellow = adaptive(0xF9E194, 0xF9E194)
    static let repickBorder = adaptive(0xE5E5E7, 0x48484A)
    static let repickActionFill = adaptive(0xF9E194, 0xF9E194)
    static let repickActionInk = adaptive(0x3B3020, 0x3B3020)
    static let repickRewardInk = adaptive(0x3B3020, 0x3B3020)
    static let repickRewardSurface = adaptive(0xF3DBA7, 0x4B3D22)
    static let repickDanger = adaptive(0xB42318, 0xFFB4A9)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}

@MainActor
enum AppTypographyAppearance {
    static func configure() {
        AppFont.register()
        let title = scaledFont(.headline, size: 17, weight: .bold)
        let largeTitle = scaledFont(.largeTitle, size: 34, weight: .bold)
        let navigation = UINavigationBarAppearance()
        navigation.configureWithDefaultBackground()
        navigation.titleTextAttributes = [.font: title]
        navigation.largeTitleTextAttributes = [.font: largeTitle]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation

        let tabs = UITabBarAppearance()
        tabs.configureWithDefaultBackground()
        for layout in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
            for state in [layout.normal, layout.selected, layout.disabled, layout.focused] {
                state.titleTextAttributes = [.font: scaledFont(.caption2, size: 11)]
            }
        }
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: scaledFont(.body, size: 17)], for: .normal)
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: scaledFont(.body, size: 17)], for: .disabled)
    }

    private static func scaledFont(_ style: UIFont.TextStyle, size: CGFloat, weight: Font.Weight = .medium) -> UIFont {
        guard let font = UIFont(name: AppFont.postScriptName(weight: weight), size: size) else {
            return .preferredFont(forTextStyle: style)
        }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
    }
}

struct PaperCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(Design.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.repickSurface, in: RoundedRectangle(cornerRadius: Design.cardRadius))
            .overlay { RoundedRectangle(cornerRadius: Design.cardRadius).strokeBorder(Color.repickBorder, lineWidth: 0.5) }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.font(.body, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: Design.controlHeight)
            .foregroundStyle(isEnabled ? Color.repickActionInk : Color.repickSecondaryText)
            .background(
                isEnabled ? Color.repickActionFill.opacity(configuration.isPressed ? 0.85 : 1) : Color.repickBorder,
                in: RoundedRectangle(cornerRadius: Design.controlRadius)
            )
    }
}

struct PointBadge: View {
    let points: Int
    var body: some View {
        Text("\(points.formatted())P")
            .font(AppFont.font(.subheadline, weight: .semibold)).monospacedDigit()
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(Color.repickInk)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.repickRewardSurface, in: Capsule())
            .accessibilityLabel(Text("보유 포인트 \(points)"))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.font(.subheadline, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: Design.controlHeight)
            .foregroundStyle(isEnabled ? Color.repickGreen : Color.repickSecondaryText)
            .background(Color.repickSurface, in: RoundedRectangle(cornerRadius: Design.controlRadius))
            .overlay { RoundedRectangle(cornerRadius: Design.controlRadius).strokeBorder(Color.repickBorder, lineWidth: 0.5) }
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct PointsToolbar: ToolbarContent {
    let points: Int

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarTrailing) { PointBadge(points: points) }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarTrailing) { PointBadge(points: points) }
        }
    }
}
