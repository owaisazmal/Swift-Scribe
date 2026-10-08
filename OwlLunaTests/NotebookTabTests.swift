import XCTest
@testable import OwlLuna

/// The tabs of one window: which notebooks are open, which is on show, and what is kept between visits to the library.
@MainActor
final class NotebookTabTests: XCTestCase {
    private func makeDocument() -> NotebookDocument {
        let root = StorageRoot(url: FileManager.default.temporaryDirectory.appending(path: "tab-tests-\(UUID().uuidString)", directoryHint: .isDirectory))
        let defaults = PageDefaults(template: .blank, paperColor: .white, pageSize: .letter)
        let manifest = NotebookManifest(title: "Tab", defaults: defaults, pages: [defaults.newPage()])
        return NotebookDocument(package: NotebookPackage(root: root, id: manifest.id), load: ManifestLoad(manifest: manifest))
    }

    func testANotebookIsShownInItsOwnTabOrANewOne() {
        let window = EditorWindow()
        let first = UUID(), second = UUID(), page = UUID()
        window.show(OpenNotebook(id: first, pageID: page))
        XCTAssertEqual(window.tabs.map(\.id), [first])
        XCTAssertEqual(window.selected, first)
        window.show(OpenNotebook(id: second))
        XCTAssertEqual(window.tabs.map(\.id), [first, second], "a new tab goes at the end of the bar")
        XCTAssertEqual(window.selected, second)
        XCTAssertNil(window.tabs[0].pageID, "a tab that is left comes back where it was left, not where it was first opened")

        let other = UUID()
        window.show(OpenNotebook(id: first, pageID: other))
        XCTAssertEqual(window.tabs.map(\.id), [first, second], "shown again, a notebook keeps its tab")
        XCTAssertEqual(window.selected, first)
        XCTAssertEqual(window.tabs[0].pageID, other, "and opens at the page that was asked for")
        window.show(OpenNotebook(id: first, pageID: page))
        XCTAssertEqual(window.tabs[0].pageID, page)
    }

    func testSteppingAlongTheBarComesRoundAtTheEnds() {
        let window = EditorWindow()
        let ids = [UUID(), UUID(), UUID()]
        ids.forEach { window.show(OpenNotebook(id: $0)) }
        window.step(1)
        XCTAssertEqual(window.selected, ids[0])
        window.step(-1)
        XCTAssertEqual(window.selected, ids[2])
        window.step(-1)
        XCTAssertEqual(window.selected, ids[1])
        window.select(UUID())
        XCTAssertEqual(window.selected, ids[1], "only a tab can be selected")
    }

    func testClosingTheTabOnShowShowsTheOneThatTakesItsPlace() {
        let window = EditorWindow()
        let ids = [UUID(), UUID(), UUID()]
        ids.forEach { window.show(OpenNotebook(id: $0)) }
        window.select(ids[1])
        window.removeTab(ids[1])
        XCTAssertEqual(window.selected, ids[2], "the tab that moved into its place")
        window.removeTab(ids[2])
        XCTAssertEqual(window.selected, ids[0], "or the one before it, at the end of the bar")
        window.show(OpenNotebook(id: ids[1]))
        window.removeTab(ids[0])
        XCTAssertEqual(window.selected, ids[1], "closing a tab behind the bar leaves the one on show alone")
        XCTAssertEqual(window.tabs.map(\.id), [ids[1]])
    }

    func testATabMovesAlongTheBarAndTheOneOnShowStaysOnShow() {
        let window = EditorWindow()
        let ids = [UUID(), UUID(), UUID(), UUID()]
        ids.forEach { window.show(OpenNotebook(id: $0)) }
        window.select(ids[1])
        XCTAssertTrue(window.moveTab(ids[0], to: 2))
        XCTAssertEqual(window.tabs.map(\.id), [ids[1], ids[2], ids[0], ids[3]], "dropped on a later tab, it lands after it")
        XCTAssertTrue(window.moveTab(ids[3], to: 0))
        XCTAssertEqual(window.tabs.map(\.id), [ids[3], ids[1], ids[2], ids[0]], "and on an earlier one, before it")
        XCTAssertEqual(window.selected, ids[1], "the tab on show stays on show")
        XCTAssertTrue(window.moveTab(ids[1], to: 3))
        XCTAssertEqual(window.selected, ids[1], "wherever it is moved to")
        XCTAssertFalse(window.moveTab(ids[1], to: 3), "a tab dropped where it stands hasn't moved")
        XCTAssertFalse(window.moveTab(ids[1], to: 4), "and there is nowhere past the end of the bar")
        XCTAssertFalse(window.moveTab(UUID(), to: 0), "only a tab can be moved")
        XCTAssertEqual(window.tabs.map(\.id), [ids[3], ids[2], ids[0], ids[1]])
    }

