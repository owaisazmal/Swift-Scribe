import UIKit
import SwiftUI
import PencilKit
import os

/// Writes a notebook as a PDF: vector backgrounds (templates, the original PDF pages, photos) with the ink
/// on top, clipped to each page. Runs off the main thread and reports progress; cancellable between pages.
enum NotebookExporter {
    private static let signposter = OSSignposter(subsystem: "com.owais.NotesApp", category: "export")

    struct Input: Sendable {
        var title: String
        var pages: [NotebookPage]
        var inMemoryInk: [UUID: PKDrawing]
        var package: NotebookPackage
    }

    /// Streams pages to disk one at a time: each page's ink is read, drawn and released before the next,
    /// so memory stays flat however long the notebook is.
    static func export(_ input: Input, progress: @escaping @Sendable (Double) async -> Void) async throws -> URL {
        let interval = signposter.beginInterval("Export", "\(input.pages.count) pages")
        defer { signposter.endInterval("Export", interval) }
        let name = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(name.isEmpty ? "Untitled" : name).pdf")
        try Task.checkCancellation()

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: input.title, kCGPDFContextCreator as String: "Swift Scribe"]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: input.pages.first?.size ?? PageSize.letter.points), format: format)
        let assets = input.package.assetsDirectory
        let count = Double(max(input.pages.count, 1))
        let outline = outline(for: input.pages)
        let links = LinkTitles(pages: input.pages)
        let linked = linkedPages(in: input.pages)
        try renderer.writePDF(to: url) { context in
            if let outline { CGPDFContextSetOutline(context.cgContext, outline as CFDictionary) }
            for (index, page) in input.pages.enumerated() {
                if Task.isCancelled { return }
                autoreleasepool {
                    let bounds = CGRect(origin: .zero, size: page.size)
                    context.beginPage(withBounds: bounds, pageInfo: [:])
                    PageRenderer.drawBackground(page, assets: assets, in: context.cgContext, size: page.size, links: links)
                    // Destinations are placed in the PDF's own space, which runs up the page.
                    if linked.contains(page.id) { context.addDestination(withName: page.id.uuidString, at: CGPoint(x: 0, y: page.size.height)) }
                    if page.hasItems {
                        for item in page.items {
                            guard let link = item.link, linked.contains(link.target) else { continue }
                            let box = item.boundingBox
                            context.setDestinationWithName(link.target.uuidString, for: CGRect(x: box.minX, y: page.size.height - box.maxY, width: box.width, height: box.height))
                        }
                    }
                    let ink = input.inMemoryInk[page.id] ?? savedInk(page, in: input.package)
                    if !ink.strokes.isEmpty {
                        var image: UIImage?
                        UITraitCollection(userInterfaceStyle: page.effectivePaperColor.inkAppearance).performAsCurrent {
                            image = ink.image(from: bounds, scale: 3)
                        }
                        image?.draw(in: bounds)
                    }
                }
                let fraction = Double(index + 1) / count
                Task { await progress(fraction) }
            }
        }
        if Task.isCancelled {
            try? FileManager.default.removeItem(at: directory)
            throw CancellationError()
        }
        await progress(1)
        return url
    }

    /// The pages that links on other pages open, so those links still work in the exported PDF.
    static func linkedPages(in pages: [NotebookPage]) -> Set<UUID> {
        let ids = Set(pages.map(\.id))
        var linked = Set<UUID>()
        for page in pages where page.hasItems {
            for item in page.items { if let target = item.link?.target, ids.contains(target) { linked.insert(target) } }
        }
        return linked
    }

    /// Bookmarks become the PDF's outline, so they show in any reader's sidebar.
    static func outline(for pages: [NotebookPage]) -> [String: Any]? {
        let children: [[String: Any]] = pages.enumerated().compactMap { index, page in
            guard page.bookmark != nil else { return nil }
            return [kCGPDFOutlineTitle as String: page.bookmarkTitle(number: index + 1), kCGPDFOutlineDestination as String: index + 1]
        }
        return children.isEmpty ? nil : [kCGPDFOutlineChildren as String: children]
    }

    /// Reads a page's saved ink directly: writes are atomic, so reading outside the package actor is safe.
    /// A file that can't be decoded exports as a blank page; the editor sets it aside when the page is opened.
    private static func savedInk(_ page: NotebookPage, in package: NotebookPackage) -> PKDrawing {
        guard let data = try? Data(contentsOf: package.inkURL(page.id)) else { return PKDrawing() }
        return (try? NotebookPackage.decodeInk(data)) ?? PKDrawing()
    }
}

@MainActor
@Observable
final class ExportJob: Identifiable {
    enum State: Equatable { case running, finished(URL), failed(String), cancelled }

    let id = UUID()
    private(set) var progress: Double = 0
    private(set) var state: State = .running
    @ObservationIgnored private var task: Task<Void, Never>?

    convenience init(document: NotebookDocument) {
        var inMemory: [UUID: PKDrawing] = [:]
        for page in document.pages { if let ink = document.loadedInk(page.id) { inMemory[page.id] = ink } }
        self.init(input: NotebookExporter.Input(title: document.title, pages: document.pages, inMemoryInk: inMemory, package: document.package))
    }

    /// Exports from the library: the open document, with its unsaved ink, if the notebook is being edited, otherwise the saved pages.
    static func forNotebook(_ id: UUID, root: StorageRoot) async throws -> ExportJob {
        if let document = DocumentRegistry.shared.document(for: id) { return ExportJob(document: document) }
        let package = NotebookPackage(root: root, id: id)
        let manifest = try await package.readManifest().manifest
        return ExportJob(input: NotebookExporter.Input(title: manifest.title, pages: manifest.pages, inMemoryInk: [:], package: package))
    }

    init(input: NotebookExporter.Input) {
        task = Task { [weak self] in
            let work = Task.detached(priority: .userInitiated) {
                try await NotebookExporter.export(input) { value in
                    await MainActor.run { self?.progress = max(self?.progress ?? 0, value) }
                }
            }
            do {
                let url = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                if self?.state == .running { self?.state = .finished(url) }
            } catch is CancellationError {
                self?.state = .cancelled
            } catch {
                self?.state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        state = .cancelled
    }
}

struct ExportSheet: View {
    let job: ExportJob
    @Environment(\.dismiss) private var dismiss
    @State private var sharing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Space.x5) {
                switch job.state {
                case .running:
                    ProgressView(value: job.progress) { Text("Exporting…") } currentValueLabel: {
                        Text(job.progress, format: .percent.precision(.fractionLength(0)))
                    }
                    Button("Cancel", role: .cancel) { job.cancel(); dismiss() }
                case .finished(let url):
                    Label("Your PDF is ready.", systemImage: "checkmark.circle").font(.headline)
                    HStack(spacing: Space.x3) {
                        Button { sharing = true } label: { Label("Share", systemImage: "square.and.arrow.up") }
                            .prominentButton()
                        Button { print(url) } label: { Label("Print", systemImage: "printer") }
                            .buttonStyle(.bordered)
                    }
                    .sheet(isPresented: $sharing) { ShareSheet(items: [url]) }
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                case .cancelled:
                    Text("Export cancelled.")
                }
            }
            .padding(Space.x8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.surface)
            .navigationTitle("Export PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
        .onDisappear { if job.state == .running { job.cancel() } }
    }

    private func print(_ url: URL) {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.jobName = url.deletingPathExtension().lastPathComponent
        info.outputType = .general
        controller.printInfo = info
        controller.printingItem = url
        controller.present(animated: true)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
