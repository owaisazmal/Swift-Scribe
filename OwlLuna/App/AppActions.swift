import AppIntents
import SwiftData

/// Something asked of the app from outside its windows: a widget link, a shortcut, Siri.
enum AppAction: Equatable, Sendable {
    case today, quickNote, continueWriting
    case open(UUID, page: UUID? = nil)

    static let scheme = "owlluna"

    /// The address that opens a notebook, at one of its pages if given. Links in exported PDFs use it.
    static func url(forNotebook id: UUID, page: UUID? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "notebook"
        components.path = "/\(id.uuidString)"
        if let page { components.queryItems = [URLQueryItem(name: "page", value: page.uuidString)] }
        return components.url
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        switch url.host() {
        case "today": self = .today
        case "quicknote": self = .quickNote
        case "continue": self = .continueWriting
        case "notebook":
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value
            self = .open(id, page: page.flatMap(UUID.init(uuidString:)))
        default: return nil
        }
    }
}

extension Notification.Name {
    /// Asks the editor showing a notebook (object: its ID) to save and close.
    static let owlLunaCloseEditor = Notification.Name("OwlLunaCloseEditor")
}

extension LibraryStore {
    /// The notebook last opened that is still on the shelves.
    var lastOpenedNotebook: NotebookRecord? { lastOpenedNotebook(includingLocked: true) }

    /// A locked notebook is never what a widget shows.
    func lastOpenedNotebook(includingLocked: Bool) -> NotebookRecord? {
        notebooks().filter { $0.lastOpenedAt != nil && (includingLocked || !$0.isLocked) }
            .max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }
    }

    /// Every notebook that isn't in Recently Deleted.
    func notebooks() -> [NotebookRecord] {
        ((try? context.fetch(FetchDescriptor<NotebookRecord>())) ?? []).filter { !$0.isTrashed }
    }
}

// MARK: Shortcuts

struct NotebookEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Notebook"
    static let defaultQuery = NotebookQuery()

    let id: UUID
    let title: String
    let pages: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(pages) pages")
    }

    @MainActor
    init(_ record: NotebookRecord) {
        id = record.id
        title = record.title.isEmpty ? String(localized: "Untitled") : record.title
        pages = record.pageCount
    }
}

struct NotebookQuery: EntityStringQuery {
    @MainActor
    private func library() async -> [NotebookRecord] {
        await AppModel.shared.start()
        return AppModel.shared.library.notebooks().sorted { ($0.lastOpenedAt ?? $0.modifiedAt) > ($1.lastOpenedAt ?? $1.modifiedAt) }
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [NotebookEntity] {
        await library().filter { identifiers.contains($0.id) }.map(NotebookEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [NotebookEntity] {
        await library().prefix(24).map(NotebookEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [NotebookEntity] {
        await library().filter { $0.title.localizedCaseInsensitiveContains(string) }.map(NotebookEntity.init)
    }
}

struct OpenTodayPageIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Today's Journal Page"
    static let description = IntentDescription("Opens today's page in your daily journal, starting a journal if you don't have one yet.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.pendingAction = .today
        return .result()
    }
}

struct QuickNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "New Quick Note"
    static let description = IntentDescription("Starts a new notebook on your default paper and opens it, ready to write.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.pendingAction = .quickNote
        return .result()
    }
}

struct ContinueWritingIntent: AppIntent {
    static let title: LocalizedStringResource = "Continue Writing"
    static let description = IntentDescription("Opens the notebook you last wrote in, at the page you left.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.pendingAction = .continueWriting
        return .result()
    }
}

struct OpenNotebookIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Notebook"
    static let description = IntentDescription("Opens one of your notebooks.")
    static let openAppWhenRun = true

    @Parameter(title: "Notebook")
    var notebook: NotebookEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.pendingAction = .open(notebook.id)
        return .result()
    }
}

struct OwlLunaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenTodayPageIntent(),
                    phrases: ["Open today's page in \(.applicationName)", "Write in my \(.applicationName) journal"],
                    shortTitle: "Today's Page", systemImageName: "calendar")
        AppShortcut(intent: QuickNoteIntent(),
                    phrases: ["New quick note in \(.applicationName)", "Start a note in \(.applicationName)"],
                    shortTitle: "Quick Note", systemImageName: "square.and.pencil")
        AppShortcut(intent: ContinueWritingIntent(),
                    phrases: ["Continue writing in \(.applicationName)"],
                    shortTitle: "Continue Writing", systemImageName: "book")
        AppShortcut(intent: OpenNotebookIntent(),
                    phrases: ["Open a notebook in \(.applicationName)", "Open \(\.$notebook) in \(.applicationName)"],
                    shortTitle: "Open Notebook", systemImageName: "books.vertical")
    }
}
