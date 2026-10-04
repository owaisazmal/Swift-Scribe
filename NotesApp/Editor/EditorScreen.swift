import SwiftUI
import SwiftData

/// Where a link to another notebook was followed from, so the notebook it opened can offer the way back.
struct NotebookReturn: Equatable {
    let origin: UUID
    let page: UUID
    let title: String
    let destination: UUID
}

/// What the first pane's editor is closing for: to go back to the library, or only to close its tab.
enum EditorClosing { case library, tab }

/// What the editors of one window share with the library behind them.
@MainActor
@Observable
final class EditorWindow {
    static let tabLimit = 12

    var linkReturn: NotebookReturn?
    /// The notebook open beside the first one, in the same window.
    var beside: OpenNotebook?
    /// The notebook of the pane last touched. Keyboard shortcuts go to it.
    var active: UUID?
    /// Where the first pane ends, as a fraction of the window.
    var split: CGFloat = 0.5
    /// The notebooks open in tabs, in the order of the tab bar. A notebook on its own is one tab, and shows no bar.
    private(set) var tabs: [OpenNotebook] = []
    /// The tab on show in the first pane. If the first pane was the one being worked in, it still is.
    private(set) var selected: UUID? {
        didSet { if let active, active != beside?.id { self.active = selected } }
    }
    /// The editor on show has put its bars away (focus, presenting, find): the tab bar goes with them.
    var hidesChrome = false
    var pickingTab = false
    /// Set while everything is being saved on the way back to the library: tabs can't be changed meanwhile.
    var isLeaving = false
    @ObservationIgnored var closing = EditorClosing.library
    /// The documents of the tabs looked at since the editor opened. They stay open while another tab is on show, so
    /// a tab comes back with its undo history; all are saved and closed on the way back to the library.
    @ObservationIgnored private(set) var documents: [UUID: NotebookDocument] = [:]
    /// Shows another notebook, at a page if one is given: in a tab when there are tabs, and otherwise in place of
    /// the editor that is open, once that has saved and closed.
    @ObservationIgnored var openNotebook: ((UUID, UUID?) -> Void)?

    /// Shows a notebook in the first pane: in its own tab if it has one, in a new tab otherwise.
    func show(_ notebook: OpenNotebook) {
        if notebook.id != selected { leaveTab() }
        if let index = tabs.firstIndex(where: { $0.id == notebook.id }) {
            tabs[index].pageID = notebook.pageID
        } else {
            tabs.append(notebook)
            // Past the limit, the first tab that isn't open behind the bar makes room.
            if tabs.count > Self.tabLimit, let waiting = tabs.firstIndex(where: { $0.id != notebook.id && documents[$0.id] == nil }) {
                tabs.remove(at: waiting)
            }
        }
        selected = notebook.id
    }

    func select(_ id: UUID) {
        guard id != selected, tabs.contains(where: { $0.id == id }) else { return }
        leaveTab()
        selected = id
    }

    /// One tab along the bar, coming round at the ends.
    func step(_ delta: Int) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == selected }) else { return }
        select(tabs[(index + delta + tabs.count) % tabs.count].id)
    }

    /// A tab that is left comes back at the page it was left on, not the page it was first opened at.
    private func leaveTab() {
        if let index = tabs.firstIndex(where: { $0.id == selected }) { tabs[index].pageID = nil }
    }

    func keep(_ document: NotebookDocument) {
        documents[document.id] = document
    }

    /// Lets go of a document its own editor has closed, or hands it over to be closed.
    @discardableResult
    func release(_ id: UUID) -> NotebookDocument? {
        documents.removeValue(forKey: id)
    }

    /// Takes a tab off the bar. If it was the tab on show, the one that takes its place is shown.
    func removeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if selected == id { selected = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id }
    }

    /// Going back to the library: several tabs wait to be shown again, a notebook on its own doesn't.
    /// Returns the documents still open, to be saved and closed.
    func park() -> [NotebookDocument] {
        let open = Array(documents.values)
        documents = [:]
        if tabs.count < 2 {
            tabs = []
            selected = nil
        }
        for index in tabs.indices { tabs[index].pageID = nil }
        hidesChrome = false
        pickingTab = false
        isLeaving = false
        closing = .library
        return open
    }

    /// The tabs this window had when the app last ran.
    func restore(_ notebooks: [OpenNotebook]) {
        guard tabs.isEmpty, notebooks.count > 1 else { return }
        tabs = Array(notebooks.prefix(Self.tabLimit))
    }

    /// Lets go of the tabs of notebooks that have left the library. The tab on show stays: its editor says what happened.
    func keepTabs(where isPresent: (UUID) -> Bool) {
        let kept = tabs.filter { $0.id == selected || isPresent($0.id) }
        if kept.count != tabs.count { tabs = kept }
    }
}

