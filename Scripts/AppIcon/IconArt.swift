import CoreGraphics

extension OwlLunaTheme {
    var name: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    var setName: String { self == .cobalt ? "AppIcon" : "AppIcon-\(name)" }
}

/// The light icon is opaque with its sky; dark and tinted are the owl and moon alone, over the system's own backdrop.
func icon(_ theme: OwlLunaTheme, _ appearance: OwlLunaAppearance, size: Int = 1024) -> CGImage {
    let ctx = bitmap(size, size, opaque: appearance == .light)
    OwlLunaArt.draw(in: ctx, size: CGFloat(size), palette: .icon(theme, appearance), includesSky: appearance == .light)
    return ctx.makeImage()!
}

// MARK: Colour

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    OwlLunaRGBA(hex: hex, alpha: alpha).cgColor
}

func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [white, white, white, alpha])!
}
