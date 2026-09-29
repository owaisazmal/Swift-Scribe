import XCTest
import PencilKit
import PDFKit
@testable import NotesApp

final class PageStackLayoutTests: XCTestCase {
    func testPagesStackVerticallyAndCentre() {
        let pages = [NotebookPage.template(.blank, color: .white, size: .letter), .template(.blank, color: .white, size: .a5),
                     NotebookPage(background: .image(file: "x"), paperColor: .white, size: CGSize(width: 960, height: 540))]
        let layout = PageStackLayout(pages: pages)
        let margin = PageStackLayout.margin
        XCTAssertEqual(layout.size.width, 960 + margin * 2)
        XCTAssertEqual(layout.frames[0].size, PageSize.letter.points)
        XCTAssertEqual(layout.frames[1].minY, layout.frames[0].maxY + margin)
        XCTAssertEqual(layout.frames[0].midX, layout.size.width / 2, accuracy: 1)
        XCTAssertEqual(layout.frames[2].minX, margin)
        XCTAssertEqual(layout.size.height, layout.frames[2].maxY + margin)
    }

    func testPageAtYAndVisibleRange() {
        let layout = PageStackLayout(pages: (0..<5).map { _ in .template(.blank, color: .white, size: .letter) })
        XCTAssertEqual(layout.pageIndex(atY: 0), 0)
        XCTAssertEqual(layout.pageIndex(atY: layout.frames[3].midY), 3)
        XCTAssertEqual(layout.pageIndex(atY: layout.frames[1].maxY + PageStackLayout.margin / 4), 1)
        XCTAssertEqual(layout.pageIndex(atY: 1_000_000), 4)
        XCTAssertEqual(layout.range(from: layout.frames[1].midY, to: layout.frames[2].midY), 1...2)
    }
}

/// Replaces the stroke-masking test: masking at stroke end is gone, and ink past the edge is kept but never shown.
@MainActor
final class InkStaysOnItsPageTests: XCTestCase {
    func testInkPastTheEdgeIsKeptButOnlyThePagePartIsDrawn() throws {
        let page = NotebookPage.template(.blank, color: .white, size: .letter)
        let size = page.size
        let crossing = stroke(from: CGPoint(x: size.width - 120, y: 300), to: CGPoint(x: size.width + 200, y: 300), width: 8)
        let drawing = PKDrawing(strokes: [crossing])
        let image = PageRenderer.image(of: page, ink: drawing, assets: temporaryRoot(self).url, width: size.width, scale: 1)
        XCTAssertEqual(image.size, size, "renders exactly the page rectangle")
        XCTAssertLessThan(try luminance(of: image, at: CGPoint(x: size.width - 40, y: 300)), 0.5, "the part on the page is drawn")
        XCTAssertGreaterThan(try luminance(of: image, at: CGPoint(x: 100, y: 300)), 0.9)
        XCTAssertEqual(drawing.strokes.first?.mask, nil, "the stroke itself is left whole")
        XCTAssertTrue(PageSlotView(page: page).clipsToBounds, "on screen, the page slot clips its canvas")
    }

