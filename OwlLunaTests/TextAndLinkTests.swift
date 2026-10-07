import XCTest
import PDFKit
import PencilKit
@testable import OwlLuna

/// Typed text boxes and links between pages: the manifest, layout, search, navigation and export.
@MainActor
final class TextAndLinkTests: XCTestCase {
    private let paper = PageDefaults(template: .blank, paperColor: .white, pageSize: .letter)

    private func makeDocument(pages: Int = 3) async throws -> NotebookDocument {
        let root = temporaryRoot(self)
        let manifest = NotebookManifest(title: "Chemistry", defaults: paper, pages: (0..<pages).map { _ in paper.newPage() })
        try await NotebookPackage(root: root, id: manifest.id).create(manifest)
        return try await NotebookDocument.open(manifest.id, root: root)
    }

    private func textItem(_ string: String, width: CGFloat = 200, at centre: CGPoint = CGPoint(x: 300, y: 300)) -> PageItem {
        let box = TextBox(string: string)
        return PageItem(content: .text(box), center: centre, size: CGSize(width: width, height: box.height(width: width)))
    }

    func testTextAndLinksSurviveTheManifest() throws {
        var page = paper.newPage()
        let target = UUID()
        var box = TextBox(string: "Avogadro's number\n6.022 × 10²³", fontSize: 24, isBold: true, tint: .cobalt, alignment: .center)
        box.fontSize = 24
        let text = PageItem(content: .text(box), center: CGPoint(x: 200, y: 100), size: CGSize(width: 240, height: 60), rotation: 0.1)
        let link = PageItem(content: .link(PageLink(target: target, label: "Answers")), center: CGPoint(x: 400, y: 700), size: CGSize(width: 120, height: 30))
        page.items = [text, link]

        let decoded = try XCTUnwrap(ManifestCodec.decodePage(ManifestCodec.encodePage(page)))
        XCTAssertEqual(decoded.items.map(\.content), [.text(box), .link(PageLink(target: target, label: "Answers"))])
        XCTAssertEqual(decoded.typedText, "Avogadro's number\n6.022 × 10²³")

        let nameless: JSONValue = .object(["id": .string(UUID().uuidString), "kind": .string("link"), "x": .number(1), "y": .number(2), "w": .number(3), "h": .number(4)])
        let huge: JSONValue = .object(["id": .string(UUID().uuidString), "kind": .string("text"), "text": .string("big"), "fs": .number(9000),
                                       "color": .string("ultraviolet"), "x": .number(1), "y": .number(2), "w": .number(3), "h": .number(4)])
        XCTAssertEqual(PageItem(json: nameless)?.content, .unknown, "a link with no page to open is kept and not drawn")
        let clamped = try XCTUnwrap(PageItem(json: huge)?.text)
        XCTAssertEqual(clamped.fontSize, TextBox.fontSizes.upperBound)
        XCTAssertEqual(clamped.tint, .ink, "a colour from a newer version falls back to ink")
    }

    func testABoxGrowsDownwardsWithItsText() {
        let short = textItem("One line")
        let long = textItem("One line that carries on well past the edge of a narrow box and has to wrap", width: 120)
        XCTAssertGreaterThan(long.size.height, short.size.height * 2.5)
        XCTAssertEqual(TextBox(string: "").height(width: 200), short.size.height, "an empty box is one line tall")
        XCTAssertGreaterThan(TextBox(string: "a\n").height(width: 200), short.size.height, "a trailing return opens a new line")

        var edited = short
        edited.content = .text(TextBox(string: "One line\nand another\nand a third"))
        let fitted = edited.fittedToText()
        XCTAssertEqual(fitted.center.y - fitted.size.height / 2, short.center.y - short.size.height / 2, accuracy: 0.001, "the top edge stays where it was")
        XCTAssertEqual(fitted.center.x, short.center.x)

        var turned = short
        turned.rotation = .pi / 2
        let wider = turned.resized(to: CGSize(width: 300, height: short.size.height))
        XCTAssertEqual(wider.center.x, turned.center.x, accuracy: 0.001, "turned a quarter, a wider box grows down the page")
        XCTAssertEqual(wider.center.y, turned.center.y + 50, accuracy: 0.001)
    }

