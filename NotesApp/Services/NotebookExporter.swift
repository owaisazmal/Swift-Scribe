import UIKit
import SwiftUI
import PencilKit
import AVFoundation
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
        let name = fileName(input.title)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(name).pdf")
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
                            guard let link = item.link else { continue }
                            let box = item.boundingBox
                            let area = CGRect(x: box.minX, y: page.size.height - box.maxY, width: box.width, height: box.height)
                            if let target = link.target {
                                if linked.contains(target) { context.setDestinationWithName(target.uuidString, for: area) }
                            } else if let url = link.externalURL {
                                context.setURL(url, for: area)
                            }
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
                    PageRenderer.drawOverInk(page, assets: assets, in: context.cgContext, size: page.size)
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

    static func fileName(_ title: String) -> String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        return name.isEmpty ? String(localized: "Untitled") : name
    }

    /// Writes each page as a PNG, twice the page's size in points, numbered in page order.
    static func exportImages(_ input: Input, progress: @escaping @Sendable (Double) async -> Void) async throws -> [URL] {
        let interval = signposter.beginInterval("Export", "\(input.pages.count) images")
        defer { signposter.endInterval("Export", interval) }
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = fileName(input.title), assets = input.package.assetsDirectory, links = LinkTitles(pages: input.pages)
        let digits = String(input.pages.count).count, count = Double(max(input.pages.count, 1))
        var urls: [URL] = []
        for (index, page) in input.pages.enumerated() {
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: directory)
                throw CancellationError()
            }
            let number = input.pages.count == 1 ? "" : " " + String(repeating: "0", count: digits - String(index + 1).count) + String(index + 1)
            let url = directory.appending(path: "\(name)\(number).png")
            let ink = input.inMemoryInk[page.id] ?? savedInk(page, in: input.package)
            let data = autoreleasepool {
                PageRenderer.image(of: page, ink: ink, assets: assets, width: page.size.width, scale: 2, links: links).pngData()
            }
            guard let data else { throw ImportError.unreadable }
            try data.write(to: url, options: .atomic)
            urls.append(url)
            await progress(Double(index + 1) / count)
        }
        return urls
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
    static func savedInk(_ page: NotebookPage, in package: NotebookPackage) -> PKDrawing {
        guard let data = try? Data(contentsOf: package.inkURL(page.id)) else { return PKDrawing() }
        return (try? NotebookPackage.decodeInk(data)) ?? PKDrawing()
    }
}

@MainActor
@Observable
final class ExportJob: Identifiable {
    enum State: Equatable { case running, finished([URL]), failed(String), cancelled }
    /// One PDF, a PNG for every page, or a film of one page being written.
    enum Format: Sendable { case pdf, images, timelapse }

    let id = UUID()
    let format: Format
    /// The first page's width over its height, for showing a film of it.
    let shape: CGFloat
    private(set) var progress: Double = 0
    private(set) var state: State = .running
    @ObservationIgnored private var task: Task<Void, Never>?

    /// `pages` narrows the export to some of the notebook's pages; nil exports them all.
    convenience init(document: NotebookDocument, format: Format = .pdf, pages: [NotebookPage]? = nil) {
        let pages = pages ?? document.pages
        var inMemory: [UUID: PKDrawing] = [:]
        for page in pages { if let ink = document.loadedInk(page.id) { inMemory[page.id] = ink } }
        self.init(input: NotebookExporter.Input(title: document.title, pages: pages, inMemoryInk: inMemory, package: document.package), format: format)
    }

    /// Exports from the library: the open document, with its unsaved ink, if the notebook is being edited, otherwise the saved pages.
    static func forNotebook(_ id: UUID, root: StorageRoot, format: Format = .pdf) async throws -> ExportJob {
        if let document = DocumentRegistry.shared.document(for: id) { return ExportJob(document: document, format: format) }
        let package = NotebookPackage(root: root, id: id)
        let manifest = try await package.readManifest().manifest
        return ExportJob(input: NotebookExporter.Input(title: manifest.title, pages: manifest.pages, inMemoryInk: [:], package: package), format: format)
    }

    init(input: NotebookExporter.Input, format: Format = .pdf) {
        self.format = format
        shape = input.pages.first.map { $0.size.width / max($0.size.height, 1) } ?? 0.77
        task = Task { [weak self] in
            let report: @Sendable (Double) async -> Void = { value in
                await MainActor.run { self?.progress = max(self?.progress ?? 0, value) }
            }
            let work = Task.detached(priority: .userInitiated) { () throws -> [URL] in
                switch format {
                case .pdf: [try await NotebookExporter.export(input, progress: report)]
                case .images: try await NotebookExporter.exportImages(input, progress: report)
                case .timelapse: [try await InkTimelapse.export(input, progress: report)]
                }
            }
            do {
                let urls = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                if self?.state == .running { self?.state = .finished(urls) }
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
                case .finished(let urls):
                    if job.format == .timelapse, let url = urls.first {
                        LoopingVideo(url: url)
                            .aspectRatio(job.shape, contentMode: .fit)
                            .frame(maxHeight: 420)
                            .overlay { Rectangle().strokeBorder(Color.hairline, lineWidth: 1) }
                            .accessibilityElement()
                            .accessibilityLabel(Text("The page being written, playing over and over"))
                            .accessibilityAddTraits(.isImage)
                            .accessibilityIdentifier("export.preview")
                    }
                    Label(readyText(urls.count), systemImage: "checkmark.circle").font(.headline)
                        .accessibilityIdentifier("export.ready")
                    HStack(spacing: Space.x3) {
                        Button { sharing = true } label: { Label("Share", systemImage: "square.and.arrow.up") }
                            .prominentButton()
                        if job.format != .timelapse {
                            Button { print(urls) } label: { Label(String(localized: "export.print", defaultValue: "Print"), systemImage: "printer") }
                                .buttonStyle(.bordered)
                        }
                    }
                    .sheet(isPresented: $sharing) { ShareSheet(items: urls) }
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                case .cancelled:
                    Text("Export cancelled.")
                }
            }
            .padding(Space.x8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.surface)
            .navigationTitle(job.format == .pdf ? Text("Export PDF") : job.format == .images ? Text("Export Images") : Text("Export Video"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents(job.format == .timelapse ? [.large] : [.medium])
        .onDisappear { if job.state == .running { job.cancel() } }
    }

    private func readyText(_ count: Int) -> String {
        switch job.format {
        case .pdf: String(localized: "Your PDF is ready.")
        case .images: count == 1 ? String(localized: "Your image is ready.") : String(localized: "Your \(count) images are ready.")
        case .timelapse: String(localized: "Your video is ready.")
        }
    }

    private func print(_ urls: [URL]) {
        guard let first = urls.first else { return }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.jobName = first.deletingPathExtension().lastPathComponent
        info.outputType = .general
        controller.printInfo = info
        if urls.count == 1 { controller.printingItem = first } else { controller.printingItems = urls }
        controller.present(animated: true)
    }
}

/// A film playing silently over and over, without controls: the preview of an exported time-lapse.
struct LoopingVideo: UIViewRepresentable {
    let url: URL

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var looper: AVPlayerLooper?
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        let player = AVQueuePlayer()
        player.isMuted = true
        view.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        (view.layer as? AVPlayerLayer)?.player = player
        (view.layer as? AVPlayerLayer)?.videoGravity = .resizeAspect
        player.play()
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {}

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        (view.layer as? AVPlayerLayer)?.player?.pause()
        view.looper = nil
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