/// Whether an editor has the window to itself or shares it.
enum EditorPaneRole { case single, primary, secondary }

extension EnvironmentValues {
    @Entry var editorPane = EditorPaneRole.single
}

/// The window's editor, or two side by side (one above the other when the window is taller than it is wide),
/// under a bar of tabs when several notebooks are open. Going back to the library from the first closes
/// everything; the second has its own Close, and each tab its own.
struct EditorPanes: View {
    let primary: OpenNotebook
    let sceneID: String?
    let onClose: () -> Void
    @Environment(EditorWindow.self) private var window
    @Environment(LibraryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var size = CGSize.zero
    @State private var dragOrigin: CGFloat?

    static let dividerWidth: CGFloat = 14
    /// `-splitSideBySide` lets a test see the narrow panes of a landscape window while the simulator stays upright.
    private var stacked: Bool { size.height > size.width && !LaunchOptions.arguments.contains("-splitSideBySide") }

    /// The tab on show; a notebook on its own is the one the library opened.
    private var current: OpenNotebook { window.tabs.first { $0.id == window.selected } ?? primary }

    private var showsTabs: Bool { window.tabs.count > 1 && !window.hidesChrome }

    var body: some View {
        @Bindable var window = window
        VStack(spacing: 0) {
            if showsTabs {
                TabStrip(select: { window.select($0) }, close: closeTab)
                    .disabled(window.isLeaving)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            panes
        }
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: showsTabs)
        .background(Color.desk.ignoresSafeArea())
        .sheet(isPresented: $window.pickingTab) {
            BesidePicker(current: current.id, title: "Open in a Tab", exclude: Set(window.tabs.map(\.id) + (window.beside.map { [$0.id] } ?? [])),
                         emptyMessage: "Every other notebook is already open.") { id in
                window.show(OpenNotebook(id: id))
                window.active = id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scribeSelectTab)) { note in
            guard let id = note.object as? UUID, id != window.beside?.id, !window.isLeaving else { return }
            window.select(id)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)) { note in
            guard (note.object as? UIScene)?.session.persistentIdentifier == sceneID else { return }
            let shown = current.id
            putAway(window.park().filter { $0.id != shown })
        }
    }

    private var panes: some View {
        let split = window.beside != nil && size != .zero
        let length = ((stacked ? size.height : size.width) - Self.dividerWidth) * window.split
        let current = current
        return (stacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))) {
            EditorScreen(notebookID: current.id, initialPageID: current.pageID, sceneID: sceneID, beforeClose: beforeClose) { closed(current.id) }
                .id(current.id)
                .environment(\.editorPane, window.beside == nil ? .single : .primary)
                .frame(width: split && !stacked ? length : nil, height: split && stacked ? length : nil)
            if let beside = window.beside {
                divider
                EditorScreen(notebookID: beside.id, initialPageID: beside.pageID, sceneID: sceneID) {
                    window.beside = nil
                    window.active = self.current.id
                }
                .id(beside.id)
                .environment(\.editorPane, .secondary)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
    }

    // MARK: Tabs

    /// The tab on show is closed by its own editor, which can say so if saving fails; one behind the bar is saved
    /// and closed here.
    private func closeTab(_ id: UUID) {
        guard window.tabs.count > 1, !window.isLeaving else { return }
        if id == current.id {
            window.closing = .tab
            NotificationCenter.default.post(name: .scribeCloseEditor, object: id)
        } else {
            window.removeTab(id)
            putAway(window.release(id).map { [$0] } ?? [])
        }
    }

    private func putAway(_ documents: [NotebookDocument]) {
        for document in documents { Task { await EditorScreen.putAway(document, store: store) } }
    }

    /// On the way back to the library the notebook beside this one and the tabs behind the bar are saved and closed first.
    private func beforeClose() async -> Bool {
        guard window.closing == .library else { return true }
        window.isLeaving = true
        guard await closeBeside() else {
            window.isLeaving = false
            return false
        }
        let shown = current.id
        for document in window.documents.values where document.id != shown {
            await EditorScreen.putAway(document, store: store)
            window.release(document.id)
        }
        return true
    }

    /// The editor on show has saved and closed: its tab goes, or the whole editor does.
    private func closed(_ id: UUID) {
        let closing = window.closing
        window.closing = .library
        window.release(id)
        if closing == .tab, window.tabs.count > 1 { return window.removeTab(id) }
        putAway(window.park())
        onClose()
    }

    private var divider: some View {
        Color.desk
            .frame(width: stacked ? nil : Self.dividerWidth, height: stacked ? Self.dividerWidth : nil)
            .overlay { Rectangle().fill(Color.hairline).frame(width: stacked ? nil : 1, height: stacked ? 1 : nil) }
            .overlay { Capsule().fill(Color.textSecondary).frame(width: stacked ? 40 : 5, height: stacked ? 5 : 40) }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { value in
                    let start = dragOrigin ?? window.split
                    dragOrigin = start
                    let total = max(stacked ? size.height : size.width, 1)
                    window.split = min(max(start + (stacked ? value.translation.height : value.translation.width) / total, 0.3), 0.7)
                }
                .onEnded { _ in dragOrigin = nil })
            .accessibilityHidden(true)
            // VoiceOver's handle is a full-size target laid over the strip; it takes no touches, so the panes' edges stay theirs.
            .overlay {
                Color.clear
                    .frame(minWidth: 44, minHeight: 44)
                    .allowsHitTesting(false)
                    .accessibilityElement()
                    .accessibilityLabel(Text("Divider between the notebooks"))
                    .accessibilityValue(Text(window.split, format: .percent.precision(.fractionLength(0))))
                    .accessibilityAdjustableAction { direction in
                        window.split = min(max(window.split + (direction == .increment ? 0.05 : -0.05), 0.3), 0.7)
                    }
                    .accessibilityIdentifier("editor.split.divider")
            }
    }

    /// The first notebook only closes once the one beside it has saved and closed.
    private func closeBeside() async -> Bool {
        guard let beside = window.beside else { return true }
        NotificationCenter.default.post(name: .scribeCloseEditor, object: beside.id)
        for _ in 0..<100 where window.beside != nil { try? await Task.sleep(for: .milliseconds(100)) }
        return window.beside == nil
    }
}

