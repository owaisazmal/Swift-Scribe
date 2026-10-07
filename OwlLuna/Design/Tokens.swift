import SwiftUI

/// 4-point spacing grid.
enum Space {
    static let x1: CGFloat = 4
    static let x2: CGFloat = 8
    static let x3: CGFloat = 12
    static let x4: CGFloat = 16
    static let x5: CGFloat = 20
    static let x6: CGFloat = 24
    static let x8: CGFloat = 32
    static let x10: CGFloat = 40
    static let x12: CGFloat = 48
}

enum Radius {
    /// Covers: nearly square, a touch rounder on the fore-edge.
    static let coverSpine: CGFloat = 2
    static let coverEdge: CGFloat = 5
    static let control: CGFloat = 12
}

enum Motion {
    static let standard = Animation.easeOut(duration: 0.18)
    static let quick = Animation.easeOut(duration: 0.15)
    static let ribbon = Animation.spring(response: 0.34, dampingFraction: 0.62)

    /// Everything becomes a short cross-fade when Reduce Motion is on.
    static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : animation
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

extension ClothColor {
    var color: Color { Color(hex: hex) }
    var uiColor: UIColor { UIColor(hex: hex) }

    /// Text on the cloth itself (the page ribbon): white on dark cloths, ink on mustard, rose and oat,
    /// whichever reaches 4.5:1.
    var onCloth: Color {
        switch self {
        case .mustard, .rose, .oat: Color(hex: 0x1B2230)
        default: .white
        }
    }
}

extension View {
    /// The filled cloth button that finishes a task.
    func prominentButton(compact: Bool = false) -> some View {
        buttonStyle(.owlLuna(.primary, compact: compact))
    }
}

extension RisoInk {
    var uiColor: UIColor { UIColor(hex: hex) }
}
