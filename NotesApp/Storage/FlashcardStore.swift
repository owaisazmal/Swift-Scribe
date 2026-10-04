import UIKit
import os

/// The files flashcards live in: `cards.json` beside a notebook's manifest and clippings in its `cards/` folder,
/// so they are copied, backed up, synced and deleted with the notebook. Thread-safe.
enum CardFiles {
    struct Deck: Sendable {
        var cards: [Flashcard] = []
        /// Written by a newer version, or set aside as damaged: shown, never written over.
        var isReadOnly = false
    }

    static func file(in package: URL) -> URL { package.appending(path: "cards.json") }
    static func directory(in package: URL) -> URL { package.appending(path: "cards", directoryHint: .isDirectory) }
    static func imageURL(_ name: String, in package: URL) -> URL { directory(in: package).appending(path: name) }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func read(_ package: URL) -> Deck {
        let url = file(in: package)
        guard let data = try? Data(contentsOf: url) else { return Deck() }
        guard let decoded = try? decoder.decode(FlashcardFile.self, from: data) else {
            return Deck(isReadOnly: (try? Quarantine.move(url)) == nil)
        }
        return Deck(cards: decoded.cards, isReadOnly: decoded.version > FlashcardFile.currentVersion)
    }

    /// Never brings back a notebook that was deleted while a review was going on.
    static func write(_ cards: [Flashcard], to package: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: package.appending(path: "manifest.json").path(percentEncoded: false)) else { throw PackageError.missing }
        let url = file(in: package)
        if cards.isEmpty {
            if fileManager.fileExists(atPath: url.path(percentEncoded: false)) { try fileManager.removeItem(at: url) }
            try? fileManager.removeItem(at: directory(in: package))
            return
        }
        try encoder.encode(FlashcardFile(cards: cards)).write(to: url, options: .atomic)
        let kept = Set(cards.flatMap { [$0.front.image, $0.back.image] }.compactMap { $0 })
        // A clipping is written before the card that names it, so only ones left over for a while are cleared.
        let stale = Date.now.addingTimeInterval(-600)
        for image in (try? fileManager.contentsOfDirectory(at: directory(in: package), includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        where !kept.contains(image.lastPathComponent) {
            let written = (try? image.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if written < stale { try? fileManager.removeItem(at: image) }
        }
    }

    static func writeImage(_ png: Data, in package: URL) throws -> String {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: package.appending(path: "manifest.json").path(percentEncoded: false)) else { throw PackageError.missing }
        let folder = directory(in: package)
        if !fileManager.fileExists(atPath: folder.path(percentEncoded: false)) {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
        }
        let name = "\(UUID().uuidString).png"
        try png.write(to: folder.appending(path: name), options: .atomic)
        return name
    }
}

/// Writes decks one after another, so a quick run of answers lands on disk in the order it was given.
private actor CardWriter {
    func write(_ cards: [Flashcard], to package: URL) -> Bool {
        (try? CardFiles.write(cards, to: package)) != nil
    }

    func writeImage(_ png: Data, in package: URL) throws -> String {
        try CardFiles.writeImage(png, in: package)
    }
}

/// A card and the notebook it belongs to.
struct DeckCard: Identifiable, Equatable, Sendable {
    let notebook: UUID
    var card: Flashcard
    var id: UUID { card.id }
}

/// Every notebook's flashcards, read once at launch and kept in step with the files.
@MainActor
@Observable
final class FlashcardLibrary {
    let root: StorageRoot
    private(set) var decks: [UUID: [Flashcard]] = [:]
    private(set) var readOnly: Set<UUID> = []
    private(set) var isLoaded = false
    @ObservationIgnored private let writer = CardWriter()
    @ObservationIgnored private let log = Logger(subsystem: "com.owais.NotesApp", category: "flashcards")
    @ObservationIgnored private let images = LRUCache<PageThumbnailer.SharedUIImage>(capacity: 40)

    init(root: StorageRoot) {
        self.root = root
    }

    /// Reads every notebook's cards. Called at launch and after a sync or a restore changed the library on disk.
    func load() async {
        let root = root
        let found = await Task.detached(priority: .utility) {
            var decks: [UUID: CardFiles.Deck] = [:]
            for id in root.packageIDs() {
                let deck = CardFiles.read(root.package(id))
                if !deck.cards.isEmpty || deck.isReadOnly { decks[id] = deck }
            }
            return decks
        }.value
        decks = found.mapValues(\.cards).filter { !$0.value.isEmpty }
        readOnly = Set(found.filter(\.value.isReadOnly).keys)
        isLoaded = true
    }

