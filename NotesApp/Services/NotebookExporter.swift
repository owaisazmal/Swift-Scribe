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

    static func export(_ input: Input, progress: @escaping @Sendable (Double) async -> Void) async throws -> URL {
        let interval = signposter.beginInterval("Export", "\(input.pages.count) pages")
        defer { signposter.endInterval("Export", interval) }
        let name = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(name.isEmpty ? "Untitled" : name).pdf")

        var inks: [PKDrawing] = []
        for (index, page) in input.pages.enumerated() {
            try Task.checkCancellation()
            if let ink = input.inMemoryInk[page.id] {
                inks.append(ink)
            } else if case .ink(let drawing, _) = await input.package.readInk(page.id) {
                inks.append(drawing)
            } else {
                inks.append(PKDrawing())
            }
            await progress(Double(index + 1) / Double(input.pages.count) * 0.2)
        }

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: input.title, kCGPDFContextCreator as String: "Swift Scribe"]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: input.pages.first?.size ?? PageSize.letter.points), format: format)
        let assets = input.package.assetsDirectory
        let data = renderer.pdfData { context in
            for (index, page) in input.pages.enumerated() {
                if Task.isCancelled { return }
                let bounds = CGRect(origin: .zero, size: page.size)
                context.beginPage(withBounds: bounds, pageInfo: [:])
                PageRenderer.drawBackground(page, assets: assets, in: context.cgContext, size: page.size)
                let ink = inks[index]
                if !ink.strokes.isEmpty {
                    var image: UIImage?
                    UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                        image = ink.image(from: bounds, scale: 3)
                    }
                    image?.draw(in: bounds)
                }
                let fraction = 0.2 + 0.8 * Double(index + 1) / Double(input.pages.count)
                Task { await progress(fraction) }
            }
        }
        try Task.checkCancellation()
        try data.write(to: url, options: .atomic)
        await progress(1)
        return url
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
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try await NotebookExporter.export(input) { value in
                        await MainActor.run { self?.progress = max(self?.progress ?? 0, value) }
                    }
                }.value
                self?.state = .finished(url)
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
