import SwiftUI

struct ScribeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var store
    @Environment(AppModel.self) private var app
    @AppStorage(SettingsKey.drawingInput) private var drawingInput: DrawingInput = .system
    @AppStorage(SettingsKey.defaultTemplate) private var template: PaperTemplate = .narrowRuled
    @AppStorage(SettingsKey.defaultPaperColor) private var color: PaperColor = .white
    @AppStorage(SettingsKey.defaultPageSize) private var size: PageSize = .letter
    @State private var backupSize: String?

    private let repository = URL(string: "https://github.com/owaisazmal/Swift-Scribe")!

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Draw With", selection: $drawingInput) {
                        ForEach(DrawingInput.allCases) { Text($0.displayName).tag($0) }
                    }
                } header: {
                    Text("Input")
                } footer: {
                    Text("“System Setting” follows Settings › Apple Pencil › Only Draw with Apple Pencil.")
                }

                Section("New Notebooks") {
                    Picker("Template", selection: $template) {
                        ForEach(PaperTemplate.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Paper Colour", selection: $color) {
                        ForEach(PaperColor.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Page Size", selection: $size) {
                        ForEach(PageSize.allCases) { Text($0.displayName).tag($0) }
                    }
                }

                if let problem = app.migrationProblem {
                    Section {
                        Text(problem)
                    } header: {
                        Text("Moving to the New Format")
                    } footer: {
                        Text("Your original notebooks are untouched. Swift Scribe tries again each time it opens.")
                    }
                }

                if let backupSize {
                    Section {
                        LabeledContent("Previous-format backup", value: backupSize)
                    } footer: {
                        Text("Your notebooks were moved to the new format. The original files are kept in Backups/v1 inside the app's storage.")
                    }
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                    NavigationLink("Acknowledgements") { AcknowledgementsView() }
                    Link(destination: repository) {
                        Label("Source Code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Link(destination: repository.appendingPathComponent("issues")) {
                        Label("Report a Problem or Request a Feature", systemImage: "exclamationmark.bubble")
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Swift Scribe is free and open source. No ads, no subscriptions, no tracking — your notes stay on your device.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.surface)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                let backup = store.root.backups.appending(path: "v1", directoryHint: .isDirectory)
                backupSize = await Task.detached { Self.size(of: backup) }.value
            }
        }
    }

    nonisolated static func size(of directory: URL) -> String? {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return nil }
        var total = 0
        for case let url as URL in enumerator { total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        return total > 0 ? total.formatted(.byteCount(style: .file)) : nil
    }
}

struct AcknowledgementsView: View {
    private struct Entry: Identifiable {
        let id: String
        let name: String
        let use: String
        let license: String
    }

    private var entries: [Entry] {
        [("Fraunces", "Library headings, cloth labels and empty states", "OFL-Fraunces"),
         ("Bricolage Grotesque", "Print cover titles", "OFL-BricolageGrotesque")].map { name, use, file in
            let url = Bundle.main.url(forResource: file, withExtension: "txt")
            return Entry(id: file, name: name, use: use, license: url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "")
        }
    }

    var body: some View {
        List {
            ForEach(entries) { entry in
                Section {
                    Text(entry.use).foregroundStyle(Color.inkSecondary)
                    DisclosureGroup("SIL Open Font License 1.1") {
                        Text(entry.license).font(.footnote.monospaced()).textSelection(.enabled)
                    }
                } header: {
                    Text(entry.name).font(.display(20, relativeTo: .title3)).textCase(nil).foregroundStyle(Color.ink)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.surface)
        .navigationTitle("Acknowledgements")
    }
}
