import UIKit
import PDFKit
import Vision
import PencilKit
import os

/// Recognises handwriting page by page, off the main thread. A page is only re-read when its saved ink hash
/// changes, and an edit cancels any recognition still running for that page.
actor HandwritingIndexer {
    static let shared = HandwritingIndexer()

    private var running: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]
    private let signposter = OSSignposter(subsystem: "com.owais.NotesApp", category: "ocr")

    struct Job: Sendable {
        let package: NotebookPackage
        let pages: [NotebookPage]
    }

    /// Queues recognition for pages whose text is missing or older than their ink. Returns the notebook's full text.
    /// A page already being read by another job is awaited rather than read twice.
    @discardableResult
    func index(_ job: Job) async -> String {
        for page in job.pages {
            guard !Task.isCancelled,
                  FileManager.default.fileExists(atPath: job.package.manifestURL.path(percentEncoded: false)) else { break }
            if let existing = running[page.id] { await existing.task.value }
            if await isCurrent(page, in: job.package) { continue }
            if let existing = running[page.id] {
                await existing.task.value
                if await isCurrent(page, in: job.package) { continue }
            }
            let token = UUID()
            let task = Task(priority: .utility) { await recognize(page, in: job.package) }
            running[page.id] = (token, task)
            await task.value
            if running[page.id]?.token == token { running[page.id] = nil }
        }
        if await isComplete(job) { await job.package.removeLegacyText() }
        return LibraryIndex.searchText(in: job.package.textDirectory)
    }

    func cancel(page: UUID) {
        running[page]?.task.cancel()
        running[page] = nil
    }

    /// Whether every page of the notebook, not just this job's, has current text. A v1 notebook whose ink couldn't
    /// be read never is: its v1 search text is the only trace of that ink.
    private func isComplete(_ job: Job) async -> Bool {
        let damagedV1Ink = job.package.url.appending(path: "legacy/drawing.pkdrawing.corrupt")
        guard !Task.isCancelled, !FileManager.default.fileExists(atPath: damagedV1Ink.path(percentEncoded: false)),
              let pages = try? await job.package.readManifest().manifest.pages else { return false }
        for page in pages where !(await isCurrent(page, in: job.package)) { return false }
        return true
    }

    private func isCurrent(_ page: NotebookPage, in package: NotebookPackage) async -> Bool {
        guard let text = await package.readText(page.id) else { return page.inkHash == nil && !page.hasPDFText }
        return text.hasPrefix(Self.header(for: page))
    }

    nonisolated static func header(for page: NotebookPage) -> String {
        "#ink:\(page.inkHash ?? "none")\n"
    }

    /// Rendering and Vision run off the actor, so an edit's `cancel(page:)` gets through while they work.
    private nonisolated func recognize(_ page: NotebookPage, in package: NotebookPackage) async {
        let interval = signposter.beginInterval("OCR page")
        defer { signposter.endInterval("OCR page", interval) }
        var chunks: [String] = []
        if case .pdf(let file, let index) = page.background, let text = PDFDocument(url: package.assetURL(file))?.page(at: index)?.string {
            chunks.append(text)
        }
        if page.inkHash != nil, case .ink(let drawing, _) = await package.readInk(page.id), !drawing.strokes.isEmpty {
            guard !Task.isCancelled else { return }
            let image = PageRenderer.image(of: page, ink: drawing, assets: package.assetsDirectory, width: 1400, includeBackground: false)
            guard !Task.isCancelled, let lines = Self.recognizeText(in: image) else { return }
            chunks += lines
        }
        guard !Task.isCancelled else { return }
        try? await package.writeText(Self.header(for: page) + chunks.joined(separator: "\n"), pageID: page.id)
    }

    /// Nil when Vision fails, so the page isn't stamped as read and is tried again next time.
    nonisolated static func recognizeText(in image: UIImage) -> [String]? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        do { try VNImageRequestHandler(cgImage: cgImage).perform([request]) } catch { return nil }
        return request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
    }
}

extension NotebookPage {
    var hasPDFText: Bool {
        if case .pdf = background { return true }
        return false
    }
}