    /// Picks up notebooks that appeared since the last load: a duplicate carries its cards with it.
    func loadNewNotebooks() async {
        guard isLoaded else { return }
        let root = root, known = Set(decks.keys).union(readOnly)
        let found = await Task.detached(priority: .utility) {
            var decks: [UUID: CardFiles.Deck] = [:]
            for id in root.packageIDs() where !known.contains(id) {
                guard FileManager.default.fileExists(atPath: CardFiles.file(in: root.package(id)).path(percentEncoded: false)) else { continue }
                decks[id] = CardFiles.read(root.package(id))
            }
            return decks
        }.value
        for (id, deck) in found where decks[id] == nil {
            if !deck.cards.isEmpty { decks[id] = deck.cards }
            if deck.isReadOnly { readOnly.insert(id) }
        }
    }

    func forget(notebooks: [UUID]) {
        for id in notebooks {
            decks[id] = nil
            readOnly.remove(id)
        }
    }

    // MARK: Reading

    func cards(in notebook: UUID) -> [Flashcard] { decks[notebook] ?? [] }

    func canChange(_ notebook: UUID) -> Bool { !readOnly.contains(notebook) }

    func card(for tape: UUID, in notebook: UUID) -> Flashcard? { decks[notebook]?.first { $0.tapeID == tape } }

    /// The cards to go through today, the longest overdue first.
    func due(in notebooks: some Sequence<UUID>, on day: String = ActivityFile.dayKey(for: .now, calendar: .current)) -> [DeckCard] {
        notebooks.flatMap { id in cards(in: id).filter { $0.isDue(on: day) }.map { DeckCard(notebook: id, card: $0) } }
            .sorted { ($0.card.due, $0.card.createdAt) < ($1.card.due, $1.card.createdAt) }
    }

    func all(in notebooks: some Sequence<UUID>) -> [DeckCard] {
        notebooks.flatMap { id in cards(in: id).map { DeckCard(notebook: id, card: $0) } }
            .sorted { ($0.card.due, $0.card.createdAt) < ($1.card.due, $1.card.createdAt) }
    }

    /// The first day after `day` on which a card comes due.
    func nextDue(in notebooks: some Sequence<UUID>, after day: String = ActivityFile.dayKey(for: .now, calendar: .current)) -> String? {
        notebooks.flatMap { cards(in: $0).map(\.due) }.filter { $0 > day }.min()
    }

    func imageURL(_ name: String, in notebook: UUID) -> URL { CardFiles.imageURL(name, in: root.package(notebook)) }

    func image(_ name: String?, in notebook: UUID) async -> UIImage? {
        guard let name else { return nil }
        let url = imageURL(name, in: notebook), key = url.path(percentEncoded: false)
        if let hit = images.value(key, create: { nil }) { return hit.image }
        let loaded = await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: key).map { PageThumbnailer.SharedUIImage(image: $0.preparingForDisplay() ?? $0) }
        }.value
        guard let loaded else { return nil }
        return images.value(key) { loaded }?.image
    }

    // MARK: Changing

    @discardableResult
    func add(_ cards: [Flashcard], to notebook: UUID) -> Bool {
        guard canChange(notebook), !cards.isEmpty else { return false }
        decks[notebook, default: []].append(contentsOf: cards)
        save(notebook)
        return true
    }

    func update(_ card: Flashcard, in notebook: UUID) {
        guard canChange(notebook), let index = decks[notebook]?.firstIndex(where: { $0.id == card.id }) else { return }
        decks[notebook]?[index] = card
        save(notebook)
    }

    func remove(_ ids: Set<UUID>, from notebook: UUID) {
        guard canChange(notebook), decks[notebook] != nil else { return }
        decks[notebook]?.removeAll { ids.contains($0.id) }
        if decks[notebook]?.isEmpty == true { decks[notebook] = nil }
        save(notebook)
    }

    /// Records an answer and returns the card as it now stands.
    @discardableResult
    func grade(_ id: UUID, in notebook: UUID, _ grade: CardGrade, now: Date = .now, calendar: Calendar = .current) -> Flashcard? {
        guard let card = decks[notebook]?.first(where: { $0.id == id }) else { return nil }
        let next = CardSchedule.graded(card, grade, now: now, calendar: calendar)
        update(next, in: notebook)
        return canChange(notebook) ? next : card
    }

    /// Keeps a clipping in the notebook, ready to be named by a card.
    func saveClipping(_ image: UIImage, in notebook: UUID) async throws -> String {
        guard canChange(notebook) else { throw PackageError.readOnly }
        guard let png = image.pngData() else { throw ImportError.unreadable }
        return try await writer.writeImage(png, in: root.package(notebook))
    }

    /// Waits until everything changed so far is on disk.
    func flush() async {
        await pending?.value
    }

    @ObservationIgnored private var pending: Task<Void, Never>?

    private func save(_ notebook: UUID) {
        let cards = decks[notebook] ?? [], package = root.package(notebook), writer = writer, log = log, previous = pending
        pending = Task {
            await previous?.value
            if await !writer.write(cards, to: package) { log.error("flashcards for \(notebook.uuidString) couldn't be saved") }
        }
    }
}
