import XCTest
import PencilKit
import SwiftData
@testable import OwlLuna

func temporaryRoot(_ testCase: XCTestCase) -> StorageRoot {
    let url = FileManager.default.temporaryDirectory.appending(path: "owlluna-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    testCase.addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return StorageRoot(url: url)
}

func stroke(from start: CGPoint, to end: CGPoint, width: CGFloat = 3) -> PKStroke {
    let points = (0..<8).map { i -> PKStrokePoint in
        let t = CGFloat(i) / 7
        return PKStrokePoint(location: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t),
                             timeOffset: TimeInterval(t) * 0.1, size: CGSize(width: width, height: width),
                             opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
    }
    return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1_790_000_000)))
}

func dot(at point: CGPoint) -> PKStroke {
    stroke(from: CGPoint(x: point.x - 10, y: point.y), to: CGPoint(x: point.x + 10, y: point.y))
}

private func json(_ data: Data) throws -> JSONValue { try JSONValue.parse(data) }

/// The library folder itself, and the packages an older build left in it under its old name.
final class StorageTests: XCTestCase {
    private let paper = PageDefaults(template: .grid, paperColor: .white, pageSize: .letter)

    private func legacyPackage(_ id: UUID, in root: StorageRoot) -> URL {
        root.library.appending(path: "\(id.uuidString).\(StorageRoot.legacyPackageExtension)", directoryHint: .isDirectory)
    }

    /// Writes a notebook, then renames its package the way the old app named it.
    private func makeLegacyNotebook(_ title: String, in root: StorageRoot) async throws -> NotebookManifest {
        let manifest = NotebookManifest(title: title, defaults: paper, pages: [paper.newPage()])
        let package = NotebookPackage(root: root, id: manifest.id)
        try await package.create(manifest)
        let receipt = try await package.write(SaveSnapshot(manifest: manifest, ink: [manifest.pages[0].id: PKDrawing(strokes: [dot(at: CGPoint(x: 50, y: 50))])]))
        try FileManager.default.moveItem(at: package.url, to: legacyPackage(manifest.id, in: root))
        return receipt.manifest
    }

    func testALegacyPackageIsAdoptedAndOpens() async throws {
        let root = temporaryRoot(self)
        let manifest = try await makeLegacyNotebook("Old Notes", in: root)
        XCTAssertEqual(root.packageIDs(), [], "the old name isn't a notebook until it's adopted")

        XCTAssertEqual(root.adoptLegacyPackages(), [manifest.id])
        XCTAssertEqual(root.packageIDs(), [manifest.id])
        XCTAssertEqual(root.package(manifest.id).pathExtension, StorageRoot.packageExtension)
        let package = NotebookPackage(root: root, id: manifest.id)
        let load = try await package.readManifest()
        XCTAssertEqual(load.manifest.title, "Old Notes")
        XCTAssertTrue(load.quarantined.isEmpty && load.recoveredPageIDs.isEmpty, "the notebook comes through whole")
        guard case .ink(let ink, _) = await package.readInk(manifest.pages[0].id) else { return XCTFail("the ink didn't come through") }
        XCTAssertEqual(ink.strokes.count, 1)
    }

