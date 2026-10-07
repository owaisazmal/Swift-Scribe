import Foundation
import CoreGraphics

enum PaperTemplate: String, Codable, CaseIterable, Identifiable {
    case blank, narrowRuled, wideRuled, grid, dotted, cornell, music
    case engineering, isometric, checklist, penmanship, dayPlanner, weekPlanner, storyboard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blank: String(localized: "Blank")
        case .narrowRuled: String(localized: "Narrow Ruled")
        case .wideRuled: String(localized: "Wide Ruled")
        case .grid: String(localized: "Grid")
        case .dotted: String(localized: "Dotted")
        case .cornell: String(localized: "Cornell")
        case .music: String(localized: "Music Staff")
        case .engineering: String(localized: "Engineering")
        case .isometric: String(localized: "Isometric")
        case .checklist: String(localized: "Checklist")
        case .penmanship: String(localized: "Penmanship")
        case .dayPlanner: String(localized: "Day Planner")
        case .weekPlanner: String(localized: "Week Planner")
        case .storyboard: String(localized: "Storyboard")
        }
    }

    var family: PaperFamily { PaperFamily.allCases.first { $0.templates.contains(self) } ?? .writing }
}

/// How paper is grouped wherever it's listed.
enum PaperFamily: String, CaseIterable, Identifiable {
    case writing, grids, planning, creative

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .writing: String(localized: "Writing")
        case .grids: String(localized: "Grids")
        case .planning: String(localized: "Planning")
        case .creative: String(localized: "Creative")
        }
    }

    var templates: [PaperTemplate] {
        switch self {
        case .writing: [.blank, .narrowRuled, .wideRuled, .penmanship, .checklist]
        case .grids: [.grid, .engineering, .dotted, .isometric]
        case .planning: [.cornell, .dayPlanner, .weekPlanner]
        case .creative: [.music, .storyboard]
        }
    }
}

enum PaperColor: String, Codable, CaseIterable, Identifiable {
    case white, ivory, yellow, kraft, sage, blush, gray, charcoal, chalkboard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .white: String(localized: "White")
        case .ivory: String(localized: "Ivory")
        case .yellow: String(localized: "Legal Pad")
        case .gray: String(localized: "Gray")
        case .charcoal: String(localized: "Charcoal")
        case .kraft: String(localized: "Kraft")
        case .sage: String(localized: "Sage")
        case .blush: String(localized: "Blush")
        case .chalkboard: String(localized: "Chalkboard")
        }
    }

    var rgb: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .white: (1, 1, 1)
        case .ivory: (0.992, 0.976, 0.925)
        case .yellow: (1, 0.973, 0.765)
        case .gray: (0.925, 0.929, 0.937)
        case .charcoal: (0.165, 0.169, 0.184)
        case .kraft: (0.851, 0.769, 0.627)
        case .sage: (0.867, 0.898, 0.843)
        case .blush: (0.965, 0.894, 0.878)
        case .chalkboard: (0.169, 0.243, 0.212)
        }
    }

    var isDark: Bool { self == .charcoal || self == .chalkboard }
}

enum PageSize: String, Codable, CaseIterable, Identifiable {
    case letter, a4, a5, widescreen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .letter: String(localized: "US Letter")
        case .a4: String(localized: "A4")
        case .a5: String(localized: "A5")
        case .widescreen: String(localized: "Widescreen")
        }
    }

    var points: CGSize {
        switch self {
        case .letter: CGSize(width: 612, height: 792)
        case .a4: CGSize(width: 595.28, height: 841.89)
        case .a5: CGSize(width: 419.53, height: 595.28)
        case .widescreen: CGSize(width: 960, height: 540)
        }
    }
}
