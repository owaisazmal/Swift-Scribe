import Foundation
import CoreGraphics

enum PaperTemplate: String, Codable, CaseIterable, Identifiable {
    case blank, narrowRuled, wideRuled, grid, dotted, cornell, music

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
        }
    }
}

enum PaperColor: String, Codable, CaseIterable, Identifiable {
    case white, ivory, yellow, gray, charcoal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .white: "White"
        case .ivory: "Ivory"
        case .yellow: "Legal Pad"
        case .gray: "Gray"
        case .charcoal: "Charcoal"
        }
    }

    var rgb: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .white: (1, 1, 1)
        case .ivory: (0.992, 0.976, 0.925)
        case .yellow: (1, 0.973, 0.765)
        case .gray: (0.925, 0.929, 0.937)
        case .charcoal: (0.165, 0.169, 0.184)
        }
    }

    var isDark: Bool { self == .charcoal }
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
