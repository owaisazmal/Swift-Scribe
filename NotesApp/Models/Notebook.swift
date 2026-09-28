import Foundation
import SwiftData

@Model
final class Notebook {
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var isFavorite: Bool = false
    var deletedAt: Date?
    var folder: Folder?
    var pagesData: Data = Data()
    var recordingsData: Data = Data()
    var pageCount: Int = 0
    var searchText: String = ""
    var defaultTemplateRaw: String = PaperTemplate.narrowRuled.rawValue
    var defaultColorRaw: String = PaperColor.white.rawValue
    var defaultSizeRaw: String = PageSize.letter.rawValue

    init(title: String, template: PaperTemplate, color: PaperColor, size: PageSize, folder: Folder? = nil) {
        self.title = title
        self.folder = folder
        self.defaultTemplateRaw = template.rawValue
        self.defaultColorRaw = color.rawValue
        self.defaultSizeRaw = size.rawValue
        self.pages = [.template(template, color: color, size: size)]
    }

    var pages: [PageSpec] {
        get { (try? JSONDecoder().decode([PageSpec].self, from: pagesData)) ?? [] }
        set {
            pagesData = (try? JSONEncoder().encode(newValue)) ?? Data()
            pageCount = newValue.count
        }
    }

    var recordings: [Recording] {
        get { (try? JSONDecoder().decode([Recording].self, from: recordingsData)) ?? [] }
        set { recordingsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var defaultTemplate: PaperTemplate { PaperTemplate(rawValue: defaultTemplateRaw) ?? .narrowRuled }
    var defaultColor: PaperColor { PaperColor(rawValue: defaultColorRaw) ?? .white }
    var defaultSize: PageSize { PageSize(rawValue: defaultSizeRaw) ?? .letter }

    var isTrashed: Bool { deletedAt != nil }

    func newPage() -> PageSpec {
        .template(defaultTemplate, color: defaultColor, size: defaultSize)
    }
}

@Model
final class Folder {
    var id: UUID = UUID()
    var name: String = ""
    var colorRaw: String = FolderColor.blue.rawValue
    var createdAt: Date = Date()
    @Relationship(deleteRule: .nullify, inverse: \Notebook.folder)
    var notebooks: [Notebook]? = []

    init(name: String, color: FolderColor) {
        self.name = name
        self.colorRaw = color.rawValue
    }

    var color: FolderColor {
        get { FolderColor(rawValue: colorRaw) ?? .blue }
        set { colorRaw = newValue.rawValue }
    }
}

enum FolderColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, blue, indigo, purple, pink, gray
    var id: String { rawValue }
}
