import SwiftUI

/// Opens a notebook's document and hosts the editor. One per notebook across windows.
struct EditorScreen: View {
    let notebookID: UUID
    let sceneID: String?
    let onClose: () -> Void

    @Environment(LibraryStore.self) private var store
    @State private var document: NotebookDocument?
    @State private var failure: String?

    var body: some View {
        ZStack {
            Color.desk.ignoresSafeArea()
            if let document {
                EditorView(document: document, close: close)
            } else if let failure {
                EmptyShelf(title: String(localized: "This notebook couldn't be opened"), message: failure) {
                    Button("Back to Library", action: onClose).buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .task(id: notebookID) { await open() }
    }

    private func open() async {
        if let existing = DocumentRegistry.shared.document(for: notebookID) {
            document = existing
            return
        }
        do {
            let opened = try await NotebookDocument.open(notebookID, root: store.root)
            opened.onSaved = { [weak store] manifest in store?.index(manifest) }
            DocumentRegistry.shared.register(opened, scene: sceneID)
            document = opened
        } catch {
            failure = error.localizedDescription
        }
    }

    private func close() {
        guard let document else { return onClose() }
        Task {
            await document.flush()
            await document.collectGarbage()
            store.index(document.manifest)
            DocumentRegistry.shared.unregister(notebookID, document: document)
            onClose()
            let job = HandwritingIndexer.Job(package: document.package, pages: document.pages)
            let text = await HandwritingIndexer.shared.index(job)
            store.updateSearchText(text, for: document.id)
        }
    }
}
