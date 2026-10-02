import UIKit

extension TapeColor {
    var displayName: String {
        switch self {
        case .mustard: String(localized: "Mustard")
        case .rose: String(localized: "Rose")
        case .sage: String(localized: "Sage")
        case .sky: String(localized: "Sky")
        }
    }

    var fill: UIColor {
        switch self {
        case .mustard: UIColor(hex: 0xE8B023)
        case .rose: UIColor(hex: 0xE89AA6)
        case .sage: UIColor(hex: 0x8DBF99)
        case .sky: UIColor(hex: 0x8FA9E6)
        }
    }

    var edge: UIColor {
        switch self {
        case .mustard: UIColor(hex: 0x8A6410)
        case .rose: UIColor(hex: 0x9C4455)
        case .sage: UIColor(hex: 0x3D6B49)
        case .sky: UIColor(hex: 0x3A4F94)
        }
    }
}

/// Study tape: a strip of washi tape with pinked ends that hides what is under it. Lifted, only its outline is left,
/// so what it covered can be read and the tape can be found again. Thread-safe.
enum TapeArt {
    static let defaultSize = CGSize(width: 200, height: 30)

    static func outline(in rect: CGRect) -> CGPath {
        let teeth = max(3, Int((rect.height / 6).rounded())), step = rect.height / CGFloat(teeth)
        let depth = min(step * 0.6, rect.width / 8)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        for tooth in 0..<teeth {
            path.addLine(to: CGPoint(x: rect.maxX - depth, y: rect.minY + (CGFloat(tooth) + 0.5) * step))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + CGFloat(tooth + 1) * step))
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        for tooth in 0..<teeth {
            path.addLine(to: CGPoint(x: rect.minX + depth, y: rect.maxY - (CGFloat(tooth) + 0.5) * step))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - CGFloat(tooth + 1) * step))
        }
        path.closeSubpath()
        return path
    }

    /// Draws in a y-down context.
    static func draw(_ color: TapeColor, lifted: Bool = false, in ctx: CGContext, rect: CGRect) {
        let unit = max(rect.height / defaultSize.height, 0.2)
        let shape = outline(in: rect)
        ctx.saveGState()
        defer { ctx.restoreGState() }
        if lifted {
            ctx.addPath(shape)
            ctx.setFillColor(color.fill.withAlphaComponent(0.14).cgColor)
            ctx.fillPath()
            ctx.addPath(shape)
            ctx.setStrokeColor(color.edge.cgColor)
            ctx.setLineWidth(1.5 * unit)
            ctx.setLineJoin(.round)
            ctx.setLineDash(phase: 0, lengths: [5 * unit, 4 * unit])
            ctx.strokePath()
            return
        }
        ctx.addPath(shape)
        ctx.clip()
        ctx.setFillColor(color.fill.cgColor)
        ctx.fill(rect)
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.32).cgColor)
        ctx.setLineWidth(4 * unit)
        let lean = rect.height * 0.8, gap = 14 * unit
        var x = rect.minX - lean
        while x < rect.maxX {
            ctx.move(to: CGPoint(x: x, y: rect.maxY))
            ctx.addLine(to: CGPoint(x: x + lean, y: rect.minY))
            x += gap
        }
        ctx.strokePath()
        ctx.setFillColor(color.edge.withAlphaComponent(0.22).cgColor)
        ctx.fill(CGRect(x: rect.minX, y: rect.maxY - 2 * unit, width: rect.width, height: 2 * unit))
    }
}
