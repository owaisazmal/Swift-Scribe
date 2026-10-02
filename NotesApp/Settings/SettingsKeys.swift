import PencilKit

enum DrawingInput: String, CaseIterable, Identifiable {
    case system, pencilOnly, anyInput
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: String(localized: "System Setting")
        case .pencilOnly: String(localized: "Apple Pencil Only")
        case .anyInput: String(localized: "Pencil and Finger")
        }
    }

    var policy: PKCanvasViewDrawingPolicy {
        switch self {
        case .system: .default
        case .pencilOnly: .pencilOnly
        case .anyInput: .anyInput
        }
    }
}

enum SettingsKey {
    static let drawingInput = "drawingInput"
    static let defaultTemplate = "defaultTemplate"
    static let defaultPaperColor = "defaultPaperColor"
    static let defaultPageSize = "defaultPageSize"
    static let librarySort = "librarySort"
    static let dailyJournalID = "dailyJournalID"
    static let dailyJournalPromptHidden = "dailyJournalPromptHidden"
    static let showsOnThisDay = "showsOnThisDay"
    static let onThisDayHiddenDay = "onThisDayHiddenDay"
    static let keepsWritingHistory = "keepsWritingHistory"
    static let snapsShapes = "snapsShapes"
    static let syncsWithICloud = "syncsWithICloud"
    static let tapeColor = "tapeColor"
    static let transcriptLanguage = "transcriptLanguage"
    static let indexSchema = "libraryIndexSchema"
}