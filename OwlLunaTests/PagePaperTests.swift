import XCTest
@testable import OwlLuna

/// The editor's paper: drawn in pieces off the main thread, shown by plain layers, and never more than the viewport needs.
@MainActor
final class PagePaperTests: XCTestCase {
    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    func testPiecesCoverWhatIsKeptAndStopAtThePageEdge() {
        let size = CGSize(width: 800, height: 1035)
        let keep = CGRect(x: 300.3, y: 410.7, width: 240, height: 500)
        for density in [0.8, 1, 2, 2.62, 10.5] as [CGFloat] {
            let tiles = PaperTiles(size: size, density: density, reaching: keep)
            var covered = CGRect.null
            for row in tiles.rows {
                for column in tiles.columns {
                    let pixels = tiles.pixels(column: column, row: row)
                    XCTAssertGreaterThan(pixels.width * pixels.height, 0)
                    XCTAssertLessThanOrEqual(pixels.maxX, (size.width * density).rounded(.up))
                    XCTAssertLessThanOrEqual(pixels.maxY, (size.height * density).rounded(.up))
                    covered = covered.union(pixels)
                }
            }
            let wanted = CGRect(x: keep.minX * density, y: keep.minY * density, width: keep.width * density, height: keep.height * density)
            XCTAssertTrue(covered.insetBy(dx: -0.01, dy: -0.01).contains(wanted), "\(density)")
            let side = CGFloat(PaperTiles.side)
            XCTAssertLessThan(covered.width, wanted.width + 2 * side, "\(density): no more than the pieces that reach it")
            XCTAssertLessThan(covered.height, wanted.height + 2 * side, "\(density)")
        }

        let whole = PaperTiles(size: size, density: 2, reaching: CGRect(origin: .zero, size: size))
        XCTAssertEqual(whole.columns, 0..<4)
        XCTAssertEqual(whole.rows, 0..<5)
        XCTAssertEqual(whole.pixels(column: 3, row: 4), CGRect(x: 1536, y: 2048, width: 64, height: 22))
        XCTAssertEqual(PaperTiles(size: size, density: 2, reaching: .null).count, 0)
        XCTAssertEqual(PaperTiles(size: size, density: 2, reaching: CGRect(x: 900, y: 0, width: 50, height: 50)).count, 0, "off the page")
    }

    /// The worst difference between a piece and the same pixels of the page drawn whole.
    private func difference(_ piece: CGImage, at origin: CGPoint, in whole: CGImage) throws -> Int {
        let a = try XCTUnwrap(piece.dataProvider?.data) as Data, b = try XCTUnwrap(whole.dataProvider?.data) as Data
        var worst = 0
        a.withUnsafeBytes { a in
            b.withUnsafeBytes { b in
                for y in 0..<piece.height {
                    let line = a.baseAddress! + y * piece.bytesPerRow
                    let from = b.baseAddress! + (Int(origin.y) + y) * whole.bytesPerRow + Int(origin.x) * 4
                    if memcmp(line, from, piece.width * 4) == 0 { continue }
                    for i in 0..<piece.width * 4 {
                        worst = max(worst, abs(Int(line.load(fromByteOffset: i, as: UInt8.self)) - Int(from.load(fromByteOffset: i, as: UInt8.self))))
                    }
                }
            }
        }
        return worst
    }

    private func isOneColour(_ image: CGImage) throws -> Bool {
        let data = try XCTUnwrap(image.dataProvider?.data) as Data
        return data.withUnsafeBytes { bytes in
            let first = bytes.load(as: UInt32.self)
            return !(0..<image.height).contains { y in
                (0..<image.width).contains { bytes.load(fromByteOffset: y * image.bytesPerRow + $0 * 4, as: UInt32.self) != first }
            }
        }
    }

    func testPiecesMatchThePageDrawnWhole() throws {
        let assets = FileManager.default.temporaryDirectory
        let unit: CGFloat = 1.3, density: CGFloat = 2
        for template in PaperTemplate.allCases {
            let page = NotebookPage.template(template, color: template == .grid ? .chalkboard : .white, size: .letter)
            let size = CGSize(width: page.size.width * unit, height: page.size.height * unit)
            let tiles = PaperTiles(size: size, density: density, reaching: CGRect(origin: .zero, size: size))
            let all = tiles.pixels(column: 0, row: 0).union(tiles.pixels(column: tiles.columns.upperBound - 1, row: tiles.rows.upperBound - 1))
            let whole = try XCTUnwrap(PagePaperView.image(of: page, assets: assets, unit: unit, density: density, pixels: all))
            XCTAssertEqual(try isOneColour(whole), template == .blank, "\(template): the rules are drawn")
            var worst = 0
            for row in tiles.rows {
                for column in tiles.columns {
                    let pixels = tiles.pixels(column: column, row: row)
                    let piece = try XCTUnwrap(PagePaperView.image(of: page, assets: assets, unit: unit, density: density, pixels: pixels))
                    XCTAssertEqual(CGSize(width: piece.width, height: piece.height), pixels.size)
                    worst = max(worst, try difference(piece, at: pixels.origin, in: whole))
                }
            }
            XCTAssertLessThanOrEqual(worst, 2, "\(template): pieces meet without a seam")
        }
    }

    private func layers(under layer: CALayer) -> [CALayer] {
        [layer] + (layer.sublayers ?? []).flatMap { layers(under: $0) }
    }

    /// A tiled layer commits a transaction from its drawing thread, which lays out whatever window is waiting: none may come back.
    func testEditorPaperUsesNoTiledLayerAndStaysBoundedAtFiveTimes() async throws {
        let root = temporaryRoot(self)
        let paper = PageDefaults(template: .narrowRuled, paperColor: .white, pageSize: .letter)
        let manifest = NotebookManifest(title: "Paper", defaults: paper, pages: (0..<6).map { _ in paper.newPage() })
        try await NotebookPackage(root: root, id: manifest.id).create(manifest)
        let document = try await NotebookDocument.open(manifest.id, root: root)
        let session = EditorSession(document: document)
        let controller = PageStackController(session: session)
        session.canvas = controller
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 834, height: 1194)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        addTeardownBlock { @MainActor in window.isHidden = true }
        controller.view.layoutIfNeeded()

        func drawn() async -> Bool {
            for _ in 0..<100 where !controller.isPaperDrawn { await pause(0.05) }
            return controller.isPaperDrawn
        }
        let viewport = Int(834 * 1194 * window.screen.scale * window.screen.scale)
        let atRest = await drawn()
        XCTAssertTrue(atRest, "the paper in view is drawn")
        XCTAssertGreaterThan(controller.paperPixelCount, viewport / 2)
        XCTAssertLessThan(controller.paperPixelCount, viewport * 5)
        XCTAssertFalse(layers(under: controller.view.layer).contains { $0 is CATiledLayer })

        controller.setZoom(5)
        let zoomed = await drawn()
        XCTAssertTrue(zoomed, "and again at 5×, with the pieces for the old zoom gone")
        XCTAssertLessThan(controller.paperPixelCount, viewport * 5, "a 5× page holds only the paper near the viewport")
        for _ in 0..<12 {
            controller.scrollBy(viewportFraction: 0.5)
            await pause(0.03)
            XCTAssertLessThan(controller.paperPixelCount, viewport * 5)
        }

        controller.setZoom(1)
        let back = await drawn()
        XCTAssertTrue(back)
        XCTAssertFalse(layers(under: controller.view.layer).contains { $0 is CATiledLayer })
    }
}
