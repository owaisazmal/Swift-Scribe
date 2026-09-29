import Foundation
import SwiftData
import PencilKit

/// Test-only: a small library in the exact v1 format, for exercising the migration in UI tests.
enum V1Seed {
    static let notebookTitle = "Migrated Lecture"

    static func write(root: StorageRoot) async {
        #if DEBUG
        do {
            try FileManager.default.createDirectory(at: root.url, withIntermediateDirectories: true)
            let schema = Schema(versionedSchema: LegacyV1Schema.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: root.v1Store))
            let context = ModelContext(container)
            let folder = LegacyV1Schema.Folder(name: "Lectures", colorRaw: "indigo")
            context.insert(folder)
            let notebook = LegacyV1Schema.Notebook(title: notebookTitle)
            notebook.folder = folder
            notebook.isFavorite = true
            let pages = (0..<3).map { index in
                JSONValue.object([
                    "id": .string(UUID().uuidString),
                    "background": .object(["template": .object(["_0": .string(index == 1 ? "grid" : "narrowRuled")])]),
                    "paperColor": .string("white"),
                    "size": .array([.number(612), .number(792)]),
                ])
            }
            notebook.pagesData = try JSONValue.array(pages).serialized(pretty: false)
            notebook.pageCount = 3
            context.insert(notebook)
            try context.save()

            let frames = LegacyV1Layout.frames(for: Array(repeating: PageSize.letter.points, count: 3))
            var strokes: [PKStroke] = []
            for (page, frame) in frames.enumerated() {
                for line in 0..<(page + 2) {
                    let y = frame.minY + 160 + CGFloat(line) * 40
                    let points = (0..<16).map { i -> PKStrokePoint in
                        let t = CGFloat(i) / 15
                        return PKStrokePoint(location: CGPoint(x: frame.minX + 140 + 400 * t, y: y + 8 * sin(t * 12)),
                                             timeOffset: TimeInterval(t) * 0.4, size: CGSize(width: 3, height: 3),
                                             opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                    }
                    strokes.append(PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: .now)))
                }
            }
            let directory = root.v1Notebooks.appending(path: notebook.id.uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try PKDrawing(strokes: strokes).dataRepresentation().write(to: directory.appending(path: "drawing.pkdrawing"))
        } catch {
            assertionFailure("v1 seed failed: \(error)")
        }
        #endif
    }
}