    private func luminance(of image: UIImage, at point: CGPoint) throws -> CGFloat {
        let cgImage = try XCTUnwrap(image.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let scale = CGFloat(cgImage.width) / image.size.width
        context.draw(cgImage, in: CGRect(x: -point.x * scale, y: -(CGFloat(cgImage.height) - point.y * scale - 1),
                                         width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        return (0.2126 * CGFloat(pixel[0]) + 0.7152 * CGFloat(pixel[1]) + 0.0722 * CGFloat(pixel[2])) / 255
    }
}

@MainActor
final class DocumentRegistryTests: XCTestCase {
    func testOneDocumentPerNotebookAndOnlyItsOwnerCanRelease() async throws {
        let root = temporaryRoot(self)
        let manifest = NotebookManifest(title: "Shared", defaults: PageDefaults(template: .blank, paperColor: .white, pageSize: .letter),
                                        pages: [.template(.blank, color: .white, size: .letter)])
        try await NotebookPackage(root: root, id: manifest.id).create(manifest)
        let first = try await NotebookDocument.open(manifest.id, root: root)
        let other = try await NotebookDocument.open(manifest.id, root: root)
        let registry = DocumentRegistry.shared
        registry.register(first, scene: "scene-a")
        XCTAssertTrue(registry.document(for: manifest.id) === first)
        XCTAssertEqual(registry.sceneIdentifier(for: manifest.id), "scene-a")
        XCTAssertFalse(registry.activateExistingEditor(for: manifest.id, from: "scene-a"), "the owning window just keeps its editor")
        registry.unregister(manifest.id, document: other)
        XCTAssertTrue(registry.document(for: manifest.id) === first, "a different instance can't release the owner's registration")
        registry.unregister(manifest.id, document: first)
        XCTAssertNil(registry.document(for: manifest.id))
    }
}

final class PDFRoundTripV2Tests: XCTestCase {
    private func makePDF(pageSizes: [CGSize]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSizes[0])).writePDF(to: url) { context in
            for size in pageSizes {
                context.beginPage(withBounds: CGRect(origin: .zero, size: size), pageInfo: [:])
                ("Mitochondria" as NSString).draw(at: CGPoint(x: 40, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
            }
        }
        return url
    }

    func testImportCreatesOnePagePerPDFPage() async throws {
        let root = temporaryRoot(self)
        let package = NotebookPackage(root: root, id: UUID())
        let file = try await package.importAsset(from: makePDF(pageSizes: [CGSize(width: 612, height: 792), CGSize(width: 792, height: 612)]), ext: "pdf")
        let pages = try PDFImport.pages(at: package.assetURL(file), file: file)
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[1].size, CGSize(width: 792, height: 612))
        XCTAssertEqual(pages[1].background, .pdf(file: file, index: 1))
    }

    func testExportKeepsPageCountSizesTextAndInk() async throws {
        let root = temporaryRoot(self)
        let id = UUID()
        let package = NotebookPackage(root: root, id: id)
        let file = try await package.importAsset(from: makePDF(pageSizes: [CGSize(width: 612, height: 792)]), ext: "pdf")
        var pages = try PDFImport.pages(at: package.assetURL(file), file: file)
        pages.append(.template(.dotted, color: .ivory, size: .a4))
        let manifest = NotebookManifest(id: id, title: "Bio: Cells", defaults: PageDefaults(template: .dotted, paperColor: .ivory, pageSize: .a4), pages: pages)
        try await package.create(manifest)
        _ = try await package.write(SaveSnapshot(manifest: manifest, ink: [pages[1].id: PKDrawing(strokes: [stroke(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 300, y: 60))])]))
        let url = try await NotebookExporter.export(.init(title: "Bio: Cells", pages: pages, inMemoryInk: [:], package: package)) { _ in }
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(url.lastPathComponent, "Bio- Cells.pdf")
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertEqual(document.page(at: 1)?.bounds(for: .mediaBox).size.width ?? 0, 595.28, accuracy: 0.1)
        XCTAssertTrue(document.page(at: 0)?.string?.contains("Mitochondria") ?? false, "the original PDF text stays selectable")
    }

    func testExportCanBeCancelled() async throws {
        let root = temporaryRoot(self)
        let id = UUID()
        let package = NotebookPackage(root: root, id: id)
        let pages = (0..<40).map { _ in NotebookPage.template(.grid, color: .white, size: .letter) }
        try await package.create(NotebookManifest(id: id, title: "Long", defaults: PageDefaults(template: .grid, paperColor: .white, pageSize: .letter), pages: pages))
        let task = Task { try await NotebookExporter.export(.init(title: "Long", pages: pages, inMemoryInk: [:], package: package)) { _ in } }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("a cancelled export must not produce a file")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}