/// Chooses the notebook to open beside the one being written in, or in a tab.
struct BesidePicker: View {
    let current: UUID
    var title: LocalizedStringKey = "Open Beside"
    /// Notebooks that are already open in this window in some other way.
    var exclude: Set<UUID> = []
    var emptyMessage: LocalizedStringKey = "Once you have another notebook, you can open it beside this one."
    let pick: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<NotebookRecord> { $0.deletedAt == nil }, sort: \NotebookRecord.title) private var records: [NotebookRecord]

    var body: some View {
        // A notebook open in another window stays there: one editor writes each notebook.
        let others = records.filter {
            $0.id != current && !exclude.contains($0.id) && DocumentRegistry.shared.document(for: $0.id) == nil && !DocumentRegistry.shared.isOpening($0.id)
        }
        NavigationStack {
            List(others) { record in
                Button {
                    pick(record.id)
                    dismiss()
                } label: {
                    HStack(spacing: Space.x4) {
                        RecordCover(record: record, width: CoverWidth.row, showsShadow: false).frame(width: 40)
                        VStack(alignment: .leading, spacing: Space.x1) {
                            Text(record.title).font(.headline).foregroundStyle(Color.ink)
                            Text("\(record.pageCount) pages")
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                .listRowBackground(Color.surface)
                .accessibilityIdentifier("beside.notebook.\(record.title)")
            }
            .scrollContentBackground(.hidden)
            .background(Color.desk)
            .overlay {
                if others.isEmpty {
                    ContentUnavailableView {
                        Label("No Other Notebooks", systemImage: "books.vertical").foregroundStyle(Color.ink)
                    } description: {
                        Text(emptyMessage).foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .navigationTitle(title)
            .barGround(.desk)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.buttonStyle(.scribe(.secondary, inBar: true))
                }
                .boardBackground()
            }
        }
    }
}

/// Opens a notebook's document and hosts the editor. One per notebook across windows.
struct EditorScreen: View {
    let notebookID: UUID
    var initialPageID: UUID?
    let sceneID: String?
    /// Asked before closing; returning false leaves the editor open.
    var beforeClose: (() async -> Bool)?
    let onClose: () -> Void

    @Environment(LibraryStore.self) private var store
    @Environment(WritingActivity.self) private var activity
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.editorPane) private var pane
    @Environment(EditorWindow.self) private var window: EditorWindow?
    @State private var document: NotebookDocument?
    @State private var failure: String?
    @State private var isClosing = false
    @State private var unsavedReason: String?
    @State private var lock = NotebookLock.shared
    @State private var askedToUnlock = false

    /// A locked notebook is covered until it is unlocked, and whenever the app isn't in front, so it never shows in the app switcher.
    private func isCovered(_ document: NotebookDocument) -> Bool {
        document.manifest.library.isLocked && (!lock.isUnlocked(notebookID) || scenePhase != .active)
    }

    var body: some View {
        ZStack {
            Color.desk.ignoresSafeArea()
            if let document {
                let covered = isCovered(document)
                EditorView(document: document, initialPageID: initialPageID, isCovered: covered, close: close)
                    .id(document.id)
                    .disabled(covered)
                    .accessibilityHidden(covered)
                if covered {
                    LockedNotebookView(title: document.title, closeTitle: pane == .secondary ? "Close" : "Back to Library", unlock: { unlock(document) }) {
                        if pane != .secondary { window?.closing = .library }
                        close()
                    }
                        .task(id: scenePhase) {
                            guard scenePhase == .active, !askedToUnlock, !lock.isUnlocked(notebookID) else { return }
                            askedToUnlock = true
                            unlock(document)
                        }
                }
            } else if let failure {
                EmptyShelf(title: String(localized: "This notebook couldn't be opened"), message: failure) {
                    Button("Back to Library", action: onClose).buttonStyle(.scribe(.primary))
                }
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .task(id: notebookID) { await open() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            lock.lock(notebookID)
            askedToUnlock = false
        }
        .onDisappear { lock.lock(notebookID) }
        .onReceive(NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)) { note in
            guard (note.object as? UIScene)?.session.persistentIdentifier == sceneID else { return }
            closeWithWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .scribeCloseEditor)) { note in
            guard (note.object as? UUID) == notebookID else { return }
            guard let document else { return onClose() }
            document.recorder?.shutdown()
            close()
        }
        .alert("Your latest changes aren't saved yet", isPresented: Binding(get: { unsavedReason != nil },
                                                                            set: { if !$0 { unsavedReason = nil } })) {
            Button("Try Again") { close() }
            Button("Close Anyway", role: .destructive) { closeWhileSaving() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Swift Scribe couldn't write to this device: \(unsavedReason ?? ""). If you close now, it keeps trying in the background, but changes that haven't been saved are lost if the app quits first.")
        }
    }

    private func unlock(_ document: NotebookDocument) {
        Task { await lock.unlock(notebookID, title: document.title) }
    }

    private func open() async {
        do {
            let opened = try await DocumentRegistry.shared.open(notebookID, root: store.root, scene: sceneID) { [weak store, weak activity] document in
                let id = document.id
                document.onSaved = { manifest in store?.index(manifest) }
                document.onInkSaved = { pages, date in activity?.record(notebook: id, pages: pages, at: date) }
                store?.reapplyChangesInFlight(to: document)
            }
            opened.noteOpened()
            document = opened
            if pane != .secondary { window?.keep(opened) }
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Waits for imports, then saves. The editor only goes away once everything is on disk, or the user
    /// chooses to close while saving keeps failing.
    private func close() {
        guard let document, !isClosing else { return }
        isClosing = true
        Task {
            if let beforeClose, !(await beforeClose()) {
                isClosing = false
                return
            }
            await document.finishPendingWork()
            guard await document.flush() else {
                isClosing = false
                if pane != .secondary { window?.isLeaving = false }
                unsavedReason = document.saveFailureReason ?? String(localized: "the save didn't finish")
                return
            }
            await document.collectGarbage()
            store.index(document.manifest)
            DocumentRegistry.shared.unregister(notebookID, document: document)
            onClose()
            store.indexHandwriting(package: document.package, pages: document.pages)
        }
    }

    /// The window went away with the editor still open: no UI to ask with, so save, and keep retrying if that fails.
    private func closeWithWindow() {
        guard let document, !isClosing else { return }
        isClosing = true
        Task { await Self.putAway(document, store: store) }
    }

    /// Saves and closes a document without an editor to ask with: a tab behind the bar, or a window that went away.
    /// One that can't be saved is kept, and retried, until it can.
    static func putAway(_ document: NotebookDocument, store: LibraryStore) async {
        document.recorder?.shutdown()
        await document.finishPendingWork()
        if await document.flush() {
            await document.collectGarbage()
            store.index(document.manifest)
            store.indexHandwriting(package: document.package, pages: document.pages)
            DocumentRegistry.shared.unregister(document.id, document: document)
        } else {
            DocumentRegistry.shared.keepUntilSaved(document) { [weak store] in
                store?.index(document.manifest)
                store?.indexHandwriting(package: document.package, pages: document.pages)
                Task { await document.collectGarbage() }
            }
        }
    }

    private func closeWhileSaving() {
        guard let document else { return onClose() }
        DocumentRegistry.shared.keepUntilSaved(document) { [weak store] in
            store?.index(document.manifest)
            store?.indexHandwriting(package: document.package, pages: document.pages)
            Task { await document.collectGarbage() }
        }
        onClose()
    }
}
