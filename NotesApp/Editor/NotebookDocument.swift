import Foundation
import PencilKit
import Observation
import os

/// Tells the canvas layer when the model replaced a page's ink (undo, redo, duplicate), so a live canvas can show it.
@MainActor
protocol InkObserver: AnyObject {
    func document(_ document: NotebookDocument, didReplaceInkOf pageID: UUID)
}

/// Undo registrations whose target is not the document are dropped, so PencilKit's own per-canvas undo
/// never lands on the shared stack and nothing on the stack points at a canvas that may be recycled.
final class DocumentUndoManager: UndoManager {
    private(set) var droppedRegistrations = 0

    override func registerUndo(withTarget target: Any, selector: Selector, object anObject: Any?) {
        guard target is NotebookDocument else { droppedRegistrations += 1; return }
        super.registerUndo(withTarget: target, selector: selector, object: anObject)
    }

    override func __registerUndoWithTarget(_ target: Any, handler undoHandler: @escaping @MainActor (Any) -> Void) {
        guard target is NotebookDocument else { droppedRegistrations += 1; return }
        super.__registerUndoWithTarget(target, handler: undoHandler)
    }

    override func prepare(withInvocationTarget target: Any) -> Any {
        guard target is NotebookDocument else {
            droppedRegistrations += 1
            discarded.removeAllActions()
            if discarded.groupingLevel == 0 { discarded.beginUndoGrouping() }
            return discarded.prepare(withInvocationTarget: target)
        }
        return super.prepare(withInvocationTarget: target)
    }

    private lazy var discarded: UndoManager = {
        let manager = UndoManager()
        manager.levelsOfUndo = 1
        return manager
    }()
}

struct DocumentNotice: Identifiable, Hashable, Sendable {
    enum Kind: Sendable { case quarantined, recovered, readOnly, unreadablePages, saveFailed }
    let id = UUID()
    let kind: Kind
    let message: String
}

enum SaveState: Equatable, Sendable {
    case saved
    case pending
    case saving
    case failed(String, retryIn: Duration)
}

@MainActor
@Observable
final class NotebookDocument {
    let id: UUID
    let package: NotebookPackage
    private(set) var manifest: NotebookManifest
    private(set) var saveState: SaveState = .saved
    private(set) var notices: [DocumentNotice] = []
    private(set) var damagedPages: Set<UUID> = []
    let isReadOnly: Bool

    @ObservationIgnored let undoManager = DocumentUndoManager()
    @ObservationIgnored weak var inkObserver: InkObserver?
    /// Called after any change to the page list or a page's appearance, including undo and redo.
    @ObservationIgnored var onStructureChange: (() -> Void)?
    /// Called after a save that changed what the library shows while the notebook is open (title, pages,
    /// cover, favourite, trash, folder). Ink-only saves skip it; closing the editor indexes everything.
    @ObservationIgnored var onSaved: ((NotebookManifest) -> Void)?
    @ObservationIgnored var retryBase: Duration = .seconds(1)
    @ObservationIgnored var saveDelay: Duration = .seconds(1.2)
    /// However often edits push the debounce back, a pending save starts within this long.
    @ObservationIgnored var maxSaveLatency: Duration = .seconds(5)

    @ObservationIgnored private var inks: [UUID: Ink] = [:]
    @ObservationIgnored private var loading: [UUID: Load] = [:]
    @ObservationIgnored private var recentlyUsed: [UUID] = []
    @ObservationIgnored private var pinned: Set<UUID> = []
    @ObservationIgnored private var editedSinceOpen: Set<UUID> = []
    @ObservationIgnored private var inkModifiedAt: Date?
    @ObservationIgnored private var manifestVersion = 0
    @ObservationIgnored private var savedManifestVersion = 0
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var pendingDeadline: ContinuousClock.Instant?
    @ObservationIgnored private var pendingSince: ContinuousClock.Instant?
    @ObservationIgnored private var activeSave: Task<Bool, Never>?
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var indexedSignature: IndexSignature
    @ObservationIgnored private var pendingWork: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let signposter = OSSignposter(subsystem: "com.owais.NotesApp", category: "document")

