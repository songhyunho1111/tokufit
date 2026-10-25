#if canImport(SwiftUI) && canImport(CoreText)
import CoreText
import Foundation
import OSLog
import SwiftUI

public enum AppFont {
    private static let logger = Logger(subsystem: "dev.repick", category: "Typography")
    private static let registrationSucceeded: Bool = {
        let results = ["GmarketSansMedium", "GmarketSansBold"].map { name in
            guard let url = Bundle.module.url(forResource: name, withExtension: "otf") else {
                logger.error("Missing bundled font \(name, privacy: .public) in \(Bundle.module.bundlePath, privacy: .public)")
                return false
            }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            let font = CTFontCreateWithName(name as CFString, 17, nil)
            let resolved = CTFontCopyPostScriptName(font) as String
            guard resolved == name else {
                let reason = error?.takeRetainedValue().localizedDescription ?? "Resolved \(resolved)"
                logger.error("Could not register \(name, privacy: .public): \(reason, privacy: .public)")
                return false
            }
            if let error { _ = error.takeRetainedValue() }
            return true
        }
        return results.allSatisfy { $0 }
    }()

    /// Each app and extension has its own font registry. Lazy initialization also covers previews and exports.
    @discardableResult
    public static func register() -> Bool {
        registrationSucceeded
    }

    public static func postScriptName(weight: Font.Weight = .medium) -> String {
        switch weight {
        case .semibold, .bold, .heavy, .black: "GmarketSansBold"
        default: "GmarketSansMedium"
        }
    }

    public static func font(_ style: Font.TextStyle, weight: Font.Weight = .medium) -> Font {
        register()
        return .custom(postScriptName(weight: weight), size: baseSize(for: style), relativeTo: style)
    }

    /// Only for artwork exports or a layout whose entire coordinate system scales together.
    public static func fixed(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        register()
        return .custom(postScriptName(weight: weight), fixedSize: size)
    }

    private static func baseSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }
}
#endif
