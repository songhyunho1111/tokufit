#if canImport(SwiftUI) && canImport(CoreText)
import CoreText
import SwiftUI
import Testing
@testable import REPickShared

@Test func bundledGmarketFontsRegisterWithRealPostScriptNames() {
    #expect(AppFont.register())
    #expect(AppFont.register())
    for weight: Font.Weight in [.medium, .bold] {
        let name = AppFont.postScriptName(weight: weight)
        let font = CTFontCreateWithName(name as CFString, 17, nil)
        #expect(CTFontCopyPostScriptName(font) as String == name)
        #expect(CTFontGetGlyphCount(font) > 11_000)
        let characters = Array("출석체크 오늘 기록 RE:PICK 0123456789".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        #expect(CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count))
    }
    #expect(AppFont.postScriptName(weight: .medium) != AppFont.postScriptName(weight: .bold))
    #expect(AppFont.postScriptName(weight: .semibold) == AppFont.postScriptName(weight: .bold))
}
#endif