    func testScalingATextBoxScalesItsType() {
        let item = textItem("Scale me")
        let doubled = item.scaled(by: 2, limit: 2000)
        XCTAssertEqual(doubled.text?.fontSize, 34)
        XCTAssertEqual(doubled.size.width, 400)
        XCTAssertEqual(doubled.size.height, doubled.text?.height(width: 400))
        XCTAssertEqual(item.scaled(by: 1000, limit: 100_000).text?.fontSize, TextBox.fontSizes.upperBound)
    }

    func testTypedTextIsDrawnAndFound() async throws {
        let document = try await makeDocument()
        let page = document.pages[0].id
        var item = textItem("Stoichiometry", width: 300)
        item.content = .text(TextBox(string: "Stoichiometry", fontSize: 40, isBold: true))
        item = item.fittedToText()
        document.updateItems(onPage: page, actionName: "Add Text Box") { $0.append(item) }
        let saved = await document.flush()
        XCTAssertTrue(saved)

        let image = PageRenderer.image(of: document.pages[0], ink: PKDrawing(), assets: document.package.assetsDirectory, width: 612)
        XCTAssertGreaterThan(darkPixels(in: image, rect: item.boundingBox), 400, "the text is drawn into thumbnails and exports")
        XCTAssertEqual(darkPixels(in: image, rect: CGRect(x: 100, y: 500, width: 300, height: 60)), 0)

        let blank = document.pages[1]
        XCTAssertEqual(HandwritingIndexer.header(for: blank), "#ink:none\n", "a page without typed text keeps the stamp it always had")
        XCTAssertNotEqual(HandwritingIndexer.header(for: document.pages[0]), "#ink:none\n")
        let text = await HandwritingIndexer.shared.index(HandwritingIndexer.Job(package: document.package, pages: document.pages))
        XCTAssertTrue(text.contains("Stoichiometry"), "typed text is searchable without being recognised")
        let stored = await document.package.readText(page)
        XCTAssertNotNil(PageSearch.snippet(in: try XCTUnwrap(stored), for: "stoich"))

        document.updateItems(onPage: page, actionName: "Edit Text") { items in
            items[0].content = .text(TextBox(string: "Titration"))
        }
        _ = await document.flush()
        let again = await HandwritingIndexer.shared.index(HandwritingIndexer.Job(package: document.package, pages: document.pages))
        XCTAssertTrue(again.contains("Titration"))
        XCTAssertFalse(again.contains("Stoichiometry"), "editing the text replaces what search finds")
    }

    func testALinkIsNamedAfterItsPage() async throws {
        let document = try await makeDocument()
        let third = document.pages[2].id
        let link = PageLink(target: third)
        XCTAssertEqual(LinkTitles(pages: document.pages).title(for: link), "Page 3")
        document.movePage(from: 2, to: 0)
        XCTAssertEqual(LinkTitles(pages: document.pages).title(for: link), "Page 1", "the name follows the page when it moves")
        document.setBookmark("Answers", forPage: third)
        XCTAssertEqual(LinkTitles(pages: document.pages).title(for: link), "Answers")
        XCTAssertEqual(LinkTitles(pages: document.pages).title(for: PageLink(target: third, label: "Key")), "Key")
        document.removePages([third])
        let titles = LinkTitles(pages: document.pages)
        XCTAssertFalse(titles.resolves(link))
        XCTAssertEqual(titles.title(for: link), "Missing page")
        XCTAssertGreaterThan(PageLinkArt.size(for: "A much longer bookmark name").width, PageLinkArt.size(for: "Page 3").width)
    }

