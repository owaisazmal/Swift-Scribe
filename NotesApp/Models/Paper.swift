import Foundation
import CoreGraphics

enum PaperTemplate: String, Codable, CaseIterable, Identifiable {
    case blank, narrowRuled, wideRuled, grid, dotted, cornell, music
    case engineering, isometric, checklist, penmanship, dayPlanner, weekPlanner, storyboard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blank: "Blank"
        case .narrowRuled: "Narrow Ruled"
        case .wideRuled: "Wide Ruled"
        case .grid: "Grid"
        case .dotted: "Dotted"
        case .cornell: "Cornell"
        case .music: "Music Staff"
        case .engineering: "Engineering"
        case .isometric: "Isometric"
        case .checklist: "Checklist"
        case .penmanship: "Penmanship"
        case .dayPlanner: "Day Planner"
        case .weekPlanner: "Week Planner"
        case .storyboard: "Storyboard"
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
        case .writing: "Writing"
        case .grids: "Grids"
        case .planning: "Planning"
        case .creative: "Creative"
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
        case .white: "White"
        case .ivory: "Ivory"
        case .yellow: "Legal Pad"
        case .gray: "Gray"
        case .charcoal: "Charcoal"
        case .kraft: "Kraft"
        case .sage: "Sage"
        case .blush: "Blush"
        case .chalkboard: "Chalkboard"
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
        case .letter: "US Letter"
        case .a4: "A4"
        case .a5: "A5"
        case .widescreen: "Widescreen"
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
