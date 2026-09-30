import XCTest
import SwiftUI
import SwiftData
@testable import NotesApp

@MainActor
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
            ("textSecondary/paper", .textSecondary, .paper), ("textSecondary/desk", .textSecondary, .desk), ("textSecondary/surface", .textSecondary, .surface),
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

    /// A focused sidebar row is filled with the sidebar tint under white text; its icons sit on the surface.
    func testSidebarTintCarriesWhiteTextAndItsIconsShow() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for level in [UIAccessibilityContrast.normal, .high] {
                let traits = UITraitCollection { $0.userInterfaceStyle = style; $0.accessibilityContrast = level }
                let tint = UIColor.sidebarTint.resolvedColor(with: traits)
                XCTAssertGreaterThanOrEqual(contrast(.white, tint), 4.5)
                XCTAssertGreaterThanOrEqual(contrast(tint, UIColor.surface.resolvedColor(with: traits)), 3)
            }
        }
    }

    /// The editor's page ribbon draws its text straight on the notebook's cloth.
    func testRibbonTextReachesAAOnEveryCloth() {
        for cloth in ClothColor.allCases {
            let ratio = contrast(UIColor(cloth.onCloth), cloth.uiColor)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(cloth.rawValue): \(String(format: "%.2f", ratio))")
        }
    }

    /// Small labels and metadata use the text token, which keeps 7:1 so anti-aliased small text still clears Apple's audit.
    func testSmallTextTokenReachesSevenToOne() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for level in [UIAccessibilityContrast.normal, .high] {
                let traits = UITraitCollection { $0.userInterfaceStyle = style; $0.accessibilityContrast = level }
                for background in [UIColor.paper, .desk, .surface] {
                    let ratio = contrast(UIColor.textSecondary.resolvedColor(with: traits), background.resolvedColor(with: traits))
                    XCTAssertGreaterThanOrEqual(ratio, 7, "\(style == .dark ? "dark" : "light")\(level == .high ? "+IC" : ""): \(String(format: "%.2f", ratio))")
                }
                XCTAssertGreaterThan(contrast(UIColor.textSecondary.resolvedColor(with: traits), UIColor.desk.resolvedColor(with: traits)),
                                     contrast(UIColor.inkSecondary.resolvedColor(with: traits), UIColor.desk.resolvedColor(with: traits)))
            }
        }
        let normal = UITraitCollection { $0.userInterfaceStyle = .light }
        let high = UITraitCollection { $0.userInterfaceStyle = .light; $0.accessibilityContrast = .high }
        XCTAssertGreaterThan(contrast(UIColor.textSecondary.resolvedColor(with: high), UIColor.desk.resolvedColor(with: high)),
                             contrast(UIColor.textSecondary.resolvedColor(with: normal), UIColor.desk.resolvedColor(with: normal)))
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
        XCTAssertNotNil(UIFont(name: ScribeFonts.frauncesBold, size: 20), "Bold Text uses the Bold instance")
        let title = ScribeFonts.printTitle(size: 30)
        XCTAssertEqual(CTFontCopyFamilyName(title) as String, "Bricolage Grotesque")
        let axes = CTFontCopyVariation(title) as? [NSNumber: NSNumber] ?? [:]
        XCTAssertEqual(axes[NSNumber(value: 0x7764_7468)]?.doubleValue ?? 0, 75, accuracy: 0.5, "Print titles use the condensed width")
        XCTAssertEqual(axes[NSNumber(value: 0x7767_6874)]?.doubleValue ?? 800, 800, accuracy: 0.5, "ExtraBold is the default instance")
    }
}

final class CoverRendererTests: XCTestCase {
    private func request(_ style: CoverStyle, id: UUID = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!, seed: UInt32 = 42,
                         cloth: ClothColor = .moss, inks: (RisoInk, RisoInk) = (.teal, .pink), dark: Bool = false, highContrast: Bool = false,
                         width: CGFloat = 150) -> CoverRequest {
        CoverRequest(notebookID: id, spec: CoverSpec(style: style, cloth: cloth, inks: inks, seed: seed), title: "Cell Biology",
                     meta: "Sep 2026", width: width, scale: 2, dark: dark, highContrast: highContrast, firstPage: nil,
                     firstPageKey: nil, firstPageIsPDF: style == .firstPage)
    }

    /// The sRGB colour of one point of a rendered cover.
    private func pixel(_ image: UIImage, at point: CGPoint) throws -> (r: Int, g: Int, b: Int) {
        let cgImage = try XCTUnwrap(image.cgImage)
        var data = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let x = Int(point.x * image.scale), y = Int(point.y * image.scale)
        context.draw(cgImage, in: CGRect(x: -x, y: y - cgImage.height + 1, width: cgImage.width, height: cgImage.height))
        return (Int(data[0]), Int(data[1]), Int(data[2]))
    }

    private func isClose(_ pixel: (r: Int, g: Int, b: Int), to hex: UInt32, tolerance: Int = 6) -> Bool {
        abs(pixel.r - Int((hex >> 16) & 0xFF)) <= tolerance && abs(pixel.g - Int((hex >> 8) & 0xFF)) <= tolerance && abs(pixel.b - Int(hex & 0xFF)) <= tolerance
    }

    func testCoversAreThreeByFourAndDeterministic() {
        for style in CoverStyle.allCases {
            let a = CoverRenderer.render(request(style)), b = CoverRenderer.render(request(style))
            XCTAssertEqual(a.size, CGSize(width: 150, height: 200))
            XCTAssertEqual(a.pngData(), b.pngData(), "\(style) must render identically from the same request")
        }
    }

