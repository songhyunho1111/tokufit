import Foundation

public enum CostumeStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case mermaidIsland, pajamas, gyaru
    public var id: String { rawValue }
    public var price: Int { 500 }
    public var name: String {
        switch self {
        case .mermaidIsland: String(localized: "costume.mermaidIsland", defaultValue: "인어섬", bundle: .module)
        case .pajamas: String(localized: "costume.pajamas", defaultValue: "파자마", bundle: .module)
        case .gyaru: String(localized: "costume.gyaru", defaultValue: "갸루", bundle: .module)
        }
    }
}

public struct CharacterCostume: Codable, Hashable, Identifiable, Sendable {
    public let character: CharacterKind
    public let style: CostumeStyle
    public var id: String { "\(character.rawValue).\(style.rawValue)" }
    public var name: String { style.name }
    public var price: Int { style.price }

    public init(character: CharacterKind, style: CostumeStyle) {
        self.character = character
        self.style = style
    }
}
