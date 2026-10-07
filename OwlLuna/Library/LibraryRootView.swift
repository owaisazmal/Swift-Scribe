import SwiftUI
import SwiftData

struct OpenNotebook: Identifiable, Hashable {
    let id: UUID
    var pageID: UUID?
    /// What the editor zooms out of and back into: the cover unless the open started somewhere else.
    var zoomSource: String

    init(id: UUID, pageID: UUID? = nil, zoomSource: String? = nil) {
        self.id = id
        self.pageID = pageID
        self.zoomSource = zoomSource ?? "cover-\(id.uuidString)"
    }
}

struct LibraryRootView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \FolderRecord.sortIndex) private var folders: [FolderRecord]
    @State private var scope: LibraryScope? = .all
    @State private var open: OpenNotebook?
    @State private var showingSettings = false
    @State private var creating = false
    @State private var quickNoteError: String?
    @State private var creatingQuickNote = false
    @Environment(AppModel.self) private var app
    @State private var sceneID: String?
    @State private var changes = LibraryChangeCenter()
    @State private var openingToday = false
    @State private var triedRestore = false
    @State private var performingAction = false
    @State private var window = EditorWindow()
    @SceneStorage("owlluna.openNotebook") private var restoredNotebook = ""
    @SceneStorage("owlluna.besideNotebook") private var restoredBeside = ""
    @Namespace private var zoom
    @State private var sidebar = SidebarControl()
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var rootWidth: CGFloat = 0
    @State private var detailWidth: CGFloat = 0

    /// With Reduce Motion the editor cross-fades in over the library instead of zooming out of the cover.
    private var usesZoom: Bool { !reduceMotion }

    private var folder: FolderRecord? {
        if case .folder(let id) = scope { return folders.first { $0.id == id } }
        return nil
    }

    var body: some View {
        ZStack {
            NavigationSplitView {
                LibrarySidebar(scope: $scope, showingSettings: $showingSettings, hideSidebar: hidesSidebar ? { sidebar.toggle() } : nil)
            } detail: {
                NavigationStack {
                    ShelfView(scope: scope ?? .all, zoomNamespace: zoom, onOpen: { openNotebook($0.id) },
                              onOpenPage: { openNotebook($0.id, pageID: $1) },
                              onOpenZoomed: { openNotebook($0.id, pageID: $1, zoomSource: $2) }, onCreate: { creating = true },
                              onQuickNote: quickNote, onWhiteboard: newWhiteboard, isCovered: open != nil || creating || showingSettings)
                        .modifier(BoardSidebarToggle(shows: sizeClass == .regular && !sidebarBeside, title: "Show Sidebar",
                                                     placement: .topBarLeading) { sidebar.toggle() })
                }
                .background(SidebarAnchor(control: sidebar))
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { detailWidth = $0 }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rootWidth = $0 }
            .tint(Color.accentColor)
            .environment(changes)
            .accessibilityHidden(editorCoversLibrary)
            .disabled(editorCoversLibrary)

            if !usesZoom, let open {
                EditorPanes(primary: open, sceneID: sceneID) { self.open = nil }
                    .environment(window)
                    .id(open.id)
                    .accessibilityAddTraits(.isModal)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: open)
        .fullScreenCover(item: Binding(get: { usesZoom ? open : nil }, set: { open = $0 })) { item in
            EditorPanes(primary: item, sceneID: sceneID) { open = nil }
                .environment(window)
                .zoomTransition(id: item.zoomSource, in: zoom)
                // A sideways finger drag on the page would otherwise pull the editor shut without its save-and-close.
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $creating) {
            NewNotebookView(folder: folder) { id in
                openNotebook(id)
            }
        }
        .sheet(isPresented: $showingSettings) {
            OwlLunaSettingsView()
        }
        .alert("The note couldn't be created", isPresented: Binding(get: { quickNoteError != nil }, set: { if !$0 { quickNoteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(quickNoteError ?? "")
        }
        .background(SceneReader { sceneID = $0 })
        .keyboardShortcut(for: { creating = true }, enabled: libraryInFront)
        .background {
            if libraryInFront {
                Button("Quick Note", action: quickNote)
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .hidden()
                    .accessibilityHidden(true)
                Button("Today's Page", action: openToday)
                    .keyboardShortcut("t", modifiers: .command)
                    .hidden()
                    .accessibilityHidden(true)
                if #available(iOS 26, *), sizeClass == .regular {
                    Button(sidebarBeside ? "Hide Sidebar" : "Show Sidebar") { sidebar.toggle() }
                        .keyboardShortcut("s", modifiers: [.command, .control])
                        .hidden()
                        .accessibilityHidden(true)
                }
            }
        }
        .onChange(of: open) {
            if $1 == nil {
                window.beside = nil
                window.active = nil
            }
            rememberWindow()
        }
        .onChange(of: window.selected) { rememberWindow() }
        .onChange(of: window.tabs.map(\.id)) { rememberWindow() }
        .onChange(of: window.beside?.id) {
            restoredBeside = open == nil ? "" : $1?.uuidString ?? ""
            rememberWindow()
        }
        .onChange(of: sceneID) { Task { await restoreOpenNotebook() } }
        .onAppear { window.openNotebook = { id, page in Task { await perform(.open(id, page: page)) } } }
        .task(id: app.phase) {
            await restoreOpenNotebook()
            takePendingAction()
        }
        .onChange(of: app.pendingAction) { takePendingAction() }
        .onOpenURL { url in
            if let action = AppAction(url: url) { Task { await perform(action) } }
        }
    }

    /// The notebook on show in the editor's first pane: the tab on show, when there are tabs.
    private var shownID: UUID? { open == nil ? nil : window.selected ?? open?.id }

    /// Before iPadOS 26 the system's own button does this.
    private var hidesSidebar: Bool {
        if #available(iOS 26, *) { sizeClass == .regular } else { false }
    }

    /// The sidebar stands beside the shelves only when they are narrower than the window.
    private var sidebarBeside: Bool { rootWidth - detailWidth > 1 }

    private func takePendingAction() {
        guard app.phase == .ready, let action = app.pendingAction else { return }
        app.pendingAction = nil
        Task { await perform(action) }
    }

    /// Carries out a widget link or shortcut from wherever this window is: sheets are put away, and an editor
    /// showing another notebook saves and closes first.
    private func perform(_ action: AppAction) async {
        await app.start()
        guard !performingAction else { return }
        performingAction = true
        defer { performingAction = false }
        if creating || showingSettings {
            creating = false
            showingSettings = false
            try? await Task.sleep(for: .milliseconds(600))
        }
        do {
            let id: UUID
            var page: UUID?
            switch action {
            case .today:
                if let journal = store.dailyJournal { id = journal.id } else { id = try await store.createDailyJournal() }
                page = await store.prepareTodayPage(id)
            case .quickNote:
                id = try await store.createQuickNote(folder: nil)
            case .continueWriting:
                guard let last = store.lastOpenedNotebook else { return }
                id = last.id
            case .open(let notebook, let linked):
                guard let record = store.record(notebook), !record.isTrashed else { return }
                id = notebook
                page = linked
            }
            if let current = shownID, current != id, window.beside?.id != id {
                // With tabs open the notebook gets a tab; a notebook on its own makes way for it.
                if window.tabs.count > 1 { return window.show(OpenNotebook(id: id, pageID: page)) }
                window.closing = .library
                NotificationCenter.default.post(name: .owlLunaCloseEditor, object: current)
                for _ in 0..<100 where open != nil { try? await Task.sleep(for: .milliseconds(100)) }
                guard open == nil else { return }
                try? await Task.sleep(for: .milliseconds(500))
            }
            if open != nil {
                if window.beside?.id == id { window.active = id }
                if let page { NotificationCenter.default.post(name: .owlLunaShowPage, object: id, userInfo: ["page": page]) }
            } else {
                openNotebook(id, pageID: page)
            }
        } catch {
            quickNoteError = error.localizedDescription
        }
    }

    /// ⌘T, starting a journal first if there isn't one.
    private func openToday() {
        guard libraryInFront, !openingToday else { return }
        openingToday = true
        Task {
            defer { openingToday = false }
            do {
                var id = store.dailyJournal?.id
                if id == nil { id = try await store.createDailyJournal() }
                guard let id else { return }
                let page = await store.prepareTodayPage(id)
                openNotebook(id, pageID: page, zoomSource: scope == .all ? "today-\(id.uuidString)" : nil)
            } catch {
                quickNoteError = error.localizedDescription
            }
        }
    }

    private func rememberWindow() {
        restoredNotebook = shownID?.uuidString ?? ""
        guard let sceneID else { return }
        WindowMemory.remember(shownID, beside: window.beside?.id, tabs: window.tabs.count > 1 ? window.tabs.map(\.id) : [], in: sceneID)
    }

    /// Skipped once if the last restore crashed.
    private func restoreOpenNotebook() async {
        guard app.phase == .ready, open == nil, !triedRestore, let sceneID else { return }
        triedRestore = true
        WindowMemory.keep(only: Set(UIApplication.shared.openSessions.map(\.persistentIdentifier)))
        let defaults = UserDefaults.standard, flag = "owlluna.restoreInFlight"
        if defaults.bool(forKey: flag) {
            defaults.removeObject(forKey: flag)
            restoredNotebook = ""
            WindowMemory.remember(nil, beside: nil, in: sceneID)
            return
        }
        let remembered = WindowMemory.remembered(in: sceneID) ?? (UUID(uuidString: restoredNotebook), UUID(uuidString: restoredBeside), [])
        window.restore(remembered.tabs.filter { store.record($0).map { !$0.isTrashed } ?? false }.map { OpenNotebook(id: $0) })
        guard let id = remembered.notebook, let record = store.record(id), !record.isTrashed else { return }
        let beside = remembered.beside.flatMap(store.record)
        defaults.set(true, forKey: flag)
        openNotebook(id)
        if let beside, beside.id != id, !beside.isTrashed, open?.id == id { window.beside = OpenNotebook(id: beside.id) }
        try? await Task.sleep(for: .seconds(3))
        defaults.removeObject(forKey: flag)
    }

    /// Library shortcuts only act when nothing else is in front of the library.
    private var libraryInFront: Bool {
        open == nil && !creating && !showingSettings && !creatingQuickNote && app.phase == .ready
    }

    private func quickNote() { createAndOpen { try await store.createQuickNote(folder: folder) } }

    private func newWhiteboard() { createAndOpen { try await store.createWhiteboard(folder: folder) } }

    private func createAndOpen(_ create: @escaping () async throws -> UUID) {
        guard libraryInFront else { return }
        creatingQuickNote = true
        Task {
            defer { creatingQuickNote = false }
            do {
                openNotebook(try await create())
            } catch {
                quickNoteError = error.localizedDescription
            }
        }
    }

    /// Without the zoom transition the editor is drawn over the library, which then must not be reachable.
    private var editorCoversLibrary: Bool { !usesZoom && open != nil }

    /// Only one editor per window: while one is open, the library can't switch it to another notebook.
    private func openNotebook(_ id: UUID, pageID: UUID? = nil, zoomSource: String? = nil) {
        guard open == nil else { return }
        if window.linkReturn?.destination != id { window.linkReturn = nil }
        if DocumentRegistry.shared.activateExistingEditor(for: id, from: sceneID) {
            NotificationCenter.default.post(name: .owlLunaSelectTab, object: id)
            if let pageID { NotificationCenter.default.post(name: .owlLunaShowPage, object: id, userInfo: ["page": pageID]) }
            return
        }
        let notebook = OpenNotebook(id: id, pageID: pageID, zoomSource: zoomSource)
        // A locked notebook asks before it opens; the editor asks again if it is reached some other way.
        guard let record = store.record(id), record.isLocked, !NotebookLock.shared.isUnlocked(id), NotebookLock.shared.isAvailable else {
            return show(notebook)
        }
        let title = record.title.isEmpty ? String(localized: "Untitled") : record.title
        Task {
            guard await NotebookLock.shared.unlock(id, title: title), open == nil else { return }
            show(notebook)
        }
    }

    /// Opens the editor on a notebook. Tabs left open the last time take it in among them.
    private func show(_ notebook: OpenNotebook) {
        window.show(notebook)
        open = notebook
    }
}

extension View {
    func zoomTransition(id: String, in namespace: Namespace.ID) -> some View {
        navigationTransition(.zoom(sourceID: id, in: namespace))
    }

    /// ⌘N: new notebook, from anywhere in the library. Off while an editor is open, which has its own ⌘N.
    func keyboardShortcut(for newNotebook: @escaping () -> Void, enabled: Bool) -> some View {
        background {
            if enabled {
                Button("New Notebook", action: newNotebook)
                    .keyboardShortcut("n", modifiers: .command)
                    .hidden()
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Reports the window scene's persistent identifier, which keys the one-editor-per-notebook rule.
/// What each window has open, kept the moment it changes. iPadOS saves a window's own state only on the way to
/// the background, so an app stopped straight after would otherwise reopen with what was open before.
enum WindowMemory {
    private static let key = "owlluna.windowNotebooks"

    private static var all: [String: [String]] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// The notebook on show, the one beside it, then the tabs in their order when there are several.
    static func remember(_ notebook: UUID?, beside: UUID?, tabs: [UUID] = [], in scene: String) {
        all[scene] = [notebook?.uuidString ?? "", notebook == nil ? "" : beside?.uuidString ?? ""] + tabs.map(\.uuidString)
    }

    /// Nil when the window has nothing kept here yet; a notebook of nil when it had none open.
    static func remembered(in scene: String) -> (notebook: UUID?, beside: UUID?, tabs: [UUID])? {
        all[scene].map { kept in
            (UUID(uuidString: kept.first ?? ""), UUID(uuidString: kept.dropFirst().first ?? ""), kept.dropFirst(2).compactMap(UUID.init(uuidString:)))
        }
    }

    /// Lets go of windows iPadOS no longer keeps.
    static func keep(only scenes: Set<String>) {
        let kept = all.filter { scenes.contains($0.key) }
        if kept.count != all.count { all = kept }
    }
}

struct SceneReader: UIViewRepresentable {
    let onChange: (String?) -> Void

    func makeUIView(context: Context) -> SceneReaderView {
        let view = SceneReaderView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: SceneReaderView, context: Context) {}

    final class SceneReaderView: UIView {
        var onChange: ((String?) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onChange?(window?.windowScene?.session.persistentIdentifier)
        }
    }
}

extension Notification.Name {
    /// Asks the editor showing a notebook (object: its ID) to go to a page (userInfo "page": the page ID).
    static let owlLunaShowPage = Notification.Name("OwlLunaShowPage")
}

/// Shows and hides the sidebar the way the system's button does: over the shelves in portrait, beside them in landscape.
@MainActor
final class SidebarControl {
    weak var anchor: UIView?

    func toggle() {
        var responder: UIResponder? = anchor
        while let current = responder, !(current is UISplitViewController) { responder = current.next }
        guard let split = responder as? UISplitViewController, !split.isCollapsed else { return }
        if split.displayMode == .secondaryOnly { split.show(.primary) } else { split.hide(.primary) }
    }
}

private struct SidebarAnchor: UIViewRepresentable {
    let control: SidebarControl

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        control.anchor = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) { control.anchor = view }
}

/// On iPadOS 26 and later the system's sidebar button is a glass bubble; this puts a board one in its place.
private struct BoardSidebarToggle: ViewModifier {
    let shows: Bool
    let title: LocalizedStringKey
    let placement: ToolbarItemPlacement
    let action: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .toolbar(removing: .sidebarToggle)
                .toolbar {
                    if shows {
                        ToolbarItem(placement: placement) {
                            Button(action: action) { Label(title, systemImage: "sidebar.leading") }
                                .buttonStyle(.boardIcon)
                                .accessibilityIdentifier("ToggleSidebar")
                        }
                        .boardBackground()
                    }
                }
        } else {
            content
        }
    }
}