    @MainActor
    func testCoverKeyIgnoresPageCount() throws {
        let schema = Schema(versionedSchema: LibraryIndexSchemaV1.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let root = temporaryRoot(self)
        let id = UUID()
        let records = [3, 40].map { pages in
            let record = NotebookRecord(id: id)
            record.title = "Cell Biology"
            record.createdAt = Date(timeIntervalSince1970: 1_790_000_000)
            record.pageCount = pages
            container.mainContext.insert(record)
            return record
        }
        let keys = records.map { $0.coverRequest(width: CoverWidth.shelf, scale: 2, colorScheme: .light, contrast: .standard, root: root).key }
        XCTAssertEqual(keys[0], keys[1], "adding a page must not re-render the cover")
        XCTAssertFalse(records[0].coverRequest(width: CoverWidth.shelf, scale: 2, colorScheme: .light, contrast: .standard, root: root).meta.contains("3"))
    }

    func testPageBlockOnlyAtShelfWidths() throws {
        let shelf = CoverRenderer.render(request(.cloth, width: 176))
        XCTAssertTrue(isClose(try pixel(shelf, at: CGPoint(x: shelf.size.width - 2, y: shelf.size.height / 2)), to: 0xF7F1E3), "cream fore-edge")
        let row = CoverRenderer.render(request(.cloth, width: 64))
        XCTAssertFalse(isClose(try pixel(row, at: CGPoint(x: row.size.width - 2, y: row.size.height / 2)), to: 0xF7F1E3, tolerance: 40))
        XCTAssertEqual(CoverRenderer.pageBlockInsets(for: row.size).right, 0)
    }

    func testPrintCoversHaveStaples() throws {
        let cover = request(.print)
        let image = CoverRenderer.render(cover)
        let inset = CoverRenderer.pageBlockInsets(for: cover.size)
        let board = CGSize(width: cover.size.width - inset.right, height: cover.size.height - inset.bottom)
        for y in [0.28, 0.72] {
            let staple = try pixel(image, at: CGPoint(x: board.width * 0.04, y: board.height * y))
            XCTAssertFalse(isClose(staple, to: RisoInk.paperStock), "a staple at \(y)")
            XCTAssertTrue(isClose(staple, to: 0xB9B6AE), "staple metal at \(y): \(staple)")
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
    /// The last four rows are shelf-size covers on their shadow plates, light and dark, each with Increase Contrast.
    func testContactSheet() throws {
        let gap: CGFloat = 24
        let paper = UIColor(hex: 0xF1EDE4), night = UIColor(hex: 0x181613)
        var rows: [(ground: UIColor, shadow: Bool, covers: [CoverRequest])] = []
        rows.append((paper, false, ClothColor.allCases.map { request(.cloth, id: UUID(), cloth: $0) }))
        rows.append((paper, false, RisoInk.pairs.enumerated().map { request(.print, id: UUID(), seed: UInt32($0.offset * 31), inks: $0.element) }
                     + [request(.firstPage, cloth: .slate)] + (0..<3).map { request(.print, id: UUID(), seed: UInt32($0), inks: RisoInk.pairs[$0], highContrast: true) }))
        rows.append((night, false, ClothColor.allCases.prefix(5).map { request(.cloth, id: UUID(), cloth: $0, dark: true) }
                     + RisoInk.pairs.prefix(3).map { request(.print, id: UUID(), inks: $0, dark: true) }
                     + [request(.cloth, cloth: .cobalt, highContrast: true), request(.cloth, cloth: .oat, dark: true, highContrast: true)]))
        for (ground, dark) in [(paper, false), (night, true)] {
            for highContrast in [false, true] {
                rows.append((ground, true, [request(.cloth, cloth: .cobalt, dark: dark, highContrast: highContrast, width: 176),
                                            request(.cloth, cloth: .oat, dark: dark, highContrast: highContrast, width: 176),
                                            request(.print, inks: (.blue, .pink), dark: dark, highContrast: highContrast, width: 176),
                                            request(.firstPage, cloth: .oxblood, dark: dark, highContrast: highContrast, width: 176)]))
            }
        }
        let cell = CGSize(width: 176, height: 235)
        let columns = rows.map(\.covers.count).max() ?? 1
        let size = CGSize(width: gap + CGFloat(columns) * (cell.width + gap), height: gap + CGFloat(rows.count) * (cell.height + gap))
        let sheet = UIGraphicsImageRenderer(size: size).image { context in
            for (r, row) in rows.enumerated() {
                row.ground.setFill()
                context.fill(CGRect(x: 0, y: CGFloat(r) * (cell.height + gap), width: size.width, height: cell.height + gap * (r == rows.count - 1 ? 2 : 1)))
            }
            for (r, row) in rows.enumerated() {
                for (c, item) in row.covers.enumerated() {
                    let frame = CGRect(origin: CGPoint(x: gap + CGFloat(c) * (cell.width + gap), y: gap + CGFloat(r) * (cell.height + gap)), size: item.size)
                    if row.shadow {
                        CoverShadowPlate.image(dark: item.dark, highContrast: item.highContrast)
                            .resizableImage(withCapInsets: UIEdgeInsets(top: 28, left: 28, bottom: 28, right: 28), resizingMode: .stretch)
                            .draw(in: frame.insetBy(dx: -16, dy: -16))
                    }
                    CoverRenderer.render(item).draw(in: frame)
                }
            }
        }
        let attachment = XCTAttachment(image: sheet)
        attachment.name = "cover-contact-sheet"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