    func testAdoptionIsIdempotentAndLeavesStrangersAlone() async throws {
        let root = temporaryRoot(self)
        let fileManager = FileManager.default
        let legacy = try await makeLegacyNotebook("Old", in: root)
        let twice = try await makeLegacyNotebook("Both", in: root)
        let old = legacyPackage(twice.id, in: root)
        try fileManager.copyItem(at: old, to: root.package(twice.id))
        let stranger = root.library.appending(path: "Notes.\(StorageRoot.legacyPackageExtension)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: stranger, withIntermediateDirectories: true)

        XCTAssertEqual(root.adoptLegacyPackages(), [legacy.id])
        XCTAssertEqual(Set(root.packageIDs()), [legacy.id, twice.id])
        XCTAssertTrue(fileManager.fileExists(atPath: old.path(percentEncoded: false)), "a package that already has a successor is left as it is")
        XCTAssertTrue(fileManager.fileExists(atPath: stranger.path(percentEncoded: false)), "a folder not named by a UUID is left as it is")
        XCTAssertFalse(fileManager.fileExists(atPath: legacyPackage(legacy.id, in: root).path(percentEncoded: false)))

        XCTAssertEqual(root.adoptLegacyPackages(), [], "a second pass finds nothing to do")
        XCTAssertEqual(Set(root.packageIDs()), [legacy.id, twice.id])
        XCTAssertTrue(fileManager.fileExists(atPath: old.path(percentEncoded: false)))
    }

    func testAnEmptyOrMissingLibraryAdoptsNothing() {
        let root = temporaryRoot(self)
        XCTAssertEqual(root.adoptLegacyPackages(), [])
        try? FileManager.default.createDirectory(at: root.library, withIntermediateDirectories: true)
        XCTAssertEqual(root.adoptLegacyPackages(), [])
    }
}

final class ManifestCodecTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_790_000_000)

    private func sampleManifest() -> NotebookManifest {
        var pdfPage = NotebookPage(background: .pdf(file: "a.pdf", index: 3), paperColor: .white, size: CGSize(width: 792, height: 612))
        pdfPage.inkHash = "abc123"
        let pages = [NotebookPage.template(.grid, color: .ivory, size: .a4), pdfPage,
                     NotebookPage(background: .image(file: "b.jpg"), paperColor: .white, size: CGSize(width: 612, height: 400))]
        var manifest = NotebookManifest(title: "Cell Biology", createdAt: fixedDate,
                                        cover: CoverSpec(style: .print, cloth: .moss, inks: (.teal, .pink), seed: 4_000_000_000),
                                        defaults: PageDefaults(template: .dotted, paperColor: .yellow, pageSize: .a5), pages: pages)
        manifest.modifiedAt = fixedDate.addingTimeInterval(60)
        manifest.recordings = [RecordingEntry(id: UUID(), file: "r.m4a", createdAt: fixedDate, duration: 12.5)]
        manifest.library = LibraryState(isFavorite: true, deletedAt: fixedDate, folderID: UUID(), lastOpenedAt: fixedDate, currentPage: 2)
        return manifest
    }

    func testRoundTripKeepsEveryField() throws {
        let manifest = sampleManifest()
        let decoded = try ManifestCodec.decode(ManifestCodec.encode(manifest), fallbackID: UUID())
        XCTAssertEqual(decoded.manifest, manifest)
        XCTAssertTrue(decoded.warnings.isEmpty, "\(decoded.warnings)")
        XCTAssertEqual(decoded.manifest.cover.inks.1, .pink)
        XCTAssertEqual(decoded.manifest.cover.seed, 4_000_000_000)
    }

    func testUnknownKeysAndValuesSurviveARewrite() throws {
        let id = UUID(), pageID = UUID(), videoID = UUID()
        let source = """
        {"schemaVersion": 2, "id": "\(id)", "title": "Future", "createdAt": "2026-09-28T10:00:00.000Z",
         "modifiedAt": "2026-09-28T10:00:00.000Z", "sync": {"etag": "x1", "peers": [1, 2]},
         "cover": {"style": "foil", "cloth": "velvet", "inks": ["gold", "teal"], "seed": 7, "emboss": true},
         "defaults": {"template": "hexagon", "paperColor": "white", "pageSize": "b5"},
         "pages": [
           {"id": "\(pageID)", "background": {"kind": "template", "template": "hexagon"}, "paperColor": "neon",
            "size": {"width": 612, "height": 792}, "ink": null, "inkHash": null, "layers": ["a", "b"]},
           {"id": "\(videoID)", "background": {"kind": "video", "file": "v.mov", "loop": true}, "paperColor": "white",
            "size": {"width": 612, "height": 792}}
         ],
         "recordings": [], "library": {"favorite": false, "pinnedAt": "2026-01-01"}}
        """
        let (manifest, _) = try ManifestCodec.decode(Data(source.utf8), fallbackID: UUID())
        XCTAssertEqual(manifest.pages.count, 2)
        XCTAssertEqual(manifest.pages[0].template, .blank, "unknown templates render blank")
        XCTAssertEqual(manifest.pages[0].paperColor, .white, "unknown colours fall back")
        XCTAssertEqual(manifest.cover.style, .cloth)
        guard case .unknown = manifest.pages[1].background else { return XCTFail("unknown background kind must be kept") }

        let rewritten = try json(ManifestCodec.encode(manifest))
        XCTAssertEqual(rewritten["sync"], .object(["etag": .string("x1"), "peers": .array([.number(1), .number(2)])]))
        XCTAssertEqual(rewritten["cover"]?["style"], .string("foil"))
        XCTAssertEqual(rewritten["cover"]?["cloth"], .string("velvet"))
        XCTAssertEqual(rewritten["cover"]?["inks"], .array([.string("gold"), .string("teal")]))
        XCTAssertEqual(rewritten["cover"]?["emboss"], .bool(true))
        XCTAssertEqual(rewritten["defaults"]?["template"], .string("hexagon"))
        XCTAssertEqual(rewritten["defaults"]?["pageSize"], .string("b5"))
        let pages = try XCTUnwrap(rewritten["pages"]?.arrayValue)
        XCTAssertEqual(pages[0]["background"]?["template"], .string("hexagon"))
        XCTAssertEqual(pages[0]["paperColor"], .string("neon"))
        XCTAssertEqual(pages[0]["layers"], .array([.string("a"), .string("b")]))
        XCTAssertEqual(pages[1]["background"], .object(["kind": .string("video"), "file": .string("v.mov"), "loop": .bool(true)]))
        XCTAssertEqual(rewritten["library"]?["pinnedAt"], .string("2026-01-01"))
    }

    func testUnreadablePagesAreKeptInPlace() throws {
        let first = UUID(), last = UUID()
        let source = """
        {"schemaVersion": 2, "title": "Mixed", "pages": [
          {"id": "\(first)", "background": {"kind": "template", "template": "grid"}, "paperColor": "white", "size": {"width": 612, "height": 792}},
          {"garbage": true},
          42,
          {"id": "\(last)", "background": {"kind": "template", "template": "dotted"}, "paperColor": "white", "size": {"width": 612, "height": 792}}
        ]}
        """
        let (manifest, warnings) = try ManifestCodec.decode(Data(source.utf8), fallbackID: UUID())
        XCTAssertEqual(manifest.pages.map(\.id), [first, last])
        XCTAssertEqual(manifest.opaquePages.count, 2)
        XCTAssertFalse(warnings.isEmpty)
        let pages = try XCTUnwrap(json(ManifestCodec.encode(manifest))["pages"]?.arrayValue)
        XCTAssertEqual(pages.count, 4)
        XCTAssertEqual(pages[1], .object(["garbage": .bool(true)]))
        XCTAssertEqual(pages[2], .number(42))
        XCTAssertEqual(pages[3]["id"], .string(last.uuidString))
    }

    func testMalformedFieldIsWrittenBackUnlessChanged() throws {
        let pageID = UUID()
        let source = """
        {"title": 12, "pages": [{"id": "\(pageID)", "background": {"kind": "template", "template": "grid"},
          "paperColor": "white", "size": "big"}]}
        """
        var (manifest, _) = try ManifestCodec.decode(Data(source.utf8), fallbackID: UUID())
        XCTAssertEqual(manifest.pages[0].size, PageSize.letter.points)
        XCTAssertEqual(manifest.title, "Untitled Notebook")
        var rewritten = try json(ManifestCodec.encode(manifest))
        XCTAssertEqual(rewritten["pages"]?.arrayValue?.first?["size"], .string("big"))
        XCTAssertEqual(rewritten["title"], .number(12))

        manifest.pages[0].size = CGSize(width: 100, height: 200)
        manifest.title = "Renamed"
        rewritten = try json(ManifestCodec.encode(manifest))
        XCTAssertEqual(rewritten["pages"]?.arrayValue?.first?["size"], ManifestCodec.encodeSize(CGSize(width: 100, height: 200)))
        XCTAssertEqual(rewritten["title"], .string("Renamed"))
    }

    func testInvalidManifestsThrow() {
        XCTAssertThrowsError(try ManifestCodec.decode(Data("not json".utf8), fallbackID: UUID())) { XCTAssertEqual($0 as? ManifestError, .notJSON) }
        XCTAssertThrowsError(try ManifestCodec.decode(Data("[1,2]".utf8), fallbackID: UUID())) { XCTAssertEqual($0 as? ManifestError, .notAnObject) }
        XCTAssertThrowsError(try ManifestCodec.decode(Data(#"{"pages": "lots"}"#.utf8), fallbackID: UUID())) {
            XCTAssertEqual($0 as? ManifestError, .pagesUnreadable)
        }
    }

    func testNewerSchemaIsReadOnly() async throws {
        let root = temporaryRoot(self)
        var manifest = sampleManifest()
        manifest.schemaVersion = 3
        let package = NotebookPackage(root: root, id: manifest.id)
        try FileManager.default.createDirectory(at: package.url, withIntermediateDirectories: true)
        try ManifestCodec.encode(manifest).write(to: package.manifestURL)
        let load = try await package.readManifest()
        XCTAssertTrue(load.isReadOnly)
        do {
            _ = try await package.write(SaveSnapshot(manifest: load.manifest, ink: [:]))
            XCTFail("a newer manifest must never be rewritten")
        } catch {
            XCTAssertEqual(error as? PackageError, .readOnly)
        }
    }
}

final class NotebookPackageTests: XCTestCase {
    private func makePackage(pages: Int = 3) async throws -> (NotebookPackage, NotebookManifest, StorageRoot) {
        let root = temporaryRoot(self)
        let manifest = NotebookManifest(title: "Test", defaults: PageDefaults(template: .grid, paperColor: .white, pageSize: .letter),
                                        pages: (0..<pages).map { _ in .template(.grid, color: .white, size: .letter) })
        let package = NotebookPackage(root: root, id: manifest.id)
        try await package.create(manifest)
        return (package, manifest, root)
    }

    private func drawing(_ count: Int, y: CGFloat = 100) -> PKDrawing {
        PKDrawing(strokes: (0..<count).map { dot(at: CGPoint(x: 60 + CGFloat($0) * 30, y: y)) })
    }

    func testWritesOnlyDirtyPagesThenTheManifest() async throws {
        let (package, manifest, _) = try await makePackage()
        let receipt = try await package.write(SaveSnapshot(manifest: manifest, ink: [manifest.pages[1].id: drawing(4)]))
        let fileManager = FileManager.default
        XCTAssertFalse(fileManager.fileExists(atPath: package.inkURL(manifest.pages[0].id).path(percentEncoded: false)))
        XCTAssertTrue(fileManager.fileExists(atPath: package.inkURL(manifest.pages[1].id).path(percentEncoded: false)))
        XCTAssertNotNil(receipt.manifest.pages[1].inkHash)
        XCTAssertNil(receipt.manifest.pages[0].inkHash)

        let firstWrite = try Data(contentsOf: package.inkURL(manifest.pages[1].id))
        _ = try await package.write(SaveSnapshot(manifest: receipt.manifest, ink: [manifest.pages[2].id: drawing(2)]))
        XCTAssertEqual(try Data(contentsOf: package.inkURL(manifest.pages[1].id)), firstWrite)

        let load = try await package.readManifest()
        XCTAssertEqual(load.manifest.pages[1].inkHash, receipt.manifest.pages[1].inkHash)
        guard case .ink(let read, let hash) = await package.readInk(manifest.pages[1].id) else { return XCTFail("ink expected") }
        XCTAssertEqual(read.strokes.count, 4)
        XCTAssertEqual(hash, receipt.manifest.pages[1].inkHash)
    }

    func testErasingEveryStrokeRemovesTheInkFile() async throws {
        let (package, manifest, _) = try await makePackage()
        let page = manifest.pages[0].id
        let first = try await package.write(SaveSnapshot(manifest: manifest, ink: [page: drawing(3)]))
        let second = try await package.write(SaveSnapshot(manifest: first.manifest, ink: [page: PKDrawing()]))
        XCTAssertNil(second.manifest.pages[0].inkHash)
        XCTAssertFalse(FileManager.default.fileExists(atPath: package.inkURL(page).path(percentEncoded: false)))
    }

    func testCorruptInkIsQuarantinedAndNeverOverwritten() async throws {
        let (package, manifest, _) = try await makePackage()
        let page = manifest.pages[0].id
        let garbage = Data("definitely not a drawing".utf8)
        try FileManager.default.createDirectory(at: package.inkDirectory, withIntermediateDirectories: true)
        try garbage.write(to: package.inkURL(page))

        guard case .quarantined(let file) = await package.readInk(page) else { return XCTFail("expected quarantine") }
        let quarantined = package.url.appending(path: file)
        XCTAssertEqual(try Data(contentsOf: quarantined), garbage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: package.inkURL(page).path(percentEncoded: false)))

        _ = try await package.write(SaveSnapshot(manifest: manifest, ink: [page: drawing(2)]))
        XCTAssertEqual(try Data(contentsOf: quarantined), garbage, "a quarantined file is never overwritten")

        try garbage.write(to: package.inkURL(page))
        guard case .quarantined(let second) = await package.readInk(page) else { return XCTFail("expected quarantine") }
        XCTAssertNotEqual(second, file)
        XCTAssertEqual(try Data(contentsOf: quarantined), garbage)
        let listed = await package.quarantinedFiles()
        XCTAssertEqual(listed.count, 2)
    }

    func testCorruptManifestFallsBackToThePreviousOne() async throws {
        let (package, manifest, _) = try await makePackage()
        var renamed = manifest
        renamed.title = "Second save"
        try await package.writeManifest(renamed)
        let garbage = Data("{ truncated".utf8)
        try garbage.write(to: package.manifestURL)

        let load = try await package.readManifest()
        XCTAssertEqual(load.manifest.title, "Test")
        XCTAssertTrue(load.needsSave)
        XCTAssertEqual(load.quarantined, ["manifest.json.corrupt"])
        XCTAssertEqual(try Data(contentsOf: package.url.appending(path: "manifest.json.corrupt")), garbage)
    }

    func testUnreadableManifestsAreRebuiltFromInk() async throws {
        let (package, manifest, _) = try await makePackage()
        _ = try await package.write(SaveSnapshot(manifest: manifest, ink: [manifest.pages[0].id: drawing(3), manifest.pages[2].id: drawing(1)]))
        try Data("x".utf8).write(to: package.manifestURL)
        try Data("y".utf8).write(to: package.previousManifestURL)

        let load = try await package.readManifest()
        XCTAssertEqual(Set(load.manifest.pages.map(\.id)), [manifest.pages[0].id, manifest.pages[2].id])
        XCTAssertTrue(load.needsSave)
        XCTAssertEqual(Set(load.quarantined), ["manifest.json.corrupt", "manifest.prev.json.corrupt"])
    }

    func testCrashBetweenInkAndManifestWritesIsRecovered() async throws {
        let (package, manifest, _) = try await makePackage(pages: 2)
        let saved = try await package.write(SaveSnapshot(manifest: manifest, ink: [manifest.pages[0].id: drawing(2)]))
        let manifestDate = try XCTUnwrap(package.manifestURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)

        // The next save wrote page 0's new ink and a brand-new page's ink, then the app died before the manifest.
        let newPage = UUID()
        try drawing(5).dataRepresentation().write(to: package.inkURL(manifest.pages[0].id))
        try drawing(1).dataRepresentation().write(to: package.inkURL(newPage))
        for file in [package.inkURL(manifest.pages[0].id), package.inkURL(newPage)] {
            try FileManager.default.setAttributes([.modificationDate: manifestDate.addingTimeInterval(5)], ofItemAtPath: file.path(percentEncoded: false))
        }

        let load = try await package.readManifest()
        XCTAssertEqual(load.recoveredPageIDs, [newPage])
        XCTAssertEqual(load.manifest.pages.last?.id, newPage)
        XCTAssertTrue(load.needsSave)
        guard case .ink(let ink, let hash) = await package.readInk(manifest.pages[0].id) else { return XCTFail() }
        XCTAssertEqual(ink.strokes.count, 5, "the newest ink wins")
        XCTAssertNotEqual(hash, saved.manifest.pages[0].inkHash, "the stale hash reveals the interrupted save")
        guard case .ink(let recovered, _) = await package.readInk(newPage) else { return XCTFail() }
        XCTAssertEqual(recovered.strokes.count, 1)
    }

    func testAFailedWriteLeavesTheManifestAloneAndCanBeRetried() async throws {
        let (package, manifest, _) = try await makePackage()
        let before = try Data(contentsOf: package.manifestURL)
        let fileManager = FileManager.default
        try fileManager.removeItem(at: package.inkDirectory)
        try Data("blocker".utf8).write(to: package.inkDirectory)

        let snapshot = SaveSnapshot(manifest: manifest, ink: [manifest.pages[0].id: drawing(2)])
        do {
            _ = try await package.write(snapshot)
            XCTFail("the write should fail while ink/ is not a directory")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: package.manifestURL), before)

        try fileManager.removeItem(at: package.inkDirectory)
        let receipt = try await package.write(snapshot)
        XCTAssertNotNil(receipt.manifest.pages[0].inkHash)
    }

    func testGarbageCollectionOnlyRemovesUnlistedPages() async throws {
        let (package, manifest, _) = try await makePackage()
        let receipt = try await package.write(SaveSnapshot(manifest: manifest, ink: Dictionary(uniqueKeysWithValues: manifest.pages.map { ($0.id, drawing(1)) })))
        var trimmed = receipt.manifest
        let removed = trimmed.pages.remove(at: 1)
        try Data("bad".utf8).write(to: package.inkURL(UUID()).appendingPathExtension("corrupt"))
        try await Task.sleep(for: .milliseconds(20))
        try await package.writeManifest(trimmed)
        await package.collectGarbage(keeping: trimmed)
        let names = try FileManager.default.contentsOfDirectory(atPath: package.inkDirectory.path(percentEncoded: false))
        XCTAssertFalse(names.contains("\(removed.id.uuidString).pkdrawing"))
        XCTAssertTrue(names.contains("\(trimmed.pages[0].id.uuidString).pkdrawing"))
        XCTAssertEqual(names.filter { $0.contains(".corrupt") }.count, 1)
    }
}
