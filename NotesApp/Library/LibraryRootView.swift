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
    @State private var isSearching = false
    @State private var changes = LibraryChangeCenter()
    @State private var openingToday = false
    @State private var triedRestore = false
    @State private var performingAction = false
    @SceneStorage("scribe.openNotebook") private var restoredNotebook = ""
    @Namespace private var zoom

    /// With Reduce Motion the editor cross-fades in over the library instead of zooming out of the cover.
    private var usesZoom: Bool { !reduceMotion }

    private var folder: FolderRecord? {
        if case .folder(let id) = scope { return folders.first { $0.id == id } }
        return nil
    }

    var body: some View {
        ZStack {
            NavigationSplitView {
                LibrarySidebar(scope: $scope, showingSettings: $showingSettings)
            } detail: {
                NavigationStack {
                    ShelfView(scope: scope ?? .all, zoomNamespace: zoom, onOpen: { openNotebook($0.id) },
                              onOpenPage: { openNotebook($0.id, pageID: $1) },
                              onOpenZoomed: { openNotebook($0.id, pageID: $1, zoomSource: $2) }, onCreate: { creating = true },
                              onQuickNote: quickNote, isSearching: $isSearching, isCovered: open != nil || creating || showingSettings)
                }
            }
            .tint(Color.accentColor)
            .environment(changes)
            .accessibilityHidden(editorCoversLibrary)
            .disabled(editorCoversLibrary)

            if !usesZoom, let open {
                EditorScreen(notebookID: open.id, initialPageID: open.pageID, sceneID: sceneID) { self.open = nil }
                    .id(open.id)
                    .accessibilityAddTraits(.isModal)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: open)
        .fullScreenCover(item: Binding(get: { usesZoom ? open : nil }, set: { open = $0 })) { item in
            EditorScreen(notebookID: item.id, initialPageID: item.pageID, sceneID: sceneID) { open = nil }
                .zoomTransition(id: item.zoomSource, in: zoom)
        }
        .sheet(isPresented: $creating) {
            NewNotebookView(folder: folder) { id in
                openNotebook(id)
            }
        }
        .sheet(isPresented: $showingSettings) {
            ScribeSettingsView()
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
            }
        }
        .onChange(of: open) { restoredNotebook = $1?.id.uuidString ?? "" }
        .task(id: app.phase) {
            await restoreOpenNotebook()
            takePendingAction()
        }
        .onChange(of: app.pendingAction) { takePendingAction() }
        .onOpenURL { url in
            if let action = AppAction(url: url) { Task { await perform(action) } }
        }
    }

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
            case .open(let notebook):
                guard let record = store.record(notebook), !record.isTrashed else { return }
                id = notebook
            }
            if let current = open, current.id != id {
                NotificationCenter.default.post(name: .scribeCloseEditor, object: current.id)
                for _ in 0..<100 where open != nil { try? await Task.sleep(for: .milliseconds(100)) }
                guard open == nil else { return }
                try? await Task.sleep(for: .milliseconds(500))
            }
            if open?.id == id {
                if let page { NotificationCenter.default.post(name: .scribeShowPage, object: id, userInfo: ["page": page]) }
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

    /// Skipped once if the last restore crashed.
    private func restoreOpenNotebook() async {
        guard app.phase == .ready, open == nil, !triedRestore else { return }
        triedRestore = true
        let defaults = UserDefaults.standard, flag = "scribe.restoreInFlight"
        if defaults.bool(forKey: flag) {
            defaults.removeObject(forKey: flag)
            restoredNotebook = ""
            return
        }
        guard let id = UUID(uuidString: restoredNotebook), let record = store.record(id), !record.isTrashed else { return }
        defaults.set(true, forKey: flag)
        openNotebook(id)
        try? await Task.sleep(for: .seconds(3))
        defaults.removeObject(forKey: flag)
    }

    /// Library shortcuts only act when nothing else is in front of the library.
    private var libraryInFront: Bool {
        open == nil && !creating && !showingSettings && !creatingQuickNote && app.phase == .ready
    }

    private func quickNote() {
        guard libraryInFront else { return }
        creatingQuickNote = true
        Task {
            defer { creatingQuickNote = false }
            do {
                openNotebook(try await store.createQuickNote(folder: folder))
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
        if DocumentRegistry.shared.activateExistingEditor(for: id, from: sceneID) {
            if let pageID { NotificationCenter.default.post(name: .scribeShowPage, object: id, userInfo: ["page": pageID]) }
            return
        }
        open = OpenNotebook(id: id, pageID: pageID, zoomSource: zoomSource)
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
    static let scribeShowPage = Notification.Name("ScribeShowPage")
}
