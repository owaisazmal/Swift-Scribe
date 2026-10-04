import XCTest
import SwiftData
@testable import NotesApp

/// Tags on notebooks and pages: their names, the manifest, the index, renaming across the library, and the smart shelves that filter by them.
@MainActor
final class TagTests: XCTestCase {
    private var containers: [ModelContainer] = []
    private let paper = PageDefaults(template: .narrowRuled, paperColor: .white, pageSize: .letter)

    private func makeStore() throws -> LibraryStore {
        let schema = LibraryIndex.schema
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        containers.append(container)
        return LibraryStore(root: temporaryRoot(self), context: container.mainContext)
    }

    private func makeNotebook(_ title: String, in store: LibraryStore, tags: [String] = [], pageTags: [[String]] = [[]]) async throws -> NotebookRecord {
        var manifest = NotebookManifest(title: title, defaults: paper, pages: pageTags.map { tags in
            var page = paper.newPage()
            page.tags = tags
            return page
        })
        manifest.library.tags = tags
        try await NotebookPackage(root: store.root, id: manifest.id).create(manifest)
        store.index(manifest)
        return try XCTUnwrap(store.record(manifest.id))
    }

    private func manifest(_ id: UUID, in store: LibraryStore, until condition: (NotebookManifest) -> Bool) async throws -> NotebookManifest {
        let package = NotebookPackage(root: store.root, id: id)
        let deadline = Date().addingTimeInterval(5)
        var manifest = try await package.readManifest().manifest
        while !condition(manifest), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
            manifest = try await package.readManifest().manifest
        }
        return manifest
    }

    private func savedShelves(_ store: LibraryStore, until condition: ([SmartShelf]) -> Bool) async throws -> [SmartShelf] {
        let deadline = Date().addingTimeInterval(5)
        while !condition(SmartShelfFile.read(store.root).shelves), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        return SmartShelfFile.read(store.root).shelves
    }

    // MARK: Names

    func testNamesAreTidied() {
        XCTAssertEqual(Tags.normalized("  exam "), "exam")
        XCTAssertEqual(Tags.normalized("#exam"), "exam")
        XCTAssertEqual(Tags.normalized("# # week   3\n"), "week 3", "inner space collapses to one")
        XCTAssertEqual(Tags.normalized("c#"), "c#", "only a leading # goes")
        XCTAssertNil(Tags.normalized("   "))
        XCTAssertNil(Tags.normalized("#"))
        XCTAssertEqual(Tags.normalized(String(repeating: "a", count: 60))?.count, Tags.maximumLength)
        XCTAssertEqual(Tags.key("Révision"), Tags.key("revision"), "case and accents don't make a new tag")
        XCTAssertNotEqual(Tags.key("exam"), Tags.key("exams"))
    }

    func testAListKeepsOneSpellingOfEachTagInOrder() {
        XCTAssertEqual(Tags.merged(["week 10", "Exam", "#exam", " ", "week 2", "EXAM"]), ["Exam", "week 2", "week 10"])
        XCTAssertEqual(Tags.merged([]), [])
        XCTAssertTrue(Tags.contains(["Exam"], "exam"))
        XCTAssertEqual(Tags.renaming(["exam", "week 3"], "EXAM", to: "finals"), ["finals", "week 3"])
        XCTAssertEqual(Tags.renaming(["exam", "week 3"], "exam", to: "Week 3"), ["Week 3"], "renaming onto a tag already there merges the two")
        XCTAssertEqual(Tags.renaming(["exam", "week 3"], "exam", to: nil), ["week 3"])
        XCTAssertEqual(Tags.split(Tags.joined(["exam", "week 3"])), ["exam", "week 3"])
        XCTAssertEqual(Tags.split(""), [])
    }

    func testTagsAreCountedOnceANotebook() {
        let counts = Tags.counts([(own: ["exam"], pages: ["Exam", "lab"]), (own: [], pages: ["exam"]), (own: ["exam", "draft"], pages: [])])
        XCTAssertEqual(counts.map(\.name), ["draft", "exam", "lab"], "the commonest spelling names the tag")
        XCTAssertEqual(counts.map(\.count), [1, 3, 1], "a notebook carrying a tag on itself and on a page counts once")
    }

    // MARK: Manifest

    func testTagsSurviveTheManifest() throws {
        var manifest = NotebookManifest(title: "Biology", defaults: paper, pages: [paper.newPage(), paper.newPage()])
        XCTAssertEqual(manifest.library.tags, [])
        XCTAssertNil(manifest.library.extra["tags"], "an untagged notebook's manifest says nothing about tags")
        let look = manifest.pages[0].appearanceKey
        manifest.library.tags = ["exam", "#Term 1", "EXAM"]
        manifest.pages[0].tags = ["mitosis"]
        XCTAssertEqual(manifest.pages[0].appearanceKey, look, "a tag doesn't change how the page looks, so its thumbnail stays")
        XCTAssertEqual(manifest.pages[0].duplicated().tags, ["mitosis"], "a copy of the page keeps its tags")

        let decoded = try ManifestCodec.decode(ManifestCodec.encode(manifest), fallbackID: manifest.id, fallbackDate: .now).manifest
        XCTAssertEqual(decoded.library.tags, ["exam", "Term 1"])
        XCTAssertEqual(decoded.pages.map(\.tags), [["mitosis"], []])
        XCTAssertEqual(decoded.pageTags, ["mitosis"])
        XCTAssertEqual(decoded.pages, manifest.pages)

        manifest.library.tags = []
        manifest.pages[0].tags = []
        XCTAssertNil(manifest.library.extra["tags"], "removing them leaves nothing behind")
        XCTAssertNil(manifest.pages[0].extra["tags"])
    }

    func testTagDataFromAnotherBuildIsKept() throws {
        let coloured = JSONValue.object(["name": .string("urgent"), "colour": .string("tomato")])
        var page = paper.newPage()
        page.extra["tags"] = .array([.string("exam"), coloured])
        XCTAssertEqual(page.tags, ["exam"], "an entry that isn't a name is passed over")
        page.tags = ["lab"]
        XCTAssertEqual(page.extra["tags"], .array([.string("lab"), coloured]), "and written back beside the names")
        page.tags = []
        XCTAssertEqual(page.extra["tags"], .array([coloured]))
        let decoded = try XCTUnwrap(ManifestCodec.decodePage(ManifestCodec.encodePage(page)))
        XCTAssertEqual(decoded.extra["tags"], .array([coloured]))

        var state = LibraryState()
        state.extra["tags"] = .string("exam, lab")
        XCTAssertEqual(state.tags, [], "a value that isn't a list isn't read")
        state.tags = []
        XCTAssertEqual(state.extra["tags"], .string("exam, lab"), "nor cleared by a build that can't read it")
        state.tags = ["exam"]
        XCTAssertEqual(state.extra["tags"], .array([.string("exam")]))
    }

    // MARK: Document

    func testTaggingAPageIsOneUndoStep() async throws {
        let root = temporaryRoot(self)
        let manifest = NotebookManifest(title: "Biology", defaults: paper, pages: (0..<3).map { _ in paper.newPage() })
        try await NotebookPackage(root: root, id: manifest.id).create(manifest)
        let document = try await NotebookDocument.open(manifest.id, root: root)
        var indexed: [NotebookManifest] = []
        document.onSaved = { indexed.append($0) }
        let page = document.pages[1].id
        document.undoManager.groupsByEvent = false
        document.undoManager.beginUndoGrouping()
        document.setTags(["Exam", " enzymes ", "exam"], forPage: page)
        document.undoManager.endUndoGrouping()
        XCTAssertEqual(document.pages[1].tags, ["enzymes", "Exam"])
        XCTAssertEqual(document.undoManager.undoActionName, "Tag Page")
        document.setTags(["Exam", "enzymes"], forPage: page)
        XCTAssertEqual(document.undoManager.undoActionName, "Tag Page", "the same tags again are no second step")
        document.undoManager.undo()
        XCTAssertEqual(document.pages[1].tags, [])
        XCTAssertFalse(document.undoManager.canUndo, "there was only the one step")
        document.undoManager.redo()
        XCTAssertEqual(document.pages[1].tags, ["enzymes", "Exam"])

        let saved = await document.flush()
        XCTAssertTrue(saved)
        XCTAssertEqual(indexed.last?.pageTags, ["enzymes", "Exam"], "a save that changed a page's tags tells the library")
        let reopened = try await document.package.readManifest().manifest
        XCTAssertEqual(reopened.pages[1].tags, ["enzymes", "Exam"])

        let count = indexed.count
        document.updateLibraryState { $0.tags = ["term 1"] }
        _ = await document.flush()
        XCTAssertEqual(indexed.count, count + 1, "and so does one that changed the notebook's")
        XCTAssertEqual(indexed.last?.library.tags, ["term 1"])
    }

    // MARK: Index

    func testTheIndexKeepsTagsAndSearchFindsThem() async throws {
        let store = try makeStore()
        let biology = try await makeNotebook("Biology", in: store, tags: ["exam", "term 1"], pageTags: [["mitosis"], [], ["Enzymes", "mitosis"]])
        let recipes = try await makeNotebook("Recipes", in: store)
        XCTAssertEqual(biology.tags, ["exam", "term 1"])
        XCTAssertEqual(biology.pageTags, ["Enzymes", "mitosis"], "the union of its pages' tags")
        XCTAssertEqual(recipes.tagsRaw, "")

        let context = ModelContext(try XCTUnwrap(containers.first))
        XCTAssertEqual(LibraryIndex.notebookIDs(matching: "exam", in: context), [biology.id])
        XCTAssertEqual(LibraryIndex.notebookIDs(matching: "#Term 1", in: context), [biology.id], "typed the way a tag is written")
        XCTAssertEqual(LibraryIndex.notebookIDs(matching: "enzym", in: context), [biology.id], "a page's tag finds its notebook")
        XCTAssertEqual(LibraryIndex.notebookIDs(matching: "recipes", in: context), [recipes.id])
        XCTAssertTrue(LibraryIndex.notebookIDs(matching: "physics", in: context).isEmpty)

        let version = store.searchVersion
        store.setTags(["Finals", "finals"], for: [recipes])
        XCTAssertEqual(recipes.tags, ["Finals"])
        XCTAssertEqual(store.searchVersion, version + 1, "a search under way is redone")
        let saved = try await manifest(recipes.id, in: store) { !$0.library.tags.isEmpty }
        XCTAssertEqual(saved.library.tags, ["Finals"])

        let fresh = try ModelContainer(for: LibraryIndex.schema, configurations: ModelConfiguration(schema: LibraryIndex.schema, isStoredInMemoryOnly: true))
        await LibraryIndex.refresh(root: store.root, context: fresh.mainContext)
        let rebuilt = try fresh.mainContext.fetch(FetchDescriptor<NotebookRecord>(sortBy: [SortDescriptor(\.title)]))
        XCTAssertEqual(rebuilt.map(\.tags), [["exam", "term 1"], ["Finals"]], "a rebuilt index reads the tags back")
        XCTAssertEqual(rebuilt.map(\.pageTags), [["Enzymes", "mitosis"], []])
    }

    func testAnIndexFromBeforeTagsIsMigrated() async throws {
        let root = temporaryRoot(self)
        try FileManager.default.createDirectory(at: root.url, withIntermediateDirectories: true)
        var page = paper.newPage()
        page.tags = ["mitosis"]
        var manifest = NotebookManifest(title: "Biology", defaults: paper, pages: [page])
        manifest.library.tags = ["exam"]
        manifest.library.isLocked = true
        try await NotebookPackage(root: root, id: manifest.id).create(manifest)

        try autoreleasepool {
            let old = Schema(versionedSchema: LibraryIndexSchemaV4.self)
            let container = try ModelContainer(for: old, configurations: ModelConfiguration(schema: old, url: root.indexStore))
            let record = LibraryIndexSchemaV4.NotebookRecord(id: manifest.id)
            record.title = "Biology"
            record.isLocked = true
            record.indexedAt = .distantFuture
            container.mainContext.insert(record)
            container.mainContext.insert(LibraryIndexSchemaV4.NotebookSearchText(notebookID: manifest.id, text: "prophase"))
            try container.mainContext.save()
        }

        let (container, recovered) = LibraryIndex.makeContainer(root: root)
        XCTAssertFalse(recovered, "the old index is migrated, not set aside")
        let context = container.mainContext
        let record = try XCTUnwrap(try context.fetch(FetchDescriptor<NotebookRecord>()).first)
        XCTAssertEqual(record.title, "Biology")
        XCTAssertTrue(record.isLocked, "what the record knew comes across")
        XCTAssertEqual([record.tagsRaw, record.pageTagsRaw], ["", ""], "the tags start empty")
        XCTAssertEqual(LibraryIndex.notebookIDs(matching: "prophase", in: ModelContext(container)), [manifest.id])
        await LibraryIndex.refresh(root: root, context: context, full: true)
        XCTAssertEqual(record.tags, ["exam"], "and the first refresh reads them from the manifest")
        XCTAssertEqual(record.pageTags, ["mitosis"])
        XCTAssertEqual(LibraryIndex.schemaNumber, 5)
    }

    func testTheLibrarysTagsComeFromItsRecords() async throws {
        let store = try makeStore()
        _ = try await makeNotebook("Biology", in: store, tags: ["exam"], pageTags: [["mitosis"], ["exam"]])
        let physics = try await makeNotebook("Physics", in: store, pageTags: [["exam"]])
        let diary = try await makeNotebook("Diary", in: store, tags: ["private"], pageTags: [["secret"]])
        let old = try await makeNotebook("Old", in: store, tags: ["archive"])
        store.setLocked(true, for: [diary])
        store.moveToTrash([old])
        let counts = store.tagCounts()
        XCTAssertEqual(counts.map(\.name), ["exam", "mitosis", "private"], "not a locked notebook's page tags, nor what is in the bin")
        XCTAssertEqual(counts.map(\.count), [2, 1, 1])
        XCTAssertFalse(physics.accessibilityDescription.contains("tagged"), "a cover speaks of the notebook's own tags only")
        XCTAssertTrue(diary.accessibilityDescription.contains("tagged private"), diary.accessibilityDescription)
    }

    // MARK: Rules and smart shelves

    func testAnyAndAllMatchNotebooks() {
        let any = TagRule(tags: ["exam", "lab"]), all = TagRule(tags: ["exam", "lab"], match: .all)
        XCTAssertTrue(any.matches(notebook: ["Lab"]))
        XCTAssertFalse(any.matches(notebook: ["term 1"]))
        XCTAssertFalse(all.matches(notebook: ["lab"]))
        XCTAssertTrue(all.matches(notebook: ["EXAM", "lab", "term 1"]))
        XCTAssertFalse(TagRule(tags: []).matches(notebook: ["exam"]), "a rule with no tags matches nothing")
        XCTAssertFalse(TagRule(tags: [], match: .all).matches(notebook: []))
    }

    func testAPageIsListedForItsOwnTags() {
        let any = TagRule(tags: ["exam", "lab"]), all = TagRule(tags: ["exam", "lab"], match: .all)
        XCTAssertTrue(any.lists(page: ["lab"], in: []))
        XCTAssertFalse(any.lists(page: [], in: ["exam"]), "a notebook's tag alone doesn't list every page in it")
        XCTAssertFalse(all.lists(page: ["lab"], in: []))
        XCTAssertTrue(all.lists(page: ["lab"], in: ["Exam"]), "asked for all, the notebook's tags count towards the rest")
        XCTAssertTrue(all.lists(page: ["lab", "exam"], in: []))
        XCTAssertFalse(all.lists(page: [], in: ["exam", "lab"]))
    }

    func testAShelfListsTheTaggedPagesOfItsNotebooks() async throws {
        let store = try makeStore()
        let biology = try await makeNotebook("Biology", in: store, tags: ["exam"], pageTags: [["lab"], [], ["lab", "week 3"]])
        let physics = try await makeNotebook("Physics", in: store, pageTags: [["lab"], ["exam"]])
        let sources = [biology, physics].map { TagPages.Source(id: $0.id, tags: $0.tags) }

        let labs = await TagPages.hits(for: TagRule(tags: ["LAB"]), in: sources, root: store.root)
        XCTAssertEqual(labs[biology.id]?.map(\.index), [0, 2])
        XCTAssertEqual(labs[biology.id]?.last?.snippet, "#lab  #week 3")
        XCTAssertEqual(labs[biology.id]?.last?.label(in: "Biology"), "Biology, page 3, tagged lab and week 3")
        XCTAssertEqual(labs[physics.id]?.map(\.index), [0])

        let both = await TagPages.hits(for: TagRule(tags: ["exam", "lab"], match: .all), in: sources, root: store.root)
        XCTAssertEqual(both[biology.id]?.map(\.index), [0, 2], "Biology is tagged exam itself")
        XCTAssertNil(both[physics.id], "no page of Physics carries both")

        var ahead = try await NotebookPackage(root: store.root, id: physics.id).readManifest().manifest.pages
        ahead[1].tags = ["lab"]
        let open = await TagPages.hits(for: TagRule(tags: ["lab"]), in: [TagPages.Source(id: physics.id, tags: [], pages: ahead)], root: store.root)
        XCTAssertEqual(open[physics.id]?.map(\.index), [0, 1], "an open notebook's pages are taken as they are, ahead of its file")
    }

    func testTheSmartShelfFileKeepsWhatItCannotRead() throws {
        let root = temporaryRoot(self)
        try FileManager.default.createDirectory(at: root.library, withIntermediateDirectories: true)
        let id = UUID()
        let json = """
        {"version": 2, "shelves": [
          {"id": "\(id.uuidString)", "name": "Revision", "tags": ["exam", "Lab"], "match": "all", "createdAt": "2026-10-01T09:00:00.000Z", "icon": "star"},
          {"name": "no id"},
          {"id": "\(UUID().uuidString)", "name": "Later", "tags": "exam", "match": "none"}
        ]}
        """
        try Data(json.utf8).write(to: root.smartShelvesFile)
        var file = SmartShelfFile.read(root)
        XCTAssertEqual(file.shelves.map(\.name), ["Revision", "Later"])
        XCTAssertEqual(file.shelves[0].id, id)
        XCTAssertEqual(file.shelves[0].rule, TagRule(tags: ["exam", "Lab"], match: .all))
        XCTAssertEqual(file.shelves[1].tags, [], "tags it can't read are no tags")
        XCTAssertEqual(file.shelves[1].match, .any, "and a way of matching it doesn't know is read as any")
        XCTAssertEqual(file.opaque.count, 1)

        file.shelves[0].name = "Finals"
        try file.write(root)
        let written = try JSONValue.parse(Data(contentsOf: root.smartShelvesFile))
        XCTAssertEqual(written["version"], .number(2), "a key beside the shelves is kept")
        let shelves = try XCTUnwrap(written["shelves"]?.arrayValue)
        XCTAssertEqual(shelves.count, 3)
        XCTAssertEqual(shelves[0]["name"], .string("Finals"))
        XCTAssertEqual(shelves[0]["icon"], .string("star"), "and so is one inside a shelf")
        XCTAssertEqual(shelves[1]["tags"], .string("exam"), "what couldn't be read is written back as it was")
        XCTAssertEqual(shelves[1]["match"], .string("none"))
        XCTAssertEqual(shelves[2], .object(["name": .string("no id")]))
        XCTAssertEqual(SmartShelfFile.read(root).shelves.first?.createdAt, file.shelves[0].createdAt)

        try Data("[1, 2]".utf8).write(to: root.smartShelvesFile)
        XCTAssertEqual(SmartShelfFile.read(root), SmartShelfFile(), "a file that isn't an object is set aside")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.smartShelvesFile.path(percentEncoded: false)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.smartShelvesFile.appendingPathExtension("corrupt").path(percentEncoded: false)))
    }

    func testSmartShelvesAreSavedAndReadBack() async throws {
        let store = try makeStore()
        XCTAssertNil(store.createSmartShelf(name: "Empty", tags: [" "], match: .any), "a shelf needs a tag to look for")
        let revision = try XCTUnwrap(store.createSmartShelf(name: " Revision ", tags: ["exam", "Exam", "lab"], match: .all))
        let unnamed = try XCTUnwrap(store.createSmartShelf(name: "", tags: ["week 3", "lab"], match: .any))
        XCTAssertEqual(revision.name, "Revision")
        XCTAssertEqual(revision.tags, ["exam", "lab"])
        XCTAssertEqual(unnamed.name, "lab, week 3", "left unnamed, a shelf is called after its tags")
        XCTAssertEqual(store.smartShelves.map(\.id), [revision.id, unnamed.id])

        store.updateSmartShelf(revision.id, name: "Finals", tags: ["exam"], match: .any)
        store.deleteSmartShelf(unnamed.id)
        XCTAssertEqual(store.smartShelves.map(\.name), ["Finals"])
        let saved = try await savedShelves(store) { $0.map(\.name) == ["Finals"] }
        XCTAssertEqual(saved.first?.rule, TagRule(tags: ["exam"]))
        XCTAssertEqual(saved.first?.id, revision.id)

        let container = try ModelContainer(for: LibraryIndex.schema, configurations: ModelConfiguration(schema: LibraryIndex.schema, isStoredInMemoryOnly: true))
        containers.append(container)
        let relaunched = LibraryStore(root: store.root, context: container.mainContext)
        XCTAssertEqual(relaunched.smartShelves, [])
        await relaunched.loadSmartShelves()
        XCTAssertEqual(relaunched.smartShelves.map(\.name), ["Finals"])
    }

    // MARK: Across the library

    func testRenamingATagReachesClosedAndOpenNotebooks() async throws {
        let store = try makeStore()
        let biology = try await makeNotebook("Biology", in: store, tags: ["exam", "term 1"], pageTags: [["exam"], ["lab"]])
        let physics = try await makeNotebook("Physics", in: store, tags: ["Finals"], pageTags: [["Exam", "lab"], []])
        let recipes = try await makeNotebook("Recipes", in: store, tags: ["home"])
        let shelf = try XCTUnwrap(store.createSmartShelf(name: "Revision", tags: ["exam", "lab"], match: .all))
        let document = try await DocumentRegistry.shared.open(physics.id, root: store.root, scene: nil) { _ in }
        addTeardownBlock { @MainActor in DocumentRegistry.shared.unregister(physics.id, document: document) }
        let untouched = try Data(contentsOf: NotebookPackage(root: store.root, id: recipes.id).manifestURL)

        XCTAssertNil(store.renameTag("exam", to: "  "), "an empty name is no rename, and never a removal")
        XCTAssertEqual(biology.tags, ["exam", "term 1"])

        XCTAssertEqual(store.renameTag("exam", to: "finals"), "Finals", "a name the library has is merged into, as it is spelled there")
        XCTAssertEqual(biology.tags, ["Finals", "term 1"], "the records are right at once")
        XCTAssertEqual(biology.pageTags, ["Finals", "lab"])
        XCTAssertEqual(physics.tags, ["Finals"])
        XCTAssertEqual(physics.pageTags, ["Finals", "lab"])
        XCTAssertEqual(store.tagCounts().map(\.name), ["Finals", "home", "lab", "term 1"])
        XCTAssertEqual(document.manifest.pages[0].tags, ["Finals", "lab"], "an open notebook is changed through its document")
        XCTAssertEqual(store.smartShelves.first?.tags, ["Finals", "lab"], "a smart shelf goes on looking for the tag under its new name")

        let closed = try await manifest(biology.id, in: store) { $0.library.tags == ["Finals", "term 1"] }
        XCTAssertEqual(closed.library.tags, ["Finals", "term 1"])
        XCTAssertEqual(closed.pages.map(\.tags), [["Finals"], ["lab"]])
        let flushed = await document.flush()
        XCTAssertTrue(flushed)
        let opened = try await NotebookPackage(root: store.root, id: physics.id).readManifest().manifest
        XCTAssertEqual(opened.pages.map(\.tags), [["Finals", "lab"], []])
        XCTAssertEqual(try Data(contentsOf: NotebookPackage(root: store.root, id: recipes.id).manifestURL), untouched, "a notebook without the tag isn't written")

        XCTAssertNil(store.renameTag("LAB", to: nil))
        XCTAssertEqual(biology.pageTags, ["Finals"])
        XCTAssertEqual(document.manifest.pages[0].tags, ["Finals"])
        XCTAssertEqual(store.tagCounts().map(\.name), ["Finals", "home", "term 1"])
        XCTAssertEqual(store.smartShelves.first?.tags, ["Finals"])
        let removed = try await manifest(biology.id, in: store) { $0.pages[1].tags.isEmpty }
        XCTAssertEqual(removed.pages.map(\.tags), [["Finals"], []])
        let shelves = try await savedShelves(store) { $0.first?.tags == ["Finals"] }
        XCTAssertEqual(shelves.map(\.id), [shelf.id])
        XCTAssertNil(store.lastError)
    }

    func testTaggingFromTheLibraryCanBeUndone() async throws {
        let store = try makeStore()
        let changes = LibraryChangeCenter()
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        let record = try await makeNotebook("Physics", in: store, tags: ["term 1"])

        undoManager.beginUndoGrouping()
        changes.setTags(["exam", "Term 1"], for: record, in: store, undoManager: undoManager)
        undoManager.endUndoGrouping()
        XCTAssertEqual(record.tags, ["exam", "Term 1"])
        XCTAssertEqual(changes.current?.message, "Changed the tags of “Physics”")
        var onDisk = try await manifest(record.id, in: store) { $0.library.tags.count == 2 }
        XCTAssertEqual(onDisk.library.tags, ["exam", "Term 1"])

        changes.current?.undo()
        XCTAssertEqual(record.tags, ["term 1"])
        XCTAssertNil(changes.current, "undoing takes the slip away")
        onDisk = try await manifest(record.id, in: store) { $0.library.tags == ["term 1"] }
        XCTAssertEqual(onDisk.library.tags, ["term 1"])
        undoManager.redo()
        XCTAssertEqual(record.tags, ["exam", "Term 1"])

        changes.dismiss()
        changes.setTags(["Term 1", "exam"], for: record, in: store, undoManager: undoManager)
        XCTAssertNil(changes.current, "the same tags again are no change")
    }

    func testABackupCarriesSmartShelves() async throws {
        let store = try makeStore()
        _ = try await makeNotebook("Biology", in: store, tags: ["exam"], pageTags: [["lab"]])
        let revision = try XCTUnwrap(store.createSmartShelf(name: "Revision", tags: ["exam"], match: .any))
        let labs = try XCTUnwrap(store.createSmartShelf(name: "Labs", tags: ["lab"], match: .any))
        let backup = try await store.makeBackup()
        addTeardownBlock { try? FileManager.default.removeItem(at: backup.deletingLastPathComponent()) }

        let fresh = try makeStore()
        let summary = try await fresh.restoreBackup(from: backup)
        XCTAssertEqual(summary.added, 1)
        XCTAssertEqual(summary.smartShelves, 2)
        XCTAssertEqual(fresh.smartShelves.map(\.id), [revision.id, labs.id])
        XCTAssertEqual(fresh.tagCounts().map(\.name), ["exam", "lab"], "the notebook comes back with its tags")

        store.updateSmartShelf(revision.id, name: "Finals", tags: ["exam", "lab"], match: .all)
        store.deleteSmartShelf(labs.id)
        let again = try await store.restoreBackup(from: backup)
        XCTAssertEqual(again.smartShelves, 1, "only the shelf the library no longer has is added")
        XCTAssertEqual(store.smartShelves.map(\.name), ["Finals", "Labs"], "and the one it has is never replaced")
        XCTAssertFalse(again.isEmpty)
    }
}
