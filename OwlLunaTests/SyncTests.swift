import XCTest
import PencilKit
@testable import OwlLuna

/// Two devices and the synced copy between them, played out with three folders.
final class SyncTests: XCTestCase {
    private let paper = PageDefaults(template: .grid, paperColor: .white, pageSize: .letter)
    private var cloud: CloudFolder!
    private var a: StorageRoot!
    private var b: StorageRoot!

    override func setUp() {
        super.setUp()
        a = temporaryRoot(self)
        b = temporaryRoot(self)
        cloud = CloudFolder(url: temporaryRoot(self).url)
    }

    @discardableResult
    private func makeNotebook(_ title: String, on root: StorageRoot, strokes: Int = 1) async throws -> NotebookManifest {
        let manifest = NotebookManifest(title: title, defaults: paper, pages: [paper.newPage(), paper.newPage()])
        let package = NotebookPackage(root: root, id: manifest.id)
        try await package.create(manifest)
        let ink = PKDrawing(strokes: (0..<strokes).map { stroke(from: CGPoint(x: 40, y: 40 + CGFloat($0) * 30), to: CGPoint(x: 200, y: 60 + CGFloat($0) * 30)) })
        let receipt = try await package.write(SaveSnapshot(manifest: manifest, ink: [manifest.pages[0].id: ink]))
        try await package.writeThumbnail(Data([1, 2, 3]), pageID: manifest.pages[0].id, key: "cache")
        return receipt.manifest
    }

    /// An edit as the editor would save it: more ink, a later modification date, perhaps a new title.
    private func edit(_ id: UUID, on root: StorageRoot, title: String? = nil, strokes: Int, after seconds: TimeInterval) async throws {
        let package = NotebookPackage(root: root, id: id)
        var manifest = try await package.readManifest().manifest
        manifest.modifiedAt = manifest.modifiedAt.addingTimeInterval(seconds)
        if let title { manifest.title = title }
        let ink = PKDrawing(strokes: (0..<strokes).map { stroke(from: CGPoint(x: 40, y: 40 + CGFloat($0) * 30), to: CGPoint(x: 200, y: 60 + CGFloat($0) * 30)) })
        _ = try await package.write(SaveSnapshot(manifest: manifest, ink: [manifest.pages[0].id: ink]))
    }

    private func strokes(_ manifest: NotebookManifest, on root: StorageRoot) async -> Int {
        guard case .ink(let drawing, _) = await NotebookPackage(root: root, id: manifest.id).readInk(manifest.pages[0].id) else { return 0 }
        return drawing.strokes.count
    }

    private func titles(on root: StorageRoot) async -> [String] {
        var result: [String] = []
        for id in root.packageIDs() { if let title = try? await NotebookPackage(root: root, id: id).readManifest().manifest.title { result.append(title) } }
        return result.sorted()
    }

    @discardableResult
    private func sync(_ root: StorageRoot, busy: Set<UUID> = []) async throws -> SyncReport {
        try await LibrarySync.run(root: root, cloud: cloud, busy: busy)
    }

