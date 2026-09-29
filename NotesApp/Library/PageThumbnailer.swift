import UIKit
import PencilKit
import os

/// Page thumbnails, rendered off the main thread and cached in the package's `thumbs/` folder by ink and appearance.
enum PageThumbnailer {
    static let pixelWidth: CGFloat = 360
    private static let memory = LRUCache<SharedUIImage>(capacity: 120)
    private static let signposter = OSSignposter(subsystem: "com.owais.NotesApp", category: "thumbnails")

    struct SharedUIImage: @unchecked Sendable { let image: UIImage }

    static func cached(package: NotebookPackage, page: NotebookPage) -> UIImage? {
        memory.value(package.thumbURL(page.id, key: page.thumbnailKey).path(percentEncoded: false)) { nil }?.image
    }

    /// Thumbnail of the saved page (its manifest ink hash). For unsaved ink, use `render(page:ink:assets:)`.
    static func thumbnail(package: NotebookPackage, page: NotebookPage) async -> UIImage? {
        let file = package.thumbURL(page.id, key: page.thumbnailKey)
        let key = file.path(percentEncoded: false)
        if let hit = memory.value(key, create: { nil }) { return hit.image }
        let assets = package.assetsDirectory
        let image = await Task.detached(priority: .utility) { () -> UIImage? in
            if let data = try? Data(contentsOf: file), let image = UIImage(data: data) { return image.preparingForDisplay() ?? image }
            let ink: PKDrawing
            switch await package.readInk(page.id) {
            case .ink(let drawing, _): ink = drawing
            case .empty, .quarantined, .cancelled: ink = PKDrawing()
            }
            let image = render(page: page, ink: ink, assets: assets)
            if let png = image.pngData() { try? await package.writeThumbnail(png, pageID: page.id, key: page.thumbnailKey) }
            return image
        }.value
        if let image { _ = memory.value(key) { SharedUIImage(image: image) } }
        return image
    }

    static func render(page: NotebookPage, ink: PKDrawing, assets: URL) -> UIImage {
        let interval = signposter.beginInterval("Thumbnail")
        defer { signposter.endInterval("Thumbnail", interval) }
        return PageRenderer.image(of: page, ink: ink, assets: assets, width: pixelWidth, scale: 1)
    }

    /// Makes sure the first page's thumbnail exists on disk, for first-page covers.
    static func ensureFirstPage(root: StorageRoot, notebookID: UUID) async -> URL? {
        let package = NotebookPackage(root: root, id: notebookID)
        guard let page = try? await package.readManifest().manifest.pages.first else { return nil }
        let file = package.thumbURL(page.id, key: page.thumbnailKey)
        if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) { return file }
        _ = await thumbnail(package: package, page: page)
        return FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) ? file : nil
    }
}