    /// How many clean, loaded pages are kept in memory before the least recently used are released.
    /// Pages with a live canvas and pages with unsaved ink are never released.
    @ObservationIgnored var inkCacheLimit = 24

    private struct Ink {
        var drawing: PKDrawing
        var version = 0
        var savedVersion = 0
        var isDirty: Bool { version != savedVersion }
    }

    private struct Load {
        let token: UUID
        let task: Task<PKDrawing?, Never>
        var isRequired: Bool
    }

    /// The manifest fields the library shows while the notebook is open.
    private struct IndexSignature: Equatable {
        let title: String
        let pageCount: Int
        let cover: CoverSpec
        let isFavorite: Bool
        let deletedAt: Date?
        let folderID: UUID?
        let firstPage: String?

        init(_ manifest: NotebookManifest) {
            title = manifest.title
            pageCount = manifest.pages.count
            cover = manifest.cover
            isFavorite = manifest.library.isFavorite
            deletedAt = manifest.library.deletedAt
            folderID = manifest.library.folderID
            firstPage = manifest.pages.first.map { "\($0.id.uuidString)-\($0.appearanceKey)" }
        }
    }

    init(package: NotebookPackage, load: ManifestLoad) {
        id = package.id
        self.package = package
        manifest = load.manifest
        isReadOnly = load.isReadOnly
        indexedSignature = IndexSignature(load.manifest)
        undoManager.levelsOfUndo = 200
        if manifest.pages.isEmpty, !isReadOnly {
            manifest.pages = [manifest.defaults.newPage()]
            manifestVersion += 1
        }
        if load.needsSave, !isReadOnly { manifestVersion += 1 }
        for file in load.quarantined {
            notices.append(DocumentNotice(kind: .quarantined, message: "A damaged file (\(file)) was set aside and kept. The notebook opened from its last good copy."))
        }
        if !load.recoveredPageIDs.isEmpty {
            notices.append(DocumentNotice(kind: .recovered, message: "Recovered \(load.recoveredPageIDs.count) page(s) written just before the app last quit. They're at the end."))
        }
        if !manifest.opaquePages.isEmpty {
            notices.append(DocumentNotice(kind: .unreadablePages, message: "\(manifest.opaquePages.count) page(s) were made by a newer version of Swift Scribe and are hidden here. They're kept unchanged."))
        }
        if isReadOnly {
            notices.append(DocumentNotice(kind: .readOnly, message: "This notebook was saved by a newer version of Swift Scribe, so it opens read-only."))
        }
        if manifestVersion != savedManifestVersion { scheduleSave(after: .zero) }
    }

    static func open(_ id: UUID, root: StorageRoot) async throws -> NotebookDocument {
        let package = NotebookPackage(root: root, id: id)
        let load = try await package.readManifest()
        return NotebookDocument(package: package, load: load)
    }

    var pages: [NotebookPage] { manifest.pages }
    var title: String { manifest.title }

    /// Ink left behind by a removed page doesn't count: it's kept in memory for redo and saved if the page comes back.
    var hasUnsavedChanges: Bool {
        manifestVersion != savedManifestVersion || inkModifiedAt != nil
            || inks.contains { $0.value.isDirty && index(of: $0.key) != nil }
    }

    var saveFailureReason: String? {
        if case .failed(let reason, _) = saveState { return reason }
        return nil
    }

    func index(of pageID: UUID) -> Int? { manifest.pages.firstIndex { $0.id == pageID } }

    // MARK: Ink

    func hasUnsavedInk(_ pageID: UUID) -> Bool { inks[pageID]?.isDirty ?? false }

    /// The page's ink if it's in memory.
    func loadedInk(_ pageID: UUID) -> PKDrawing? {
        inks[pageID]?.drawing
    }

    /// Loads a page's ink off the main thread. Damaged files are quarantined and the page starts empty.
    func ink(_ pageID: UUID) async -> PKDrawing {
        while true {
            if let ink = inks[pageID] {
                touch(pageID)
                return ink.drawing
            }
            var load = loading[pageID] ?? startLoad(pageID, required: true)
            if !load.isRequired {
                load.isRequired = true
                loading[pageID] = load
            }
            if let drawing = await load.task.value { return drawing }
        }
    }

