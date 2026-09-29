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

    func document(for id: UUID) -> NotebookDocument? {
        guard let document = entries[id]?.document else {
            entries[id] = nil
            return nil
        }
        return document
    }

    func sceneIdentifier(for id: UUID) -> String? {
        document(for: id) == nil ? nil : entries[id]?.sceneIdentifier
    }

    func register(_ document: NotebookDocument, scene: String?) {
        entries[document.id] = Entry(document: document, sceneIdentifier: scene)
    }

    func unregister(_ id: UUID, document: NotebookDocument) {
        if entries[id]?.document === document { entries[id] = nil }
    }

    /// If `id` is open in another window, brings that window to the front and returns true.
    func activateExistingEditor(for id: UUID, from scene: String?) -> Bool {
        guard let owner = sceneIdentifier(for: id), owner != scene else { return false }
        guard let session = UIApplication.shared.openSessions.first(where: { $0.persistentIdentifier == owner }) else { return false }
        UIApplication.shared.requestSceneSessionActivation(session, userActivity: nil, options: nil, errorHandler: nil)
        return true
    }

    var openDocuments: [NotebookDocument] { entries.values.compactMap(\.document) }
}
