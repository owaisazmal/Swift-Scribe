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
        try renderer.writePDF(to: url) { context in
            for (index, page) in input.pages.enumerated() {
                if Task.isCancelled { return }
                autoreleasepool {
                    let bounds = CGRect(origin: .zero, size: page.size)
                    context.beginPage(withBounds: bounds, pageInfo: [:])
                    PageRenderer.drawBackground(page, assets: assets, in: context.cgContext, size: page.size)
                    let ink = input.inMemoryInk[page.id] ?? savedInk(page, in: input.package)
                    if !ink.strokes.isEmpty {
                        var image: UIImage?
                        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
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

    init(document: NotebookDocument) {
        var inMemory: [UUID: PKDrawing] = [:]
        for page in document.pages { if let ink = document.loadedInk(page.id) { inMemory[page.id] = ink } }
        let input = NotebookExporter.Input(title: document.title, pages: document.pages, inMemoryInk: inMemory, package: document.package)
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
                            .buttonStyle(.borderedProminent)
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