    /// Loads pages near the viewport ahead of time and drops queued prefetches the viewport has moved away from.
    /// A load someone is waiting for is never cancelled.
    func prefetchInk(_ ids: [UUID]) {
        let wanted = Set(ids)
        for (pageID, load) in loading where !load.isRequired && !wanted.contains(pageID) {
            load.task.cancel()
            loading[pageID] = nil
        }
        for pageID in ids where inks[pageID] == nil && loading[pageID] == nil {
            _ = startLoad(pageID, required: false)
        }
    }

    /// Pages with a live canvas. Their ink stays in memory so a stroke's undo always has the page it replaced.
    func pinInk(_ ids: Set<UUID>) {
        pinned = ids
    }

    private func startLoad(_ pageID: UUID, required: Bool) -> Load {
        let token = UUID()
        let package = package
        let task = Task(priority: required ? .userInitiated : .utility) { [weak self] () -> PKDrawing? in
            let result = await package.readInk(pageID)
            return self?.finishLoading(pageID, token: token, result)
        }
        let load = Load(token: token, task: task, isRequired: required)
        loading[pageID] = load
        return load
    }

    private func finishLoading(_ pageID: UUID, token: UUID, _ result: InkLoad) -> PKDrawing? {
        if loading[pageID]?.token == token { loading[pageID] = nil }
        if let existing = inks[pageID] { return existing.drawing }
        var drawing = PKDrawing()
        switch result {
        case .cancelled:
            return nil
        case .empty:
            break
        case .ink(let loaded, let hash):
            drawing = loaded
            if let index = index(of: pageID), manifest.pages[index].inkHash != hash {
                manifest.pages[index].inkHash = hash
                manifestVersion += 1
                scheduleSave()
            }
        case .quarantined(let file):
            damagedPages.insert(pageID)
            let number = index(of: pageID).map { " \($0 + 1)" } ?? ""
            notices.append(DocumentNotice(kind: .quarantined, message: "The ink on page\(number) couldn't be read. The original file was kept as \(file), and the page starts empty."))
            if let index = index(of: pageID) {
                manifest.pages[index].inkHash = nil
                manifestVersion += 1
            }
        }
        inks[pageID] = Ink(drawing: drawing)
        touch(pageID)
        return drawing
    }

    private func touch(_ pageID: UUID) {
        if let position = recentlyUsed.lastIndex(of: pageID) { recentlyUsed.remove(at: position) }
        recentlyUsed.append(pageID)
        guard recentlyUsed.count > inkCacheLimit else { return }
        for candidate in recentlyUsed.prefix(recentlyUsed.count - inkCacheLimit)
        where inks[candidate]?.isDirty == false && !pinned.contains(candidate) {
            inks[candidate] = nil
            recentlyUsed.removeAll { $0 == candidate }
        }
    }

    /// The stroke-end path: record the new drawing, register undo against the document, debounce a save.
    func canvasDidChangeInk(_ pageID: UUID, to drawing: PKDrawing) {
        guard !isReadOnly else { return }
        let before = inks[pageID]?.drawing
        setInk(pageID, drawing)
        if let before { registerInkUndo(pageID, restoring: before, then: drawing) }
        inkChanged()
        if editedSinceOpen.insert(pageID).inserted {
            Task.detached(priority: .utility) { await HandwritingIndexer.shared.cancel(page: pageID) }
        }
    }

    private func setInk(_ pageID: UUID, _ drawing: PKDrawing) {
        var ink = inks[pageID] ?? Ink(drawing: drawing)
        ink.drawing = drawing
        ink.version &+= 1
        inks[pageID] = ink
        touch(pageID)
    }

    /// Ink edits date the notebook when they're saved, without touching the observed manifest on every stroke.
    private func inkChanged() {
        inkModifiedAt = .now
        scheduleSave()
    }

    private func registerInkUndo(_ pageID: UUID, restoring before: PKDrawing, then after: PKDrawing) {
        undoManager.registerUndo(withTarget: self) { document in
            document.replaceInk(pageID, with: before)
            document.registerInkUndo(pageID, restoring: after, then: before)
        }
        undoManager.setActionName(String(localized: "Ink"))
    }

