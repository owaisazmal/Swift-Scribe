import SwiftUI
import SwiftData
import PencilKit

/// Where a link to another notebook was followed from, so the notebook it opened can offer the way back.
struct NotebookReturn: Equatable {
    let origin: UUID
    let page: UUID
    let title: String
    let destination: UUID
}

/// What the editors of one window share with the library behind them.
@MainActor
@Observable
final class EditorWindow {
    var linkReturn: NotebookReturn?
    /// The notebook open beside the first one, in the same window.
    var beside: OpenNotebook?
    /// The notebook of the pane last touched. Keyboard shortcuts go to it.
    var active: UUID?
    /// Where the first pane ends, as a fraction of the window.
    var split: CGFloat = 0.5
    /// One tool picker for both panes, so a tool chosen in one is the tool in the other.
    @ObservationIgnored var toolPicker: PKToolPicker?
    /// Saves and closes the editor that is open, then opens another notebook, at a page if one is given.
    @ObservationIgnored var openNotebook: ((UUID, UUID?) -> Void)?
}

/// Whether an editor has the window to itself or shares it.
enum EditorPaneRole { case single, primary, secondary }

extension EnvironmentValues {
    @Entry var editorPane = EditorPaneRole.single
}

/// The window's editor, or two side by side (one above the other when the window is taller than it is wide).
/// Closing the first closes both; the second has its own Close.
struct EditorPanes: View {
    let primary: OpenNotebook
    let sceneID: String?
    let onClose: () -> Void
    @Environment(EditorWindow.self) private var window
    @State private var size = CGSize.zero
    @State private var dragOrigin: CGFloat?

    static let dividerWidth: CGFloat = 14
    /// `-splitSideBySide` lets a test see the narrow panes of a landscape window while the simulator stays upright.
    private var stacked: Bool { size.height > size.width && !LaunchOptions.arguments.contains("-splitSideBySide") }

    var body: some View {
        let split = window.beside != nil && size != .zero
        let length = ((stacked ? size.height : size.width) - Self.dividerWidth) * window.split
        (stacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))) {
            EditorScreen(notebookID: primary.id, initialPageID: primary.pageID, sceneID: sceneID, beforeClose: closeBeside, onClose: onClose)
                .environment(\.editorPane, window.beside == nil ? .single : .primary)
                .frame(width: split && !stacked ? length : nil, height: split && stacked ? length : nil)
            if let beside = window.beside {
                divider
                EditorScreen(notebookID: beside.id, initialPageID: beside.pageID, sceneID: sceneID) {
                    window.beside = nil
                    window.active = primary.id
                }
                .id(beside.id)
                .environment(\.editorPane, .secondary)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .background(Color.desk.ignoresSafeArea())
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
            .accessibilityElement()
            .accessibilityLabel(Text("Divider between the notebooks"))
            .accessibilityValue(Text(window.split, format: .percent.precision(.fractionLength(0))))
            .accessibilityAdjustableAction { direction in
                window.split = min(max(window.split + (direction == .increment ? 0.05 : -0.05), 0.3), 0.7)
            }
            .accessibilityIdentifier("editor.split.divider")
    }

    /// The first notebook only closes once the one beside it has saved and closed.
    private func closeBeside() async -> Bool {
        guard let beside = window.beside else { return true }
        NotificationCenter.default.post(name: .scribeCloseEditor, object: beside.id)
        for _ in 0..<100 where window.beside != nil { try? await Task.sleep(for: .milliseconds(100)) }
        return window.beside == nil
    }
}

/// Chooses the notebook to open beside the one being written in.
struct BesidePicker: View {
    let current: UUID
    let pick: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<NotebookRecord> { $0.deletedAt == nil }, sort: \NotebookRecord.title) private var records: [NotebookRecord]

    var body: some View {
        // A notebook open in another window stays there: one editor writes each notebook.
        let others = records.filter { $0.id != current && DocumentRegistry.shared.document(for: $0.id) == nil && !DocumentRegistry.shared.isOpening($0.id) }
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
                            Text(record.pageCount == 1 ? String(localized: "1 page") : String(localized: "\(record.pageCount) pages"))
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
                        Text("Once you have another notebook, you can open it beside this one.").foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .navigationTitle("Open Beside")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
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
    @State private var document: NotebookDocument?
    @State private var failure: String?
    @State private var isClosing = false
    @State private var unsavedReason: String?

    var body: some View {
        ZStack {
            Color.desk.ignoresSafeArea()
            if let document {
                EditorView(document: document, initialPageID: initialPageID, close: close)
                    .id(document.id)
            } else if let failure {
                EmptyShelf(title: String(localized: "This notebook couldn't be opened"), message: failure) {
                    Button("Back to Library", action: onClose).prominentButton()
                }
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .task(id: notebookID) { await open() }
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
        document.recorder?.shutdown()
        Task {
            await document.finishPendingWork()
            if await document.flush() {
                await document.collectGarbage()
                store.index(document.manifest)
                store.indexHandwriting(package: document.package, pages: document.pages)
                DocumentRegistry.shared.unregister(notebookID, document: document)
            } else {
                closeWhileSaving()
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
