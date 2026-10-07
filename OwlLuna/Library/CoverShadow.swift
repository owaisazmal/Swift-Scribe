import SwiftUI

/// The contact and ambient shadow under a cover, drawn once into a stretchable plate so nothing is shaded live.
enum CoverShadowPlate {
    private static let light = make(dark: false, highContrast: false)
    private static let lightContrast = make(dark: false, highContrast: true)
    private static let night = make(dark: true, highContrast: false)
    private static let nightContrast = make(dark: true, highContrast: true)

    static func image(dark: Bool, highContrast: Bool) -> UIImage {
        switch (dark, highContrast) {
        case (false, false): light
        case (false, true): lightContrast
        case (true, false): night
        case (true, true): nightContrast
        }
    }

    /// 72 pt square with a 40 pt cover shape at inset 16; the shape itself is cleared, leaving only its shadow.
    private static func make(dark: Bool, highContrast: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 72, height: 72), format: format).image { context in
            let ctx = context.cgContext
            let shape = UIBezierPath(roundedRect: CGRect(x: 16, y: 16, width: 40, height: 40), cornerRadius: 4).cgPath
            let contact = (dark ? 0.45 : 0.22) * (highContrast ? 1.3 : 1)
            for (offset, blur, alpha) in [(1.5, 2.0, contact), (6.0, 10.0, dark ? 0.3 : 0.1)] {
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: offset), blur: blur, color: UIColor(white: 0, alpha: alpha).cgColor)
                ctx.setFillColor(UIColor.black.cgColor)
                ctx.addPath(shape)
                ctx.fillPath()
                ctx.restoreGState()
            }
            ctx.setBlendMode(.clear)
            ctx.addPath(shape)
            ctx.fillPath()
        }
    }
}

/// Sits behind a cover, reaching 16 pt past it on every side.
struct CoverShadowView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Image(uiImage: CoverShadowPlate.image(dark: colorScheme == .dark, highContrast: contrast == .increased))
            .resizable(capInsets: EdgeInsets(top: 28, leading: 28, bottom: 28, trailing: 28), resizingMode: .stretch)
            .padding(-16)
            .accessibilityHidden(true)
    }
}