    /// Replaces a page's ink from the model side and tells a live canvas to show it.
    func replaceInk(_ pageID: UUID, with drawing: PKDrawing) {
        setInk(pageID, drawing)
        inkObserver?.document(self, didReplaceInkOf: pageID)
        inkChanged()
    }

    // MARK: Pages

    func insertPages(_ newPages: [NotebookPage], at index: Int, ink: [UUID: PKDrawing] = [:], actionName: String = String(localized: "Add Page")) {
        guard !isReadOnly, !newPages.isEmpty else { return }
        let position = min(max(index, 0), manifest.pages.count)
        for (pageID, drawing) in ink { setInk(pageID, drawing) }
        manifest.pages.insert(contentsOf: newPages, at: position)
        structureChanged()
        let ids = newPages.map(\.id)
        undoManager.registerUndo(withTarget: self) { document in
            document.removePages(ids, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    func removePages(_ ids: [UUID], actionName: String = String(localized: "Delete Page")) {
        guard !isReadOnly else { return }
        let removed = manifest.pages.enumerated().filter { ids.contains($0.element.id) }.map { (offset: $0.offset, page: $0.element) }
        guard !removed.isEmpty else { return }
        let placeholder = removed.count == manifest.pages.count ? manifest.defaults.newPage() : nil
        applyRemoval(removed, placeholder: placeholder, actionName: actionName)
    }

    /// Removing every page leaves one blank page. Redo re-applies exactly the same change, same placeholder
    /// included, so later redo steps still find the pages they refer to.
    private func applyRemoval(_ removed: [(offset: Int, page: NotebookPage)], placeholder: NotebookPage?, actionName: String) {
        let ids = Set(removed.map(\.page.id))
        manifest.pages.removeAll { ids.contains($0.id) }
        if let placeholder, manifest.pages.isEmpty { manifest.pages = [placeholder] }
        structureChanged()
        undoManager.registerUndo(withTarget: self) { document in
            document.undoRemoval(removed, placeholder: placeholder, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    private func undoRemoval(_ removed: [(offset: Int, page: NotebookPage)], placeholder: NotebookPage?, actionName: String) {
        if let placeholder { manifest.pages.removeAll { $0.id == placeholder.id } }
        for (offset, page) in removed {
            manifest.pages.insert(page, at: min(offset, manifest.pages.count))
        }
        structureChanged()
        undoManager.registerUndo(withTarget: self) { document in
            document.applyRemoval(removed, placeholder: placeholder, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    func movePage(from source: Int, to destination: Int) {
        guard !isReadOnly, manifest.pages.indices.contains(source), manifest.pages.indices.contains(destination), source != destination else { return }
        let page = manifest.pages.remove(at: source)
        manifest.pages.insert(page, at: destination)
        structureChanged()
        undoManager.registerUndo(withTarget: self) { $0.movePage(from: destination, to: source) }
        undoManager.setActionName(String(localized: "Move Page"))
    }

    func duplicatePage(at index: Int) async {
        guard !isReadOnly, manifest.pages.indices.contains(index) else { return }
        let original = manifest.pages[index]
        let drawing = await ink(original.id)
        guard let position = self.index(of: original.id) else { return }
        var copy = original.duplicated()
        copy.inkHash = nil
        insertPages([copy], at: position + 1, ink: drawing.strokes.isEmpty ? [:] : [copy.id: drawing], actionName: String(localized: "Duplicate Page"))
    }

    func setTemplate(_ template: PaperTemplate, forPage pageID: UUID) {
        guard let index = index(of: pageID), manifest.pages[index].template != nil, manifest.pages[index].template != template else { return }
        updatePage(pageID, actionName: String(localized: "Change Template")) { $0.background = .template(template) }
    }

    func setPaperColor(_ color: PaperColor, forPage pageID: UUID) {
        guard let index = index(of: pageID), manifest.pages[index].paperColor != color else { return }
        updatePage(pageID, actionName: String(localized: "Change Paper Colour")) { $0.paperColor = color }
    }

    private func updatePage(_ pageID: UUID, actionName: String, _ change: (inout NotebookPage) -> Void) {
        guard !isReadOnly, let index = index(of: pageID) else { return }
        let before = manifest.pages[index]
        change(&manifest.pages[index])
        structureChanged()
        registerPageRestore(before, actionName: actionName)
    }

    private func registerPageRestore(_ page: NotebookPage, actionName: String) {
        undoManager.registerUndo(withTarget: self) { document in
            guard let index = document.index(of: page.id) else {
                document.registerPageRestore(page, actionName: actionName)
                return
            }
            let current = document.manifest.pages[index]
            document.manifest.pages[index] = page
            document.structureChanged()
            document.registerPageRestore(current, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    // MARK: Notebook

    func rename(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isReadOnly, !trimmed.isEmpty, trimmed != manifest.title else { return }
        manifest.title = trimmed
        structureChanged()
    }

    func updateCover(_ cover: CoverSpec) {
        guard !isReadOnly, cover != manifest.cover else { return }
        manifest.cover = cover
        structureChanged()
    }

    /// Records the open in the manifest, so the library's Last Opened order survives the next index.
    func noteOpened() {
        guard !isReadOnly else { return }
        manifest.library.lastOpenedAt = .now
        manifestVersion += 1
        scheduleSave(after: .seconds(5), coalesce: true)
    }

    func noteCurrentPage(_ index: Int) {
        guard !isReadOnly, manifest.library.currentPage != index else { return }
        manifest.library.currentPage = index
        manifest.library.lastOpenedAt = .now
        manifestVersion += 1
        scheduleSave(after: .seconds(5), coalesce: true)
    }

    func addRecording(_ recording: RecordingEntry) {
        guard !isReadOnly else { return }
        manifest.recordings.append(recording)
        structureChanged()
    }

    func removeRecording(_ id: UUID) {
        guard !isReadOnly else { return }
        manifest.recordings.removeAll { $0.id == id }
        structureChanged()
    }

    /// Favourite, trash and folder changes made from the library while this notebook is open.
    func updateLibraryState(_ change: (inout LibraryState) -> Void) {
        guard !isReadOnly else { return }
        change(&manifest.library)
        manifestVersion += 1
        scheduleSave()
    }

    /// A library change written to the files while this document was being opened. Applying it again is
    /// harmless if the document already read it, and keeps its first save from reverting it otherwise.
    func applyLibraryChange(_ change: (inout NotebookManifest) -> Void) {
        guard !isReadOnly else { return }
        var changed = manifest
        change(&changed)
        guard changed != manifest else { return }
        manifest = changed
        manifestVersion += 1
        scheduleSave()
        onStructureChange?()
    }

    func dismissNotice(_ notice: DocumentNotice) {
        notices.removeAll { $0.id == notice.id }
    }

    private func structureChanged() {
        manifestVersion += 1
        manifest.modifiedAt = .now
        scheduleSave()
        onStructureChange?()
    }

    // MARK: Work in flight

    /// Runs work that will add to the document, such as an import, so closing waits for it to land.
    func perform(_ work: @escaping @MainActor () async -> Void) {
        let token = UUID()
        pendingWork[token] = Task {
            await work()
            self.pendingWork[token] = nil
        }
    }

    func finishPendingWork() async {
        while let task = pendingWork.values.first { await task.value }
    }

    // MARK: Saving

    /// Debounced: each edit pushes the save back by `delay`, but never past `maxSaveLatency` after the first
    /// unsaved edit. With `coalesce`, an earlier pending save is never postponed.
    func scheduleSave(after delay: Duration? = nil, coalesce: Bool = false) {
        guard !isReadOnly else { return }
        if case .failed = saveState { return }
        let now = ContinuousClock.now
        let since = pendingSince ?? now
        var deadline = min(now + (delay ?? saveDelay), since + maxSaveLatency)
        if coalesce, let pendingDeadline { deadline = min(deadline, pendingDeadline) }
        pendingSince = since
        pendingDeadline = deadline
        pendingSave?.cancel()
        if saveState == .saved { saveState = .pending }
        pendingSave = Task { [self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled else { return }
            pendingDeadline = nil
            pendingSince = nil
            await save()
        }
    }

    /// Writes dirty pages, then the manifest. Only one save runs at a time; a failed save keeps everything
    /// dirty and retries with backoff. Returns true when everything is on disk.
    @discardableResult
    func save() async -> Bool {
        if let activeSave {
            _ = await activeSave.value
            if !hasUnsavedChanges { return true }
        }
        guard !isReadOnly, hasUnsavedChanges else {
            if !isReadOnly { saveState = .saved }
            return true
        }
        let task = Task { await performSave() }
        activeSave = task
        let result = await task.value
        activeSave = nil
        return result
    }

    struct PendingSave {
        let snapshot: SaveSnapshot
        let versions: [UUID: Int]
        let manifestVersion: Int
        let inkModifiedAt: Date?
    }

    /// The main-thread part of a save: value snapshots of the manifest and the dirty pages' ink.
    func makePendingSave() -> PendingSave {
        var versions: [UUID: Int] = [:]
        var dirtyInk: [UUID: PKDrawing] = [:]
        for (pageID, ink) in inks where ink.isDirty && index(of: pageID) != nil {
            dirtyInk[pageID] = ink.drawing
            versions[pageID] = ink.version
        }
        var snapshot = manifest
        if let inkModifiedAt { snapshot.modifiedAt = max(snapshot.modifiedAt, inkModifiedAt) }
        return PendingSave(snapshot: SaveSnapshot(manifest: snapshot, ink: dirtyInk), versions: versions,
                           manifestVersion: manifestVersion, inkModifiedAt: inkModifiedAt)
    }

    private func performSave() async -> Bool {
        pendingSave?.cancel()
        pendingDeadline = nil
        pendingSince = nil
        let interval = signposter.beginInterval("Save")
        saveState = .saving
        let pending = makePendingSave()
        signposter.emitEvent("Save snapshot taken")
        do {
            let receipt = try await package.write(pending.snapshot)
            for (pageID, version) in pending.versions {
                inks[pageID]?.savedVersion = version
                if inks[pageID]?.version == version, let hash = receipt.inkHashes[pageID], let index = index(of: pageID) {
                    manifest.pages[index].inkHash = hash
                }
            }
            if let written = pending.inkModifiedAt {
                if manifest.modifiedAt < written { manifest.modifiedAt = written }
                if inkModifiedAt == written { inkModifiedAt = nil }
            }
            if manifestVersion == pending.manifestVersion { savedManifestVersion = pending.manifestVersion }
            failures = 0
            saveState = hasUnsavedChanges ? .pending : .saved
            if notices.contains(where: { $0.kind == .saveFailed }) { notices.removeAll { $0.kind == .saveFailed } }
            signposter.endInterval("Save", interval)
            let signature = IndexSignature(receipt.manifest)
            if signature != indexedSignature {
                indexedSignature = signature
                onSaved?(receipt.manifest)
            }
            if hasUnsavedChanges { scheduleSave() }
            return !hasUnsavedChanges
        } catch {
            failures += 1
            let wait = min(retryBase * (1 << min(failures - 1, 6)), .seconds(60))
            saveState = .failed(error.localizedDescription, retryIn: wait)
            if !notices.contains(where: { $0.kind == .saveFailed }) {
                notices.append(DocumentNotice(kind: .saveFailed, message: "Couldn't save your latest changes. Swift Scribe will keep trying; nothing has been lost."))
            }
            signposter.endInterval("Save", interval)
            pendingSave = Task { [self] in
                try? await Task.sleep(for: wait)
                guard !Task.isCancelled else { return }
                if case .failed = saveState { saveState = .pending }
                await save()
            }
            return false
        }
    }

    /// Saves everything now, retrying a few times. Used when the app moves to the background and on close.
    @discardableResult
    func flush(attempts: Int = 3) async -> Bool {
        for _ in 0..<attempts {
            if case .failed = saveState { saveState = .pending }
            if await save() { return true }
        }
        return !hasUnsavedChanges
    }

    /// Removes files of pages that are gone for good. Call after a successful flush when the editor closes.
    func collectGarbage() async {
        guard !hasUnsavedChanges, !isReadOnly else { return }
        await package.collectGarbage(keeping: manifest)
    }
}
