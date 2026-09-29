import UIKit
import PDFKit
import Vision
import PencilKit
import os

/// Recognises handwriting page by page, off the main thread. A page is only re-read when its saved ink hash
/// changes, and an edit cancels any recognition still running for that page.
actor HandwritingIndexer {
    static let shared = HandwritingIndexer()

    private var running: [UUID: Task<Void, Never>] = [:]
    private let signposter = OSSignposter(subsystem: "com.owais.NotesApp", category: "ocr")

    struct Job: Sendable {
        let package: NotebookPackage
        let pages: [NotebookPage]
    }

    /// Queues recognition for pages whose text is missing or older than their ink. Returns the notebook's full text.
    @discardableResult
    func index(_ job: Job) async -> String {
        for page in job.pages {
            guard !Task.isCancelled else { break }
            if await isCurrent(page, in: job.package) { continue }
            let task = Task(priority: .utility) { await recognize(page, in: job.package) }
            running[page.id] = task
            await task.value
            running[page.id] = nil
        }
        return LibraryIndex.searchText(in: job.package.textDirectory)
    }

    func cancel(page: UUID) {
        running[page]?.cancel()
        running[page] = nil
    }

    private func isCurrent(_ page: NotebookPage, in package: NotebookPackage) async -> Bool {
        guard let text = await package.readText(page.id) else { return page.inkHash == nil && !page.hasPDFText }
        return text.hasPrefix(Self.header(for: page))
    }

    nonisolated static func header(for page: NotebookPage) -> String {
        "#ink:\(page.inkHash ?? "none")\n"
    }

    private func recognize(_ page: NotebookPage, in package: NotebookPackage) async {
        let interval = signposter.beginInterval("OCR page")
        defer { signposter.endInterval("OCR page", interval) }
        var chunks: [String] = []
        if case .pdf(let file, let index) = page.background, let text = PDFDocument(url: package.assetURL(file))?.page(at: index)?.string {
            chunks.append(text)
        }
        if page.inkHash != nil, case .ink(let drawing, _) = await package.readInk(page.id), !drawing.strokes.isEmpty {
            guard !Task.isCancelled else { return }
            let image = PageRenderer.image(of: page, ink: drawing, assets: package.assetsDirectory, width: 1400, includeBackground: false)
            guard !Task.isCancelled else { return }
            chunks += Self.recognizeText(in: image)
        }
        guard !Task.isCancelled else { return }
        try? await package.writeText(Self.header(for: page) + chunks.joined(separator: "\n"), pageID: page.id)
    }

    nonisolated static func recognizeText(in image: UIImage) -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try? VNImageRequestHandler(cgImage: cgImage).perform([request])
        return request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
    }
}

extension NotebookPage {
    var hasPDFText: Bool {
        if case .pdf = background { return true }
        return false
    }
}
