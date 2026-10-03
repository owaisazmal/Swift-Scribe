import XCTest
import SwiftData
import CoreSpotlight
@testable import NotesApp

/// What Spotlight is told about the library, and what a Control Center button hands the app.
@MainActor
final class SystemReachTests: XCTestCase {
    private var container: ModelContainer?
    private let paper = PageDefaults(template: .narrowRuled, paperColor: .white, pageSize: .letter)

    private func makeStore() throws -> LibraryStore {
        let schema = LibraryIndex.schema
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        self.container = container
        return LibraryStore(root: temporaryRoot(self), context: container.mainContext)
    }

    private func makeNotebook(_ title: String, in store: LibraryStore) async throws -> NotebookRecord {
        let manifest = NotebookManifest(title: title, defaults: paper, pages: [paper.newPage(), paper.newPage()])
        try await NotebookPackage(root: store.root, id: manifest.id).create(manifest)
        store.index(manifest)
        return try XCTUnwrap(store.record(manifest.id))
    }

    func testLockedAndDeletedNotebooksAreNeverOfferedToSpotlight() async throws {
        let store = try makeStore()
        let biology = try await makeNotebook("Biology", in: store)
        let diary = try await makeNotebook("Diary", in: store)
        let old = try await makeNotebook("Old notes", in: store)
        _ = try await makeNotebook("", in: store)
        store.setLocked(true, for: [diary])
        store.moveToTrash([old])
        let entries = SpotlightIndexer.entries(store.notebooks() + [old])
        XCTAssertEqual(Set(entries.map(\.title)), ["Biology", "Untitled"])
        XCTAssertEqual(entries.first { $0.id == biology.id }?.pageCount, 2)
    }

    func testOnlyWhatChangedIsIndexedAgain() {
        let biology = SpotlightEntry(id: UUID(), title: "Biology", pageCount: 3, modifiedAt: Date(timeIntervalSince1970: 1000))
        let physics = SpotlightEntry(id: UUID(), title: "Physics", pageCount: 1, modifiedAt: Date(timeIntervalSince1970: 2000))
        let known = [biology.id.uuidString: biology.signature(textBytes: 40), "GONE": "x|1|1||0"]

        XCTAssertEqual(SpotlightIndexer.candidates([biology, physics], known: known, changed: [], everything: false), [physics], "a notebook Spotlight hasn't seen")
        XCTAssertEqual(SpotlightIndexer.candidates([biology, physics], known: known, changed: [biology.id], everything: false), [biology, physics],
                       "and one whose words were just read again")
        XCTAssertEqual(SpotlightIndexer.candidates([biology], known: known, changed: [], everything: true), [biology], "everything is checked once after launch")
        var renamed = biology
        renamed = SpotlightEntry(id: biology.id, title: "Cell Biology", pageCount: 3, modifiedAt: biology.modifiedAt)
        XCTAssertEqual(SpotlightIndexer.candidates([renamed], known: known, changed: [], everything: false), [renamed])
        XCTAssertEqual(SpotlightIndexer.removals([biology, physics], known: known), ["GONE"], "what the library no longer offers is taken out")
        XCTAssertNotEqual(biology.signature(textBytes: 40), biology.signature(textBytes: 41))
    }

    func testAnItemCarriesTheTitleAndTheWords() {
        let entry = SpotlightEntry(id: UUID(), title: "Biology", pageCount: 12, modifiedAt: .now)
        let attributes = SpotlightIndexer.attributes(for: entry, text: String(repeating: "mitochondria ", count: 5000), thumbnail: Data([1, 2, 3]))
        XCTAssertEqual(attributes.title, "Biology")
        XCTAssertEqual(attributes.contentDescription, "Notebook, 12 pages")
        XCTAssertEqual(attributes.textContent?.count, SpotlightIndexer.textLimit, "a long notebook is cut short")
        XCTAssertEqual(attributes.thumbnailData, Data([1, 2, 3]))
        XCTAssertEqual(SpotlightIndexer.attributes(for: SpotlightEntry(id: UUID(), title: "One", pageCount: 1, modifiedAt: .now), text: "", thumbnail: nil).contentDescription,
                       "Notebook, 1 page")
    }

    func testASpotlightResultOpensItsNotebook() {
        let id = UUID()
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: id.uuidString]
        XCTAssertEqual(AppAction(spotlight: activity), .open(id))
        activity.userInfo = [CSSearchableItemActivityIdentifier: "not-an-id"]
        XCTAssertNil(AppAction(spotlight: activity))
        XCTAssertNil(AppAction(spotlight: NSUserActivity(activityType: "com.example.other")))
    }

    func testAControlsRequestIsCarriedOutOnce() throws {
        let suite = "scribe-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(ControlRelay.take(from: defaults))
        ControlRelay.post("quicknote", to: defaults)
        ControlRelay.post("today", to: defaults)
        XCTAssertEqual(ControlRelay.take(from: defaults), "today", "the last button pressed wins")
        XCTAssertNil(ControlRelay.take(from: defaults), "and is taken once")
        for (name, action) in [("quicknote", AppAction.quickNote), ("today", .today)] {
            XCTAssertEqual(AppAction(url: try XCTUnwrap(URL(string: "\(AppAction.scheme)://\(name)"))), action)
        }
    }
}
