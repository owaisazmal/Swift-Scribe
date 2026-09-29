import XCTest
import SwiftUI
@testable import NotesApp

final class DesignTokenTests: XCTestCase {
    private func luminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    private func contrast(_ a: UIColor, _ b: UIColor) -> CGFloat {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// Every pair of colours that carries text, in light, dark and both Increase Contrast variants, reaches 4.5:1.
    func testEveryTextPairReachesAA() {
        let pairs: [(String, UIColor, UIColor)] = [
            ("ink/paper", .ink, .paper), ("ink/desk", .ink, .desk), ("ink/surface", .ink, .surface),
            ("secondary/paper", .inkSecondary, .paper), ("secondary/desk", .inkSecondary, .desk), ("secondary/surface", .inkSecondary, .surface),
            ("tint/paper", .accent, .paper), ("tint/desk", .accent, .desk), ("tint/surface", .accent, .surface),
            ("onTomato/tomato", .onTomato, .tomato), ("onMustard/mustard", .onMustard, .mustard),
            ("labelInk/labelCream", .labelInk, .labelCream), ("labelSecondary/labelCream", .labelInkSecondary, .labelCream),
        ]
        var report: [String] = []
        for style in [UIUserInterfaceStyle.light, .dark] {
            for contrastLevel in [UIAccessibilityContrast.normal, .high] {
                let traits = UITraitCollection { $0.userInterfaceStyle = style; $0.accessibilityContrast = contrastLevel }
                for (name, foreground, background) in pairs {
                    let ratio = contrast(foreground.resolvedColor(with: traits), background.resolvedColor(with: traits))
                    report.append("\(style == .dark ? "dark" : "light")\(contrastLevel == .high ? "+HC" : "") \(name) \(String(format: "%.2f", ratio))")
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name) in \(style == .dark ? "dark" : "light")\(contrastLevel == .high ? " high contrast" : "")")
                }
            }
        }
        print("CONTRAST\n" + report.joined(separator: "\n"))
    }

    func testIncreaseContrastStrengthensSecondaryText() {
        let normal = UITraitCollection { $0.userInterfaceStyle = .light }
        let high = UITraitCollection { $0.userInterfaceStyle = .light; $0.accessibilityContrast = .high }
        XCTAssertGreaterThan(contrast(UIColor.inkSecondary.resolvedColor(with: high), UIColor.paper.resolvedColor(with: high)),
                             contrast(UIColor.inkSecondary.resolvedColor(with: normal), UIColor.paper.resolvedColor(with: normal)))
    }

    func testDisplayFontsRegister() {
        ScribeFonts.register()
        XCTAssertNotNil(UIFont(name: ScribeFonts.frauncesSemiBold, size: 20))
        XCTAssertNotNil(UIFont(name: ScribeFonts.frauncesRegular, size: 20))
        let title = ScribeFonts.printTitle(size: 30)
        XCTAssertEqual(CTFontCopyFamilyName(title) as String, "Bricolage Grotesque")
        let axes = CTFontCopyVariation(title) as? [NSNumber: NSNumber] ?? [:]
        XCTAssertEqual(axes[NSNumber(value: 0x7764_7468)]?.doubleValue ?? 0, 75, accuracy: 0.5, "Print titles use the condensed width")
        XCTAssertEqual(axes[NSNumber(value: 0x7767_6874)]?.doubleValue ?? 800, 800, accuracy: 0.5, "ExtraBold is the default instance")
    }
}

final class CoverRendererTests: XCTestCase {
    private func request(_ style: CoverStyle, id: UUID = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!, seed: UInt32 = 42,
                         cloth: ClothColor = .moss, inks: (RisoInk, RisoInk) = (.teal, .pink), dark: Bool = false, highContrast: Bool = false) -> CoverRequest {
        CoverRequest(notebookID: id, spec: CoverSpec(style: style, cloth: cloth, inks: inks, seed: seed), title: "Cell Biology",
                     meta: "24 pages", width: 150, scale: 2, dark: dark, highContrast: highContrast, firstPage: nil,
                     firstPageKey: nil, firstPageIsPDF: style == .firstPage)
    }

