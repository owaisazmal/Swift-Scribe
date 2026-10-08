import UIKit

/// One editor per notebook across all windows. The registry knows which scene has a notebook open,
/// so a second open brings that window forward instead of creating a competing editor.
@MainActor
final class DocumentRegistry {
    static let shared = DocumentRegistry()

    private struct Entry {
        weak var document: NotebookDocument?
        var sceneIdentifier: String?
    }

    private var entries: [UUID: Entry] = [:]
    private var opening: [UUID: (task: Task<NotebookDocument, Error>, scene: String?)] = [:]
    private var closing: [UUID: NotebookDocument] = [:]

    /// The live document for a notebook: open in an editor, or closed with changes still waiting to be saved.
    func document(for id: UUID) -> NotebookDocument? {
        if let document = entries[id]?.document { return document }
        entries[id] = nil
        return closing[id]
    }

    func isOpening(_ id: UUID) -> Bool { opening[id] != nil }

    func sceneIdentifier(for id: UUID) -> String? {
        if entries[id]?.document != nil { return entries[id]?.sceneIdentifier }
        return opening[id]?.scene
    }

    /// Returns the notebook's document, reusing one that's open, still opening or still saving,
    /// so two windows never write the same package through different documents.
    func open(_ id: UUID, root: StorageRoot, scene: String?,
              configure: @escaping @MainActor (NotebookDocument) -> Void) async throws -> NotebookDocument {
        if let document = entries[id]?.document { return document }
        if let document = closing.removeValue(forKey: id) {
            entries[id] = Entry(document: document, sceneIdentifier: scene)
            return document
        }
        if let pending = opening[id] { return try await pending.task.value }
        let task = Task { () throws -> NotebookDocument in
            defer { self.opening[id] = nil }
            let document = try await NotebookDocument.open(id, root: root)
            configure(document)
            self.entries[id] = Entry(document: document, sceneIdentifier: scene)
            return document
        }
        opening[id] = (task, scene)
        return try await task.value
    }

    func register(_ document: NotebookDocument, scene: String?) {
        entries[document.id] = Entry(document: document, sceneIdentifier: scene)
    }

    func unregister(_ id: UUID, document: NotebookDocument) {
        if entries[id]?.document === document { entries[id] = nil }
    }

    /// Keeps a closed document whose changes couldn't be saved alive and retrying, so nothing is dropped;
    /// opening the notebook again picks the same document back up.
    func keepUntilSaved(_ document: NotebookDocument, retryEvery interval: Duration = .seconds(15),
                        onSaved: @escaping @MainActor () -> Void) {
        let id = document.id
        unregister(id, document: document)
        closing[id] = document
        Task {
            while closing[id] === document, !(await document.flush(attempts: 1)) {
                try? await Task.sleep(for: interval)
            }
            guard closing[id] === document else { return }
            closing[id] = nil
            onSaved()
        }
    }

    /// The window that has `id` open, when it isn't this one and is still there.
    func otherWindow(with id: UUID, than scene: String?) -> UISceneSession? {
        guard let owner = sceneIdentifier(for: id), owner != scene else { return nil }
        return UIApplication.shared.openSessions.first { $0.persistentIdentifier == owner }
    }

    /// If `id` is open in another window, brings that window to the front with the notebook on show, at the page if one is given, and returns true.
    func activateExistingEditor(for id: UUID, page: UUID? = nil, from scene: String?) -> Bool {
        guard let session = otherWindow(with: id, than: scene) else { return false }
        UIApplication.shared.requestSceneSessionActivation(session, userActivity: nil, options: nil, errorHandler: nil)
        NotificationCenter.default.post(name: .owlLunaSelectTab, object: id)
        if let page { NotificationCenter.default.post(name: .owlLunaShowPage, object: id, userInfo: ["page": page]) }
        return true
    }

    var openDocuments: [NotebookDocument] { entries.values.compactMap(\.document) + closing.values }
}
