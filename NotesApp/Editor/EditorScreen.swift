import SwiftUI

/// Opens a notebook's document and hosts the editor. One per notebook across windows.
struct EditorScreen: View {
    let notebookID: UUID
    var initialPageID: UUID?
    let sceneID: String?
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