    func testANotebookWrittenOnOneDeviceArrivesOnTheOther() async throws {
        let physics = try await makeNotebook("Physics", on: a, strokes: 2)
        let first = try await sync(a)
        XCTAssertEqual(first.pushed, [physics.id])
        XCTAssertFalse(first.changedHere)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloud.package(physics.id).appending(path: "thumbs").path(percentEncoded: false)), "thumbnails don't travel")

        let second = try await sync(b)
        XCTAssertEqual(second.pulled, [physics.id])
        XCTAssertTrue(second.changedHere)
        let arrived = try await NotebookPackage(root: b, id: physics.id).readManifest()
        XCTAssertEqual(arrived.manifest.title, "Physics")
        XCTAssertTrue(arrived.recoveredPageIDs.isEmpty && arrived.quarantined.isEmpty, "the notebook arrives whole")
        let count = await strokes(physics, on: b)
        XCTAssertEqual(count, 2)

        let againA = try await sync(a), againB = try await sync(b)
        XCTAssertEqual(againA, SyncReport(), "with nothing changed, a sync does nothing")
        XCTAssertEqual(againB, SyncReport())

        try await edit(physics.id, on: b, title: "Physics II", strokes: 5, after: 60)
        let pushed = try await sync(b)
        XCTAssertEqual(pushed.pushed, [physics.id])
        let pulled = try await sync(a)
        XCTAssertEqual(pulled.pulled, [physics.id])
        let edited = await strokes(physics, on: a)
        XCTAssertEqual(edited, 5, "an edit made on the second device comes back to the first")
        let names = await titles(on: a)
        XCTAssertEqual(names, ["Physics II"])
    }

    func testNotebooksChangedOnBothDevicesAreBothKept() async throws {
        let notes = try await makeNotebook("Notes", on: a)
        try await sync(a)
        try await sync(b)

        try await edit(notes.id, on: a, strokes: 3, after: 60)
        try await edit(notes.id, on: b, strokes: 7, after: 120)
        try await sync(a)
        let report = try await sync(b)
        XCTAssertEqual(report.conflictCopies.count, 1)
        XCTAssertEqual(report.pushed, [notes.id], "the newer version keeps the notebook's place")
        let onB = await titles(on: b)
        XCTAssertEqual(onB, ["Notes", "Notes (conflicted copy)"])
        let winner = await strokes(notes, on: b)
        XCTAssertEqual(winner, 7)

        try await sync(b)
        let last = try await sync(a)
        XCTAssertEqual(Set(last.pulled).count, 2, "the first device receives the newer version and the copy of its own")
        let onA = await titles(on: a)
        XCTAssertEqual(onA, ["Notes", "Notes (conflicted copy)"])
        let newer = await strokes(notes, on: a)
        XCTAssertEqual(newer, 7)
        var copyStrokes = 0
        for id in a.packageIDs() where id != notes.id {
            let manifest = try await NotebookPackage(root: a, id: id).readManifest().manifest
            XCTAssertEqual(manifest.id, id, "the copy is a notebook of its own")
            copyStrokes = await strokes(manifest, on: a)
        }
        XCTAssertEqual(copyStrokes, 3, "nothing written on either device is lost")
        let settledA = try await sync(a), settledB = try await sync(b)
        XCTAssertEqual(settledA, SyncReport())
        XCTAssertEqual(settledB, SyncReport())
    }

    func testADeleteCarriesOverUnlessTheNotebookWasWrittenInSince() async throws {
        let old = try await makeNotebook("Old", on: a), kept = try await makeNotebook("Kept", on: a)
        try await sync(a)
        try await sync(b)

        try FileManager.default.removeItem(at: a.package(old.id))
        try FileManager.default.removeItem(at: a.package(kept.id))
        let removed = try await sync(a)
        XCTAssertEqual(Set(removed.removedThere), [old.id, kept.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: cloud.tombstone(old.id).path(percentEncoded: false)))

        try await edit(kept.id, on: b, title: "Kept and written in", strokes: 4, after: 60)
        let report = try await sync(b)
        XCTAssertEqual(report.removedHere, [old.id], "a notebook deleted elsewhere and untouched here goes")
        XCTAssertEqual(report.pushed, [kept.id], "one written in since is kept: writing wins over a delete")
        let onB = await titles(on: b)
        XCTAssertEqual(onB, ["Kept and written in"])

        let back = try await sync(a)
        XCTAssertEqual(back.pulled, [kept.id])
        let onA = await titles(on: a)
        XCTAssertEqual(onA, ["Kept and written in"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.package(old.id).path(percentEncoded: false)), "and the deleted one doesn't come back")
    }

    func testAnOpenNotebookAndAHalfArrivedOneAreLeftForLater() async throws {
        let open = try await makeNotebook("Open", on: a)
        let busy = try await sync(a, busy: [open.id])
        XCTAssertEqual(busy.waiting, [open.id])
        XCTAssertTrue(busy.pushed.isEmpty)
        try await sync(a)
        try await sync(b)

        try await edit(open.id, on: a, strokes: 6, after: 60)
        try await sync(a)
        let manifest = cloud.package(open.id).appending(path: "manifest.json")
        let whole = try Data(contentsOf: manifest)
        try Data("{".utf8).write(to: manifest)
        let report = try await sync(b)
        XCTAssertEqual(report.waiting, [open.id], "a manifest that can't be read yet is waited for")
        let untouched = await strokes(open, on: b)
        XCTAssertEqual(untouched, 1)
        try whole.write(to: manifest)
        let later = try await sync(b)
        XCTAssertEqual(later.pulled, [open.id])
    }

    func testFoldersAndStickersFollow() async throws {
        let science = FolderEntry(id: UUID(), name: "Science", clothRaw: "jade", createdAt: .now, sortIndex: 0)
        let labs = FolderEntry(id: UUID(), name: "Labs", clothRaw: "moss", createdAt: .now, sortIndex: 1, parentID: science.id)
        var file = FolderFile()
        file.folders = [science, labs]
        try file.write(a)
        try FileManager.default.createDirectory(at: a.stickers, withIntermediateDirectories: true)
        try Data([1]).write(to: a.stickers.appending(path: "cat.png"))
        try await sync(a)
        let first = try await sync(b)
        XCTAssertTrue(first.foldersChanged && first.stickersChanged)
        XCTAssertEqual(FolderFile.read(b).folders.map(\.name), ["Science", "Labs"])
        XCTAssertEqual(FolderFile.read(b).folders.last?.parentID, science.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.stickers.appending(path: "cat.png").path(percentEncoded: false)))

        var changed = FolderFile.read(b)
        changed.folders.removeAll { $0.id == labs.id }
        changed.folders.append(FolderEntry(id: UUID(), name: "Art", clothRaw: "rose", createdAt: .now, sortIndex: 2))
        try changed.write(b)
        try FileManager.default.removeItem(at: b.stickers.appending(path: "cat.png"))
        try Data([2]).write(to: b.stickers.appending(path: "dog.png"))
        try await sync(b)
        try await sync(a)
        XCTAssertEqual(FolderFile.read(a).folders.map(\.name).sorted(), ["Art", "Science"], "a folder deleted on one device goes from the other, and a new one arrives")
        let stickers = try FileManager.default.contentsOfDirectory(atPath: a.stickers.path(percentEncoded: false))
        XCTAssertEqual(stickers, ["dog.png"])
    }

    func testAPackageUnderTheOldNameInTheSyncedCopyIsLeftAlone() async throws {
        let physics = try await makeNotebook("Physics", on: a)
        try await sync(a)
        let synced = cloud.package(physics.id)
        try FileManager.default.moveItem(at: synced, to: synced.deletingPathExtension().appendingPathExtension(StorageRoot.legacyPackageExtension))

        let report = try await sync(b)
        XCTAssertEqual(report, SyncReport(), "a name the app never writes to the synced copy is neither pulled nor deleted")
        XCTAssertEqual(b.packageIDs(), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cloud.library.path(percentEncoded: false)).filter { $0.hasSuffix(".\(StorageRoot.legacyPackageExtension)") }.count, 1)
    }
}
