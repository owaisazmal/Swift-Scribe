import Foundation

/// One-tap combinations of cover and paper in New Notebook. Everything they set stays editable.
enum NotebookStarter: String, CaseIterable, Identifiable {
    case journal, whiteboard, lecture, sketchbook, planner, music, plain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .journal: String(localized: "Journal")
        case .lecture: String(localized: "Lecture")
        case .sketchbook: String(localized: "Sketchbook")
        case .planner: String(localized: "Planner")
        case .music: String(localized: "Music")
        case .whiteboard: String(localized: "Whiteboard")
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
        case .whiteboard: .dotted
        case .plain: UserDefaults.standard.string(forKey: SettingsKey.defaultTemplate).flatMap(PaperTemplate.init(rawValue:)) ?? .narrowRuled
        }
    }

    var paperColor: PaperColor {
        switch self {
        case .lecture, .sketchbook, .whiteboard: .white
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
        case .whiteboard: .slate
        case .sketchbook, .plain: nil
        }
    }

    /// The notebook opens on a whiteboard rather than a page, while its paper is one a board can have.
    func startsWithBoard(template: PaperTemplate) -> Bool { self == .whiteboard && Whiteboard.templates.contains(template) }

    var inks: (RisoInk, RisoInk) { self == .sketchbook ? (.pink, .yellow) : RisoInk.pairs[0] }

    func spec(for id: UUID) -> CoverSpec {
        CoverSpec(style: coverStyle, cloth: cloth ?? .seeded(by: id), inks: inks, seed: CoverSpec.seed(from: id))
    }

    func accessibilityLabel(for id: UUID) -> String {
        let spec = spec(for: id)
        // Names are lowercased mid-sentence in English only; German keeps its nouns capitalised.
        let english = Bundle.main.preferredLocalizations.first?.hasPrefix("en") ?? true
        func name(_ text: String) -> String { english ? text.lowercased() : text }
        let paper = name("\(template.displayName) \(paperColor.displayName)")
        let cover = spec.style == .print
            ? String(localized: "\(name(spec.inks.0.displayName)) and \(name(spec.inks.1.displayName)) print")
            : String(localized: "\(name(spec.cloth.displayName)) cloth")
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