    func testFollowingALinkRemembersTheWayBack() async throws {
        let document = try await makeDocument()
        let session = EditorSession(document: document)
        XCTAssertEqual(session.currentPage, 0)
        session.addLink(to: document.pages[2].id)
        let item = try XCTUnwrap(document.pages[0].items.first)
        let link = try XCTUnwrap(item.link)
        XCTAssertEqual(item.size, PageLinkArt.size(for: "Page 3"))
        XCTAssertEqual(document.undoManager.undoActionName, "Add Link")

        session.follow(link, from: document.pages[0].id)
        XCTAssertEqual(session.currentPage, 2)
        XCTAssertEqual(session.linkReturn, document.pages[0].id)
        session.goBack()
        XCTAssertEqual(session.currentPage, 0)
        XCTAssertNil(session.linkReturn)

        session.follow(link, from: document.pages[0].id)
        session.go(to: 1)
        XCTAssertNil(session.linkReturn, "leaving the linked page puts the way back away")

        document.removePages([try XCTUnwrap(link.target)])
        session.go(to: 0)
        session.follow(link, from: document.pages[0].id)
        XCTAssertEqual(session.currentPage, 0, "a link to a deleted page goes nowhere")
    }

    func testAnExportKeepsLinksWorking() async throws {
        let document = try await makeDocument()
        let link = PageItem(content: .link(PageLink(target: document.pages[2].id)), center: CGPoint(x: 200, y: 150), size: CGSize(width: 100, height: 30))
        let dead = PageItem(content: .link(PageLink(target: UUID())), center: CGPoint(x: 200, y: 500), size: CGSize(width: 100, height: 30))
        document.updateItems(onPage: document.pages[0].id, actionName: "Add Link") { $0 += [link, dead] }
        XCTAssertEqual(NotebookExporter.linkedPages(in: document.pages), [document.pages[2].id])

        let url = try await NotebookExporter.export(.init(title: "Chemistry", pages: document.pages, inMemoryInk: [:], package: document.package)) { _ in }
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        let annotations = try XCTUnwrap(pdf.page(at: 0)?.annotations.filter { $0.type == "Link" })
        XCTAssertEqual(annotations.count, 1, "only the link whose page exists is live")
        let annotation = try XCTUnwrap(annotations.first)
        let destination = (annotation.action as? PDFActionGoTo)?.destination ?? annotation.destination
        XCTAssertEqual(destination?.page.map(pdf.index(for:)), 2)
        XCTAssertEqual(annotation.bounds.midX, 200, accuracy: 2)
        XCTAssertEqual(annotation.bounds.midY, 792 - 150, accuracy: 2, "the tappable area sits on the tab")
        XCTAssertTrue(pdf.page(at: 1)?.annotations.isEmpty ?? false)
    }

    func testLinksToTheWebAndToOtherNotebooksSurviveTheManifest() throws {
        var page = paper.newPage()
        let notebook = UUID(), there = UUID()
        let url = try XCTUnwrap(WebAddress.url(from: "www.example.com/guide"))
        XCTAssertEqual(url.absoluteString, "https://www.example.com/guide", "an address typed without a scheme is taken as https")
        XCTAssertEqual(WebAddress.display(url), "example.com/guide")
        XCTAssertNil(WebAddress.url(from: "not an address"))
        XCTAssertNil(WebAddress.url(from: "javascript:alert(1)"))
        XCTAssertNil(WebAddress.url(from: "file:///etc/passwd"), "only web addresses are opened")
        let links = [PageLink(.web(url), label: "Guide"), PageLink(.notebook(notebook, page: there, name: "Physics")),
                     PageLink(.notebook(notebook, page: nil, name: "Physics")), PageLink(target: there)]
        page.items = links.enumerated().map { index, link in
            PageItem(content: .link(link), center: CGPoint(x: 100, y: 100 + CGFloat(index) * 50), size: CGSize(width: 120, height: 30))
        }
        let decoded = try XCTUnwrap(ManifestCodec.decodePage(ManifestCodec.encodePage(page)))
        XCTAssertEqual(decoded.items.compactMap(\.link), links)

        var changed = decoded.items[0]
        changed.content = .link(PageLink(target: there))
        XCTAssertNil(changed.json.objectValue?["url"], "a link that changes what it opens drops the old address")
        let object = try XCTUnwrap(decoded.items[1].json.objectValue)
        XCTAssertNil(object["target"], "an older version sees a link it can't read and keeps it, rather than a page that's missing")
    }

