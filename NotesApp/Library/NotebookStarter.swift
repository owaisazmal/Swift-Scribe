import Foundation

/// One-tap combinations of cover and paper in New Notebook. Everything they set stays editable.
enum NotebookStarter: String, CaseIterable, Identifiable {
    case journal, lecture, sketchbook, planner, music, plain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .journal: String(localized: "Journal")
        case .lecture: String(localized: "Lecture")
        case .sketchbook: String(localized: "Sketchbook")
        case .planner: String(localized: "Planner")
        case .music: String(localized: "Music")
        case .plain: String(localized: "Plain")
        }
    }

    /// What a notebook made from this starter is called until it's given a title.
    var notebookTitle: String { self == .plain ? String(localized: "Untitled Notebook") : title }

    var template: PaperTemplate {
        switch self {
        case .journal: .dotted
        case .lecture: .cornell
        case .sketchbook: .blank
        case .planner: .weekPlanner
        case .music: .music
        case .plain: UserDefaults.standard.string(forKey: SettingsKey.defaultTemplate).flatMap(PaperTemplate.init(rawValue:)) ?? .narrowRuled
        }
    }

    var paperColor: PaperColor {
        switch self {
        case .lecture, .sketchbook: .white
        case .journal, .planner, .music: .ivory
        case .plain: UserDefaults.standard.string(forKey: SettingsKey.defaultPaperColor).flatMap(PaperColor.init(rawValue:)) ?? .white
        }
    }

    var coverStyle: CoverStyle { self == .sketchbook ? .print : .cloth }

    /// Nil for Plain, which takes the notebook's seeded cloth.
    var cloth: ClothColor? {
        switch self {
        case .journal: .moss
        case .lecture: .navy
        case .planner: .mustard
        case .music: .oxblood
        case .sketchbook, .plain: nil
        }
    }

    var inks: (RisoInk, RisoInk) { self == .sketchbook ? (.pink, .yellow) : RisoInk.pairs[0] }

    func spec(for id: UUID) -> CoverSpec {
        CoverSpec(style: coverStyle, cloth: cloth ?? .seeded(by: id), inks: inks, seed: CoverSpec.seed(from: id))
    }

    func accessibilityLabel(for id: UUID) -> String {
        let spec = spec(for: id)
        let paper = "\(template.displayName) \(paperColor.displayName)".lowercased()
        let cover = spec.style == .print
            ? String(localized: "\(spec.inks.0.displayName.lowercased()) and \(spec.inks.1.displayName.lowercased()) print")
            : String(localized: "\(spec.cloth.displayName.lowercased()) cloth")
        return String(localized: "\(title) starter: \(paper) paper, \(cover)")
    }
}

enum CoverShuffle {
    /// Another cloth for Cloth and First page covers; a new pattern in another pair of inks for Print.
    static func next(_ spec: CoverSpec, using rng: inout some RandomNumberGenerator) -> CoverSpec {
        var next = spec
        switch spec.style {
        case .cloth, .firstPage:
            next.cloth = ClothColor.allCases.filter { $0 != spec.cloth }.randomElement(using: &rng) ?? spec.cloth
        case .print:
            repeat { next.seed = UInt32.random(in: 0...UInt32.max, using: &rng) } while next.seed == spec.seed
            let current = RisoInk.pairs.firstIndex { $0.0 == spec.inks.0 && $0.1 == spec.inks.1 }
            if let index = RisoInk.pairs.indices.filter({ $0 != current }).randomElement(using: &rng) { next.inks = RisoInk.pairs[index] }
        }
        return next
    }
}
