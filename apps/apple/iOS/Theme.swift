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
    static let repickCream = adaptive(0xF5F6F1, 0x141A16)
    static let repickSurface = adaptive(0xFFFFFF, 0x202821)
    static let repickInk = adaptive(0x243128, 0xEEF2EA)
    static let repickSecondaryText = adaptive(0x5F6B61, 0xAFBBAF)
    static let repickGreen = adaptive(0x38543C, 0xB5D0AA)
    static let repickYellow = adaptive(0xF1CC67, 0xF1CC67)
    static let repickBorder = adaptive(0xDDE3D9, 0x3D493D)
    static let repickActionFill = adaptive(0x38543C, 0xB5D0AA)
    static let repickActionInk = adaptive(0xFFFFFF, 0x142018)
    static let repickRewardInk = adaptive(0x352C12, 0x352C12)
    static let repickRewardSurface = adaptive(0xF8EDCA, 0x453B24)
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
            .font(.body.weight(.semibold))
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
            .font(.subheadline.weight(.semibold)).monospacedDigit()
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
            .font(.subheadline.weight(.semibold))
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
