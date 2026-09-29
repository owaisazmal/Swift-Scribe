import Foundation

enum CoverStyle: String, CaseIterable, Identifiable, Sendable {
    case cloth, print, firstPage

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cloth: "Cloth"
        case .print: "Print"
        case .firstPage: "First page"
        }
    }
}

enum ClothColor: String, CaseIterable, Identifiable, Sendable {
    case oxblood, tomato, mustard, moss, jade, cobalt, navy, slate, rose, oat

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    var hex: UInt32 {
        switch self {
        case .oxblood: 0x6E2A2A
        case .tomato: 0xC9452F
        case .mustard: 0xD6A02A
        case .moss: 0x3D5A40
        case .jade: 0x2F7D6B
        case .cobalt: 0x2F4DA0
        case .navy: 0x1E2A45
        case .slate: 0x56606B
        case .rose: 0xC98A86
        case .oat: 0xCDBF9F
        }
    }

    static func seeded(by id: UUID) -> ClothColor {
        allCases[Int(id.uuid.0 ^ id.uuid.15) % allCases.count]
    }
}

enum RisoInk: String, CaseIterable, Identifiable, Sendable {
    case pink, yellow, teal, blue, black

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pink: "Fluorescent pink"
        case .yellow: "Yellow"
        case .teal: "Teal"
        case .blue: "Riso blue"
        case .black: "Black"
        }
    }

    var hex: UInt32 {
        switch self {
        case .pink: 0xFF48B0
        case .yellow: 0xFFE800
        case .teal: 0x00838A
        case .blue: 0x0078BF
        case .black: 0x1C1C21
        }
    }

    static let paperStock: UInt32 = 0xF7F4EC

    static let pairs: [(RisoInk, RisoInk)] = [
        (.teal, .blue), (.pink, .yellow), (.blue, .yellow), (.teal, .pink), (.black, .pink), (.blue, .pink),
    ]
}

struct CoverSpec: Sendable, Hashable {
    var styleRaw: String
    var clothRaw: String
    var inksRaw: [String]
    var seed: UInt32
    var extra: [String: JSONValue] = [:]
    var undecoded: [String: UndecodedField] = [:]

    init(style: CoverStyle, cloth: ClothColor, inks: (RisoInk, RisoInk), seed: UInt32) {
        styleRaw = style.rawValue
        clothRaw = cloth.rawValue
        inksRaw = [inks.0.rawValue, inks.1.rawValue]
        self.seed = seed
    }

    init(styleRaw: String, clothRaw: String, inksRaw: [String], seed: UInt32, extra: [String: JSONValue] = [:],
         undecoded: [String: UndecodedField] = [:]) {
        self.styleRaw = styleRaw
        self.clothRaw = clothRaw
        self.inksRaw = inksRaw
        self.seed = seed
        self.extra = extra
        self.undecoded = undecoded
    }

    var style: CoverStyle {
        get { CoverStyle(rawValue: styleRaw) ?? .cloth }
        set { styleRaw = newValue.rawValue }
    }

    var cloth: ClothColor {
        get { ClothColor(rawValue: clothRaw) ?? .slate }
        set { clothRaw = newValue.rawValue }
    }

    var inks: (RisoInk, RisoInk) {
        get {
            let known = inksRaw.compactMap(RisoInk.init(rawValue:))
            return (known.first ?? .teal, known.dropFirst().first ?? .blue)
        }
        set { inksRaw = [newValue.0.rawValue, newValue.1.rawValue] }
    }

    static func defaultCloth(for id: UUID) -> CoverSpec {
        CoverSpec(style: .cloth, cloth: .seeded(by: id), inks: RisoInk.pairs[0], seed: seed(from: id))
    }

    static func seed(from id: UUID) -> UInt32 {
        let bytes = id.uuid
        return UInt32(bytes.1) << 24 | UInt32(bytes.5) << 16 | UInt32(bytes.9) << 8 | UInt32(bytes.13)
    }
}