    func testALinkToANotebookFollowsItsTitle() {
        let notebook = UUID()
        let link = PageLink(.notebook(notebook, page: nil, name: "Physics"))
        XCTAssertEqual(LinkTitles().title(for: link), "Physics", "without the library it keeps the name it was made with")
        XCTAssertTrue(LinkTitles().resolves(link))
        let renamed = LinkTitles(notebooks: [notebook: "Physics II"])
        XCTAssertEqual(renamed.title(for: link), "Physics II")
        XCTAssertTrue(renamed.resolves(link))
        let gone = LinkTitles(notebooks: [:])
        XCTAssertFalse(gone.resolves(link), "a notebook that was deleted greys its links out")
        XCTAssertEqual(gone.title(for: link), "Physics")
        XCTAssertEqual(LinkTitles().title(for: PageLink(.web(URL(string: "https://www.swift.org")!))), "swift.org")
        XCTAssertEqual(LinkTitles().title(for: PageLink(.web(URL(string: "https://www.swift.org")!), label: "Swift")), "Swift")
        XCTAssertNotEqual(LinkTitles(notebooks: [:]), LinkTitles(notebooks: [notebook: "A"]), "a rename is a change the page stack redraws for")
    }

    func testFollowingALinkOutOfTheNotebook() async throws {
        let document = try await makeDocument()
        let session = EditorSession(document: document)
        var opened: [URL] = [], notebooks: [(UUID, UUID?, UUID)] = []
        session.openURL = { opened.append($0) }
        session.openNotebook = { notebooks.append(($0, $1, $2)) }
        let url = URL(string: "https://example.com")!, other = UUID(), there = UUID(), here = document.pages[0].id

        session.addLink(PageLink(.web(url)))
        XCTAssertEqual(document.pages[0].items.first?.size, PageLinkArt.size(for: "example.com"))
        session.follow(PageLink(.web(url)), from: here)
        XCTAssertEqual(opened, [url])
        XCTAssertEqual(session.currentPage, 0)
        XCTAssertNil(session.linkReturn)

        session.follow(PageLink(.notebook(other, page: there, name: "Physics")), from: here)
        XCTAssertEqual(notebooks.count, 1)
        XCTAssertEqual(notebooks.first?.0, other)
        XCTAssertEqual(notebooks.first?.1, there)
        XCTAssertEqual(notebooks.first?.2, here, "the notebook it opens can offer the way back to this page")
    }

    func testAnExportKeepsLinksOutOfTheNotebook() async throws {
        let document = try await makeDocument()
        let url = URL(string: "https://example.com/guide")!, other = UUID(), there = UUID()
        let web = PageItem(content: .link(PageLink(.web(url))), center: CGPoint(x: 200, y: 150), size: CGSize(width: 100, height: 30))
        let notebook = PageItem(content: .link(PageLink(.notebook(other, page: there, name: "Physics"))), center: CGPoint(x: 200, y: 500), size: CGSize(width: 100, height: 30))
        document.updateItems(onPage: document.pages[0].id, actionName: "Add Link") { $0 += [web, notebook] }

        let file = try await NotebookExporter.export(.init(title: "Chemistry", pages: document.pages, inMemoryInk: [:], package: document.package)) { _ in }
        let pdf = try XCTUnwrap(PDFDocument(url: file))
        let annotations = try XCTUnwrap(pdf.page(at: 0)?.annotations.filter { $0.type == "Link" }).sorted { $0.bounds.midY > $1.bounds.midY }
        XCTAssertEqual(annotations.count, 2)
        XCTAssertEqual(annotations.first?.url, url)
        XCTAssertEqual(try XCTUnwrap(annotations.first).bounds.midY, 792 - 150, accuracy: 2, "the tappable area sits on the tab")
        XCTAssertEqual(annotations.last?.url.flatMap(AppAction.init(url:)), .open(other, page: there), "a link to another notebook opens OwlLuna at its page")
    }

    private func darkPixels(in image: UIImage, rect: CGRect) -> Int {
        guard let cg = image.cgImage else { return 0 }
        let width = cg.width, height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        for y in max(0, Int(rect.minY))..<min(height, Int(rect.maxY)) {
            for x in max(0, Int(rect.minX))..<min(width, Int(rect.maxX)) where bytes[(y * width + x) * 4] < 110 { count += 1 }
        }
        return count
    }
}