    func testOnlyATabsDocumentIsKept() {
        let window = EditorWindow()
        let first = makeDocument(), second = makeDocument()
        window.show(OpenNotebook(id: first.id))
        window.show(OpenNotebook(id: second.id))
        window.keep(first)
        window.keep(second)
        window.removeTab(second.id)
        XCTAssertEqual(window.selected, first.id)
        XCTAssertTrue(window.release(second.id) === second, "a tab moved beside leaves its document to be handed on, undo history and all")
        window.keep(second)
        XCTAssertEqual(Array(window.documents.keys), [first.id], "a document that opens after its tab has gone isn't kept")
    }

    func testSeveralTabsWaitInTheLibraryAndANotebookOnItsOwnDoesNot() {
        let window = EditorWindow()
        let alone = makeDocument()
        window.show(OpenNotebook(id: alone.id))
        window.keep(alone)
        window.hidesChrome = true
        window.isLeaving = true
        XCTAssertEqual(window.park().map(\.id), [alone.id], "what is still open is handed back to be saved and closed")
        XCTAssertTrue(window.tabs.isEmpty)
        XCTAssertNil(window.selected)
        XCTAssertFalse(window.hidesChrome)
        XCTAssertFalse(window.isLeaving)

        let first = makeDocument(), second = makeDocument()
        window.show(OpenNotebook(id: first.id))
        window.keep(first)
        window.show(OpenNotebook(id: second.id, pageID: UUID()))
        window.keep(second)
        XCTAssertNotNil(window.release(first.id))
        XCTAssertEqual(window.park().map(\.id), [second.id])
        XCTAssertEqual(window.tabs.map(\.id), [first.id, second.id], "two tabs are still there when a notebook is next opened")
        XCTAssertTrue(window.tabs.allSatisfy { $0.pageID == nil })
        XCTAssertTrue(window.documents.isEmpty)

        let third = UUID()
        window.show(OpenNotebook(id: third))
        XCTAssertEqual(window.tabs.map(\.id), [first.id, second.id, third], "and it joins them")
    }

    func testPastTheLimitATabThatIsNotOpenMakesRoom() {
        let window = EditorWindow()
        let live = makeDocument()
        window.show(OpenNotebook(id: live.id))
        window.keep(live)
        let waiting = (1..<EditorWindow.tabLimit).map { _ in UUID() }
        waiting.forEach { window.show(OpenNotebook(id: $0)) }
        XCTAssertEqual(window.tabs.count, EditorWindow.tabLimit)
        let extra = UUID()
        window.show(OpenNotebook(id: extra))
        XCTAssertEqual(window.tabs.count, EditorWindow.tabLimit)
        XCTAssertEqual(window.tabs.first?.id, live.id, "a tab with its notebook open is never the one to go")
        XCTAssertFalse(window.tabs.contains { $0.id == waiting[0] })
        XCTAssertEqual(window.selected, extra)
    }

    func testTabsAreBroughtBackAndLostNotebooksLetGo() {
        let window = EditorWindow()
        let ids = [UUID(), UUID(), UUID()]
        window.restore([OpenNotebook(id: ids[0])])
        XCTAssertTrue(window.tabs.isEmpty, "one notebook isn't a set of tabs")
        window.restore(ids.map { OpenNotebook(id: $0) })
        XCTAssertEqual(window.tabs.map(\.id), ids)
        XCTAssertNil(window.selected, "nothing is on show until a notebook is opened")
        window.show(OpenNotebook(id: ids[1]))
        window.keepTabs { $0 == ids[0] }
        XCTAssertEqual(window.tabs.map(\.id), [ids[0], ids[1]], "the tab on show stays even if its notebook is gone: its editor says so")
        window.restore([OpenNotebook(id: UUID()), OpenNotebook(id: UUID())])
        XCTAssertEqual(window.tabs.map(\.id), [ids[0], ids[1]], "tabs already there are never replaced")
    }

    func testAWindowRemembersItsTabs() {
        let scene = "test-\(UUID().uuidString)"
        let shown = UUID(), beside = UUID(), tabs = [UUID(), shown, UUID()]
        WindowMemory.remember(shown, beside: beside, tabs: tabs, in: scene)
        let kept = WindowMemory.remembered(in: scene)
        XCTAssertEqual(kept?.notebook, shown)
        XCTAssertEqual(kept?.beside, beside)
        XCTAssertEqual(kept?.tabs, tabs)

        WindowMemory.remember(nil, beside: nil, tabs: tabs, in: scene)
        XCTAssertNil(WindowMemory.remembered(in: scene)?.notebook, "back in the library, nothing is on show")
        XCTAssertEqual(WindowMemory.remembered(in: scene)?.tabs, tabs, "but the tabs are still waiting")

        WindowMemory.remember(shown, beside: nil, in: scene)
        XCTAssertEqual(WindowMemory.remembered(in: scene)?.tabs, [], "a notebook on its own has none")
        WindowMemory.keep(only: [])
        XCTAssertNil(WindowMemory.remembered(in: scene))
    }
}
