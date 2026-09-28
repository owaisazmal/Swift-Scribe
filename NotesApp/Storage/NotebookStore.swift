import Foundation
import PencilKit
import UIKit

enum NotebookStore {
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Notebooks", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func directory(for id: UUID) -> URL {
        let url = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func drawingURL(for id: UUID) -> URL {
        directory(for: id).appendingPathComponent("drawing.pkdrawing")
    }

    static func thumbnailURL(for id: UUID) -> URL {
        directory(for: id).appendingPathComponent("thumbnail.png")
    }

    static func assetsDirectory(for id: UUID) -> URL {
        let url = directory(for: id).appendingPathComponent("assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func assetURL(_ fileName: String, notebook id: UUID) -> URL {
        assetsDirectory(for: id).appendingPathComponent(fileName)
    }

    static func loadDrawing(for id: UUID) -> PKDrawing {
        guard let data = try? Data(contentsOf: drawingURL(for: id)),
              let drawing = try? PKDrawing(data: data) else { return PKDrawing() }
        return drawing
    }

    static func save(_ drawing: PKDrawing, for id: UUID) {
        try? drawing.dataRepresentation().write(to: drawingURL(for: id), options: .atomic)
    }

    static func saveThumbnail(_ image: UIImage, for id: UUID) {
        try? image.pngData()?.write(to: thumbnailURL(for: id), options: .atomic)
    }

    static func importAsset(from source: URL, notebook id: UUID, ext: String) throws -> String {
        let name = "\(UUID().uuidString).\(ext)"
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: source, to: assetURL(name, notebook: id))
        return name
    }

    static func writeAsset(_ data: Data, notebook id: UUID, ext: String) throws -> String {
        let name = "\(UUID().uuidString).\(ext)"
        try data.write(to: assetURL(name, notebook: id), options: .atomic)
        return name
    }

    static func duplicate(from source: UUID, to destination: UUID) {
        let src = directory(for: source)
        let dst = root.appendingPathComponent(destination.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: dst)
        try? FileManager.default.copyItem(at: src, to: dst)
    }

    static func deleteFiles(for id: UUID) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(id.uuidString, isDirectory: true))
    }
}