    func testCoversAreThreeByFourAndDeterministic() {
        for style in CoverStyle.allCases {
            let a = CoverRenderer.render(request(style)), b = CoverRenderer.render(request(style))
            XCTAssertEqual(a.size, CGSize(width: 150, height: 200))
            XCTAssertEqual(a.pngData(), b.pngData(), "\(style) must render identically from the same request")
        }
    }

    func testReprintChangesThePatternButNotTheInks() {
        let first = CoverRenderer.printPlan(for: request(.print, seed: 1))
        let plans = (2...12).map { CoverRenderer.printPlan(for: request(.print, seed: UInt32($0))) }
        XCTAssertTrue(plans.contains { $0.base != first.base || $0.overlay != first.overlay || $0.jitter != first.jitter })
        for plan in plans + [first] {
            XCTAssertEqual(Set([plan.baseInk, plan.overlayInk]), [.teal, .pink])
            XCTAssertLessThanOrEqual(abs(plan.misregistration.width), 0.3)
            XCTAssertLessThanOrEqual(abs(plan.misregistration.height), 0.3)
        }
        XCTAssertNotEqual(CoverRenderer.render(request(.print, seed: 1)).pngData(), CoverRenderer.render(request(.print, seed: 7)).pngData())
    }

    func testDifferentNotebooksGetDifferentPrints() {
        let plans = (0..<12).map { _ in CoverRenderer.printPlan(for: request(.print, id: UUID())) }
        XCTAssertGreaterThan(Set(plans.map { "\($0.base)-\($0.overlay)" }).count, 2)
    }

    func testKeysSeparateEveryVariant() {
        let base = request(.cloth)
        var keys: Set<String> = [base.key]
        var variants = [request(.print), request(.firstPage), request(.cloth, cloth: .navy), request(.cloth, dark: true), request(.cloth, highContrast: true)]
        var retitled = base
        retitled.title = "Genetics"
        variants.append(retitled)
        for variant in variants { keys.insert(variant.key) }
        XCTAssertEqual(keys.count, variants.count + 1)
    }

    /// Renders a contact sheet of every style for visual review; attached to the test result.
    func testContactSheet() throws {
        let width: CGFloat = 150, gap: CGFloat = 16
        var rows: [[CoverRequest]] = []
        rows.append(ClothColor.allCases.map { request(.cloth, id: UUID(), cloth: $0) })
        rows.append(RisoInk.pairs.enumerated().map { request(.print, id: UUID(), seed: UInt32($0.offset * 31), inks: $0.element) }
                    + [request(.firstPage, cloth: .slate)] + (0..<3).map { request(.print, id: UUID(), seed: UInt32($0), inks: RisoInk.pairs[$0], highContrast: true) })
        rows.append(ClothColor.allCases.prefix(5).map { request(.cloth, id: UUID(), cloth: $0, dark: true) }
                    + RisoInk.pairs.prefix(3).map { request(.print, id: UUID(), inks: $0, dark: true) }
                    + [request(.cloth, cloth: .cobalt, highContrast: true), request(.cloth, cloth: .oat, dark: true, highContrast: true)])
        let columns = rows.map(\.count).max() ?? 1
        let size = CGSize(width: gap + CGFloat(columns) * (width + gap), height: gap + CGFloat(rows.count) * (width * 4 / 3 + gap))
        let sheet = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(hex: 0xF1EDE4).setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: size.width, height: size.height * 2 / 3)))
            UIColor(hex: 0x181613).setFill()
            context.fill(CGRect(x: 0, y: size.height * 2 / 3, width: size.width, height: size.height / 3))
            for (r, row) in rows.enumerated() {
                for (c, item) in row.enumerated() {
                    CoverRenderer.render(item).draw(at: CGPoint(x: gap + CGFloat(c) * (width + gap), y: gap + CGFloat(r) * (width * 4 / 3 + gap)))
                }
            }
        }
        let attachment = XCTAttachment(image: sheet)
        attachment.name = "cover-contact-sheet"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
